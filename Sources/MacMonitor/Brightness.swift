import AppKit

final class BrightnessController {
    private let queue = DispatchQueue(label: "MacMonitor.DDC", qos: .userInitiated)
    private var hardwareMax: [String: Int] = [:]
    private var confirmedHardware: [String: Double] = [:]
    private let helper: ([String]) -> (Int32, String)
    // Additional dimming is opt-in for this session. Launching the app must
    // not change the picture that was visible before it started.
    private var extraDimming = Set<String>()
    private var overlayLevels: [String: Double] = [:]
    private var windows: [String: NSWindow] = [:]
    private var scheduled: [String: DispatchWorkItem] = [:]
    private var generations: [String: Int] = [:]
    init(helper: @escaping ([String]) -> (Int32, String) = BrightnessController.runHelper) {
        self.helper = helper
    }
    var onStatus: ((String, Double?, String) -> Void)?
    var screenForID: ((String) -> NSScreen?)?
    func supportsHardware(_ id: String) -> Bool { hardwareMax[id] != nil }
    func usesExtraDimming(_ id: String) -> Bool { extraDimming.contains(id) }
    func minimum(_ id: String) -> Double { supportsHardware(id) && !usesExtraDimming(id) ? 0 : 0.05 }
    func setExtraDimming(_ enabled: Bool, monitor: Monitor) {
        if enabled { extraDimming.insert(monitor.id) } else { extraDimming.remove(monitor.id) }
        set(monitor.brightness, monitor: monitor)
    }
    private func hardwareStatus(_ id: String) -> String {
        usesExtraDimming(id) ? "Độ sáng màn hình · DDC + giảm sáng thêm" : "Độ sáng màn hình · DDC"
    }

    static func runHelper(_ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("m1ddc")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    func probe(_ monitor: Monitor) {
        let id = monitor.id
        let generation = (generations[id] ?? 0) + 1
        generations[id] = generation
        queue.async { [weak self] in
            guard let self else { return }
            let response = self.helper(["display", "id=\(monitor.displayID)", "get-json", "luminance"])
            let reading = response.0 == 0 ? try? JSONDecoder().decode(BrightnessReading.self, from: Data(response.1.utf8)) : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generations[id] == generation else { return }
                // DDC/CI brightness is normally 0–100. Some HDMI paths yield corrupt
                // bytes; reject implausible maxima and keep control predictable.
                if let reading, let value = reading.normalized {
                    self.hardwareMax[id] = reading.maximum
                    self.confirmedHardware[id] = value
                    // A probe only observes hardware. Do not restore an old
                    // value or create/change an overlay on launch or refresh.
                    self.onStatus?(id, value, self.hardwareStatus(id))
                } else if self.hardwareMax[id] != nil {
                    self.onStatus?(id, nil, "Độ sáng màn hình · Chưa đọc được, giữ mức gần nhất")
                } else {
                    self.onStatus?(id, nil, "Giảm sáng phần mềm · DDC không phản hồi")
                }
            }
        }
    }

    func set(_ value: Double, monitor: Monitor) {
        let value = DisplayPolicy.brightness(value, minimum: minimum(monitor.id))
        generations[monitor.id, default: 0] += 1
        let generation = generations[monitor.id]
        scheduled[monitor.id]?.cancel()
        if let maximum = hardwareMax[monitor.id] {
            if usesExtraDimming(monitor.id) { applyOverlay(value, id: monitor.id) }
            else { clearOverlay(monitor.id) }
            onStatus?(monitor.id, nil, "Đang chỉnh và kiểm tra độ sáng…")
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let requested = Int((value * Double(maximum)).rounded())
                let result = self.helper(["display", "id=\(monitor.displayID)", "set", "luminance", "\(requested)"])
                // A successful I2C write only confirms transport, not that the
                // monitor applied it. Publish the validated reply after settling.
                var reading: BrightnessReading?
                if result.0 == 0 {
                    Thread.sleep(forTimeInterval: 0.12)
                    for _ in 0..<2 {
                        let response = self.helper(["display", "id=\(monitor.displayID)", "get-json", "luminance"])
                        reading = response.0 == 0 ? try? JSONDecoder().decode(BrightnessReading.self, from: Data(response.1.utf8)) : nil
                        if let reading, reading.matches(requested: requested, maximum: maximum) { break }
                        Thread.sleep(forTimeInterval: 0.12)
                    }
                }
                let verified = reading
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generations[monitor.id] == generation else { return }
                    if let verified, let actual = verified.normalized {
                        self.hardwareMax[monitor.id] = verified.maximum
                        self.confirmedHardware[monitor.id] = actual
                        if self.usesExtraDimming(monitor.id) { self.applyOverlay(DisplayPolicy.brightness(actual), id: monitor.id) }
                        let status = verified.matches(requested: requested, maximum: maximum)
                            ? self.hardwareStatus(monitor.id) : "Màn hình chưa áp dụng mức yêu cầu · DDC"
                        self.onStatus?(monitor.id, actual, status)
                    } else {
                        // Keep the known backend; a transient write failure must
                        // not unexpectedly add another dimming layer.
                        let last = self.confirmedHardware[monitor.id]
                        if self.usesExtraDimming(monitor.id), let last { self.applyOverlay(DisplayPolicy.brightness(last), id: monitor.id) }
                        self.onStatus?(monitor.id, last, "Chưa xác minh được mức sáng · Thử đọc lại")
                    }
                }
            }
            scheduled[monitor.id] = item
            queue.asyncAfter(deadline: .now() + 0.06, execute: item)
        } else {
            // A user adjustment must not be overwritten by an in-flight probe.
            onStatus?(monitor.id, value, "Giảm sáng phần mềm")
            applyOverlay(value, id: monitor.id)
        }
    }

    private func applyOverlay(_ value: Double, id: String) {
        guard value < 0.999, let screen = screenForID?(id) else { clearOverlay(id); return }
        let window: NSWindow
        if let existing = windows[id] { window = existing } else {
            window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            windows[id] = window
        }
        overlayLevels[id] = value
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 1 - value
        window.orderFrontRegardless()
    }
    func updateOverlays(_ monitors: [Monitor]) {
        for monitor in monitors where windows[monitor.id] != nil {
            if monitor.connected, let value = overlayLevels[monitor.id] { applyOverlay(value, id: monitor.id) }
            else { clearOverlay(monitor.id) }
        }
    }
    func clearOverlay(_ id: String) { windows.removeValue(forKey: id)?.close(); overlayLevels.removeValue(forKey: id) }
    func remove(_ id: String) {
        generations[id, default: 0] += 1
        scheduled.removeValue(forKey: id)?.cancel()
        // Retain a validated hardware range across a temporary disconnect;
        // a failed reconnect read must not replace it with software dimming.
        clearOverlay(id)
    }
    func stop() {
        scheduled.values.forEach { $0.cancel() }
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }
}
