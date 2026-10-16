import AppKit
import Combine
import Darwin

final class SidecarController: ObservableObject {
    @Published private(set) var devices: [SidecarDevice] = []
    @Published private(set) var supported = true
    @Published private(set) var scanning = false
    @Published private(set) var changing = false
    @Published private(set) var repairing = false
    @Published private(set) var message: String?
    private(set) var displayIDs = Set<CGDirectDisplayID>()
    var canChange: () -> Bool = { true }
    var onWillChange: (() -> Void)?
    var onDidChange: (() -> Void)?
    private var process: Process?
    private var timeout: DispatchWorkItem?
    private var repairRetry: DispatchWorkItem?
    private var generation = 0
    private var stopped = false
    private var lastScan = Date.distantPast
    private let queue = DispatchQueue(label: "local.anle.MacMonitor.Sidecar", qos: .userInitiated)

    func refresh(force: Bool = false) {
        guard !stopped, !scanning, !changing, !repairing, force || Date().timeIntervalSince(lastScan) > 5 else { return }
        scanning = true
        run(["devices"]) { [weak self] snapshot in
            guard let self else { return }
            self.scanning = false
            if let snapshot { self.update(snapshot) }
            else { self.message = "Chưa đọc được danh sách iPad. Bấm Tìm lại để thử lại." }
        }
    }
    func repairDiscovery() {
        guard !stopped, canChange(), SidecarDiscoveryRepair.allowed(
            uid: getuid(), effectiveUID: geteuid(), connected: devices.contains(where: \.connected),
            busy: scanning || changing || repairing),
            let arguments = SidecarDiscoveryRepair.arguments(uid: getuid(), effectiveUID: geteuid()) else { return }
        repairing = true; message = nil
        onDidChange?()
        restartDiscoveryService(arguments) { [weak self] status in
            guard let self, !self.stopped else { return }
            // Exit 1 also covers a service which was not running. Discovery
            // itself asks macOS to start its normal per-user service again.
            guard status == 0 || status == 1 else {
                self.repairing = false
                self.message = "Chưa làm mới được dịch vụ tìm thiết bị. Thử khởi động lại Mac hoặc kết nối iPad bằng USB."
                self.onDidChange?(); return
            }
            self.scheduleRepairScan(attempt: 0)
        }
    }
    private func scheduleRepairScan(attempt: Int) {
        guard !stopped, repairing else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.repairing else { return }
            self.scanning = true
            self.run(["devices"]) { [weak self] snapshot in
                guard let self, !self.stopped, self.repairing else { return }
                self.scanning = false
                if let snapshot { self.update(snapshot) }
                if let snapshot, snapshot.supported, snapshot.error.isEmpty, !snapshot.devices.isEmpty {
                    self.repairing = false
                    self.message = "Đã tìm thấy iPad. Bấm Kết nối cạnh tên thiết bị."
                    self.onDidChange?()
                } else if attempt + 1 < SidecarDiscoveryRepair.retryDelays.count && snapshot?.supported != false {
                    self.scheduleRepairScan(attempt: attempt + 1)
                } else {
                    self.repairing = false
                    if snapshot?.supported != false {
                        self.message = "Đã thử làm mới nhưng chưa thấy iPad. Mở khóa iPad, kiểm tra Handoff và cùng tài khoản Apple, hoặc thử cắm dây USB."
                    }
                    self.onDidChange?()
                }
            }
        }
        repairRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SidecarDiscoveryRepair.retryDelays[attempt], execute: work)
    }
    private func restartDiscoveryService(_ arguments: [String], completion: @escaping (Int32?) -> Void) {
        generation += 1
        let token = generation
        let task = Process()
        task.executableURL = SidecarDiscoveryRepair.executable
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        process = task
        var completed = false
        func finish(_ status: Int32?) {
            guard !completed, !self.stopped, token == self.generation else { return }
            completed = true; self.timeout?.cancel(); self.timeout = nil; self.process = nil
            completion(status)
        }
        task.terminationHandler = { ended in
            DispatchQueue.main.async { finish(ended.terminationReason == .exit ? ended.terminationStatus : nil) }
        }
        do { try task.run() }
        catch { finish(nil); return }
        let work = DispatchWorkItem {
            if task.isRunning { task.terminate() }
            finish(nil)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
    private func update(_ snapshot: SidecarSnapshot) {
        supported = snapshot.supported
        devices = snapshot.devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        displayIDs = snapshot.displayIDs
        lastScan = Date()
        if snapshot.error.isEmpty { message = nil }
        else { message = errorMessage(snapshot.error) }
        onDidChange?()
    }
    func toggle(_ device: SidecarDevice) {
        guard !stopped, !scanning, !changing, !repairing, canChange(),
              let current = devices.first(where: { $0.id == device.id }), current == device else { return }
        if !device.connected && devices.contains(where: \.connected) {
            message = "Hãy ngắt iPad đang kết nối trước khi chọn iPad khác."; return
        }
        // Never disconnect the last visible desktop (for example a headless Mac).
        if device.connected {
            guard device.displayID != 0,
                  currentDesktopOutputs().contains(where: { $0.active && $0.id != device.displayID }) else {
                message = "Chưa thể ngắt iPad khi không xác định được màn hình khác đang hoạt động."; return
            }
        }
        let oldOutputs = currentDesktopOutputs()
        changing = true; message = nil
        onWillChange?()
        run([device.connected ? "disconnect" : "connect", device.id]) { [weak self] snapshot in
            guard let self else { return }
            guard let snapshot else {
                self.changing = false
                self.message = "Sidecar phản hồi quá lâu. Kiểm tra iPad rồi bấm Tìm lại."
                self.onDidChange?()
                return
            }
            self.update(snapshot)
            if !snapshot.supported || (!snapshot.error.isEmpty && snapshot.error != "timeout") {
                self.changing = false
                self.onDidChange?()
                return
            }
            // Sidecar can report completion before WindowServer has finished.
            self.verify(device, connecting: !device.connected, oldOutputs: oldOutputs, attempt: 0)
        }
    }
    private func verify(_ device: SidecarDevice, connecting: Bool, oldOutputs: [DesktopOutput], attempt: Int) {
        guard !stopped else { return }
        run(["devices"]) { [weak self] snapshot in
            guard let self else { return }
            if let snapshot { self.update(snapshot) }
            let actual = snapshot?.devices.first(where: { $0.id == device.id })
            let stateMatches = snapshot?.supported == true && snapshot?.error.isEmpty == true &&
                (connecting ? actual?.connected == true : actual?.connected != true)
            if stateMatches {
                if connecting, let id = actual?.displayID, id != 0 {
                    self.keepDesktopLayout(oldOutputs, ipad: id)
                }
                self.changing = false
                if self.message == nil { self.message = connecting ? "Đã kết nối iPad qua Sidecar." : "Đã ngắt kết nối iPad." }
                self.onDidChange?()
            } else if snapshot != nil && attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.verify(device, connecting: connecting, oldOutputs: oldOutputs, attempt: attempt + 1)
                }
            } else {
                self.changing = false
                self.message = self.message ?? "Chưa xác nhận được trạng thái iPad. Kiểm tra iPad rồi bấm Tìm lại."
                self.onDidChange?()
            }
        }
    }
    private func keepDesktopLayout(_ previous: [DesktopOutput], ipad: CGDirectDisplayID) {
        // Only modify the newly connected iPad's mirror relationship. In
        // particular, preserve every existing physical/virtual HiDPI mirror.
        guard !previous.contains(where: { $0.id == ipad && $0.active }),
              CGDisplayIsOnline(ipad) != 0 else { return }
        let live = currentDesktopOutputs()
        guard let placements = SidecarLayout.placements(previous: previous, current: live, ipad: ipad) else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        if CGDisplayMirrorsDisplay(ipad) != 0,
           CGConfigureDisplayMirrorOfDisplay(config, ipad, kCGNullDirectDisplay) != .success {
            CGCancelDisplayConfiguration(config); return
        }
        for item in placements {
            if CGConfigureDisplayOrigin(config, item.id, item.x, item.y) != .success {
                CGCancelDisplayConfiguration(config); return
            }
        }
        if CGCompleteDisplayConfiguration(config, .forSession) != .success {
            message = "iPad đã kết nối. Bạn có thể chỉnh vị trí trong Sắp xếp màn hình."
        }
    }
    private func errorMessage(_ code: String) -> String {
        switch code {
        case "unsupported": return "Sidecar chưa khả dụng trên phiên bản macOS này."
        case "unavailable": return "Chưa tìm thấy iPad đã chọn. Mở khóa iPad rồi bấm Tìm lại."
        case "other-connected": return "Hãy ngắt iPad đang kết nối trước khi chọn iPad khác."
        case "timeout": return "Sidecar phản hồi quá lâu. Kiểm tra iPad rồi bấm Tìm lại."
        default: return "Chưa kết nối được với iPad. Kiểm tra cùng tài khoản Apple, Wi-Fi, Bluetooth hoặc dây USB."
        }
    }
    private func run(_ arguments: [String], completion: @escaping (SidecarSnapshot?) -> Void) {
        generation += 1
        let token = generation
        let task = Process(), output = Pipe()
        task.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SidecarTool")
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        process = task
        var finished = false
        func finish(_ snapshot: SidecarSnapshot?) {
            guard !finished, !self.stopped, token == self.generation else { return }
            finished = true; self.timeout?.cancel(); self.timeout = nil; self.process = nil
            completion(snapshot)
        }
        do { try task.run() }
        catch { finish(nil); return }
        // Drain the pipe while the child is running; waiting for termination
        // first can deadlock if discovery returns many devices.
        queue.async {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let snapshot = task.terminationStatus == 0 ? try? SidecarSnapshot.decode(data) : nil
            DispatchQueue.main.async { finish(snapshot) }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, token == self.generation else { return }
            if task.isRunning { task.terminate() }
            finish(nil)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (arguments.first == "devices" ? 8 : 25), execute: work)
    }
    func stop() {
        stopped = true; generation += 1; timeout?.cancel(); timeout = nil
        repairRetry?.cancel(); repairRetry = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        // A user-created Sidecar session belongs to macOS; quitting the app
        // never disconnects the iPad or changes its native resolution.
    }
}
