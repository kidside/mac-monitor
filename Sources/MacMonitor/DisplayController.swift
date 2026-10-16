import AppKit
import Combine

final class DisplayController: ObservableObject {
    @Published var appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "automatic" {
        didSet {
            UserDefaults.standard.set(appLanguage, forKey: "appLanguage")
            NotificationCenter.default.post(name: Notification.Name("MacMonitorLanguageChanged"), object: nil)
        }
    }
    @Published var monitors: [Monitor] = []
    @Published var message: String?
    @Published var busy = false
    @Published var pendingTitle: String?
    @Published var secondsRemaining = 0
    @Published var shortcutReady = false
    @Published var shortcutFeedback: String?
    @Published var shortcutsEnabled = UserDefaults.standard.object(forKey: "shortcutsEnabled") as? Bool ?? true {
        didSet { keys.enabled = shortcutsEnabled; UserDefaults.standard.set(shortcutsEnabled, forKey: "shortcutsEnabled") }
    }
    @Published var shortcutTarget = UserDefaults.standard.string(forKey: "shortcutTarget") ?? "pointer" {
        didSet { UserDefaults.standard.set(shortcutTarget, forKey: "shortcutTarget") }
    }
    @Published var restoreOnReconnect = UserDefaults.standard.object(forKey: "restoreOnReconnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(restoreOnReconnect, forKey: "restoreOnReconnect") }
    }
    let keys = BrightnessKeys()
    let brightness = BrightnessController()
    let hud = BrightnessHUD()
    var onPresent: (() -> Void)?
    var onDisplayConfigurationWillChange: (() -> Void)?
    private var timer: Timer?
    private var tick = 0
    private var customSizes: [String: [HiDPISize]] = [:]
    private var profiles: [String: ScreenProfile] = [:]
    private var virtualLayouts: [String: [RecoveryRecord]] = [:]
    private var virtuals: [String: MMVirtualScreen] = [:]
    private var originals: [String: RecoveryRecord] = [:]
    private var disabled = Set<String>()
    private var disabledConfigurations: [String: RecoveryRecord] = [:]
    private var disabledLayouts: [String: [RecoveryRecord]] = [:]
    private var disconnectRetries: [String: [Date]] = [:]
    private var probing = Set<String>()
    private var pendingRollback: (() -> Void)?
    private var pendingCommit: (() -> Void)?
    private var pendingDeadline: Date?
    private var watchdog: Process?
    private var stopping = false
    private var operationGeneration = 0
    static var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMonitor/recovery.json")
    }
    var external: [Monitor] { monitors.filter { !$0.builtin } }
    var virtualSupported: Bool { MMVirtualScreen.isSupported() }
    var canChange: Bool { !busy && pendingTitle == nil }

    private let recoveryFileOverride: URL?
    private var recoveryFileURL: URL { recoveryFileOverride ?? Self.recoveryURL }

    init(recoveryFileURL: URL? = nil) {
        self.recoveryFileOverride = recoveryFileURL
        if let data = UserDefaults.standard.data(forKey: "customHiDPISizes"),
           let saved = try? JSONDecoder().decode([String: [HiDPISize]].self, from: data) { customSizes = saved }

        if let data = UserDefaults.standard.data(forKey: "profiles"), let saved = try? JSONDecoder().decode([String: ScreenProfile].self, from: data) { profiles = saved }
        brightness.screenForID = { [weak self] id in self?.screen(for: id) }
        brightness.onStatus = { [weak self] id, value, status in
            guard let self, let i = self.monitors.firstIndex(where: { $0.id == id }) else { return }
            if let value { self.monitors[i].brightness = value }
            self.monitors[i].brightnessBackend = status
        }
        keys.onStep = { [weak self] step in self?.handleBrightnessKey(step) ?? false }
        keys.onRecognized = { [weak self] key, handled in
            self?.shortcutFeedback = handled ? "Đã nhận \(key)" : "Đã nhận \(key) · chọn màn hình để chỉnh sáng"
        }
        keys.enabled = shortcutsEnabled
    }

    func start() {
        // Recovery is not a saved layout preference. An old recovery file must
        // never overwrite active desktops or another app's mirror configuration.
        if let data = try? Data(contentsOf: recoveryFileURL), let records = try? JSONDecoder().decode([RecoveryRecord].self, from: data) {
            let outputs = currentDesktopOutputs()
            let livePositions = DesktopPolicy.positions(outputs)
            let targets = DesktopPolicy.startupRecovery(records, outputs: outputs)
            if targets.isEmpty || (restoreRecords(targets) && applyDisplayPlacements(livePositions)) {
                try? FileManager.default.removeItem(at: recoveryFileURL)
            } else { message = "Chưa khôi phục được cấu hình cũ. Thử kết nối lại màn hình." }
        }
        refresh()
        keys.start()
        shortcutReady = keys.isRunning
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.stopping else { return }
            self.tick += 1
            self.keys.start()
            self.shortcutReady = self.keys.isRunning
            if let deadline = self.pendingDeadline {
                self.secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if self.secondsRemaining == 0 { self.revert() }
            }
            if self.tick % 3 == 0 && !self.busy { self.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.probing.removeAll(); self?.refresh() }
        }
    }

    func refresh() {
        guard !stopping else { return }
        let old = Dictionary(uniqueKeysWithValues: monitors.map { ($0.id, $0) })
        let virtualIDs = Set(virtuals.values.map(\.displayID))
        let ids = MMAllDisplays().map(\.uint32Value).filter { !virtualIDs.contains($0) && CGDisplayVendorNumber($0) != 0x4D4D }
        var next: [Monitor] = []
        for id in ids {
            let online = CGDisplayIsOnline(id) != 0
            let connected = online && (CGDisplayIsActive(id) != 0 || CGDisplayMirrorsDisplay(id) != 0)
            let reportedUUID = displayUUID(id)
            // UUID/EDID can be unavailable while software-disabled. The display
            // ID still identifies the same output during this session.
            let uuid = reportedUUID == "display-\(id)"
                ? old.values.first(where: { $0.displayID == id })?.id ?? reportedUUID : reportedUUID
            let size = CGDisplayScreenSize(id)
            let effective = virtuals[uuid]?.displayID ?? id
            let mode = currentDisplayChoice(effective) ?? currentDisplayChoice(id)
            let screenName = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?.localizedName
            var monitor = Monitor(id: uuid, displayID: id, name: screenName ?? MMDisplayName(id), online: online,
                                  connected: connected, builtin: CGDisplayIsBuiltin(id) != 0,
                                  inches: hypot(size.width, size.height) / 25.4,
                                  modes: displayModes(id), current: mode.map { $0.label } ?? "Chưa có tín hiệu",
                                  currentModeID: mode?.id, hiDPI: mode.map { $0.pixelWidth > $0.width } ?? false)
            monitor.virtual = virtuals[uuid] != nil
            let mainID = CGMainDisplayID()
            monitor.main = effective == mainID || CGDisplayMirrorsDisplay(id) == mainID
            let panel = MMPanelPixelSize(id)
            if panel.width > 0 && panel.height > 0 { monitor.panel = HiDPISize(width: Int(panel.width), height: Int(panel.height)) }
            else if let previous = old[uuid] { monitor.panel = previous.panel }
            else if let largest = monitor.modes.filter({ !$0.hiDPI }).max(by: { $0.width * $0.height < $1.width * $1.height }) {
                monitor.panel = HiDPISize(width: largest.width, height: largest.height)
            }
            if let previous = old[uuid] {
                // Disabled outputs may temporarily lose their name and physical
                // size in CoreDisplay; keep the card's identity visible.
                if !connected || monitor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    monitor.name = previous.name
                    monitor.inches = previous.inches
                }
                monitor.brightness = previous.brightness
                monitor.brightnessBackend = previous.brightnessBackend
                if !previous.connected && connected { probing.remove(uuid) }
            }
            if !connected && monitor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            next.append(monitor)
        }
        // Keep only software-disabled outputs. Physically disconnected displays
        // should disappear from the menu instead of becoming empty cards.
        for (uuid, previous) in old where !next.contains(where: { $0.id == uuid }) && disabled.contains(uuid) {
            var remembered = previous
            remembered.connected = false; remembered.online = false
            remembered.virtual = false
            next.append(remembered)
        }
        for (uuid, _) in old where !next.contains(where: { $0.id == uuid }) && !disabled.contains(uuid) {
            probing.remove(uuid)
            brightness.remove(uuid)
        }
        monitors = next.sorted { $0.builtin != $1.builtin ? !$0.builtin : $0.id < $1.id }
        // Hotplug/WindowServer reconfiguration can reactivate an output after
        // a successful session disable. Reconcile only explicit off requests,
        // never physically missing outputs or the last remaining desktop.
        if maintainDisconnectedDisplay() { return }
        // Release virtual desktops when their physical output disappears.
        for uuid in Array(virtuals.keys) where !monitors.contains(where: { $0.id == uuid && $0.online }) {
            virtuals.removeValue(forKey: uuid)
            brightness.remove(uuid)
        }
        for monitor in external where monitor.connected && !probing.contains(monitor.id) {
            probing.insert(monitor.id)
            brightness.probe(monitor)
        }
        brightness.updateOverlays(monitors)
        // Reapply a confirmed profile after a cable reconnect, never on the initial launch.
        if restoreOnReconnect && canChange {
            if let monitor = external.first(where: { item in
                item.connected && !item.virtual && old[item.id]?.connected == false && profiles[item.id] != nil && !disabled.contains(item.id)
            }) { restoreProfile(monitor) }
        }
    }

    @discardableResult private func maintainDisconnectedDisplay() -> Bool {
        guard canChange, let monitor = external.first(where: { disabled.contains($0.id) && $0.connected }),
              DisplayPolicy.canDisconnect(monitor.id, monitors: monitors) else { return false }
        let now = Date()
        let attempts = (disconnectRetries[monitor.id] ?? []).filter { now.timeIntervalSince($0) < 60 }
        guard attempts.count < 3 else {
            disabled.remove(monitor.id)
            disconnectRetries.removeValue(forKey: monitor.id)
            message = "macOS liên tục bật lại \(monitor.name). Đã dừng giữ ngắt để tránh nhấp nháy. Bạn có thể thử lại công tắc."
            return false
        }
        disconnectRetries[monitor.id] = attempts + [now]
        busy = true
        let generation = operationGeneration
        onDisplayConfigurationWillChange?()
        let result = MMSetEnabled(monitor.displayID, false)
        guard result == .success else {
            busy = false; disabled.remove(monitor.id)
            message = "macOS đã bật lại \(monitor.name) và chưa ngắt lại được. Bạn có thể thử lại công tắc."
            return false
        }
        brightness.remove(monitor.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.stopping, self.operationGeneration == generation else { return }
            self.busy = false
            self.refresh()
        }
        return true
    }

    func screen(for uuid: String) -> NSScreen? {
        guard let monitor = monitors.first(where: { $0.id == uuid }) else { return nil }
        let effective = virtuals[uuid]?.displayID ?? monitor.displayID
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == effective }
    }
    func setBrightness(_ value: Double, id: String) {
        guard let i = monitors.firstIndex(where: { $0.id == id && $0.connected && !$0.builtin }) else { return }
        monitors[i].brightness = DisplayPolicy.brightness(value, minimum: brightness.minimum(id))
        brightness.set(monitors[i].brightness, monitor: monitors[i])
    }
    func setExtraDimming(_ enabled: Bool, id: String) {
        guard let monitor = monitors.first(where: { $0.id == id && $0.connected }) else { return }
        brightness.setExtraDimming(enabled, monitor: monitor)
    }
    func retryBrightness(_ id: String) {
        guard let monitor = monitors.first(where: { $0.id == id }) else { return }
        brightness.probe(monitor)
    }
    private func handleBrightnessKey(_ step: Double) -> Bool {
        let available = external.filter(\.connected)
        let targets: [Monitor]
        if shortcutTarget == "all" { targets = available }
        else if shortcutTarget == "pointer" {
            let underPointer = available.filter { screen(for: $0.id)?.frame.contains(NSEvent.mouseLocation) == true }
            // Keep system brightness behavior when the pointer is on an active built-in screen.
            if !underPointer.isEmpty { targets = underPointer }
            else if monitors.contains(where: { $0.builtin && $0.connected }) { targets = [] }
            else { targets = available.filter { $0.displayID == CGMainDisplayID() }.isEmpty ? Array(available.prefix(1)) : available.filter { $0.displayID == CGMainDisplayID() } }
        } else { targets = available.filter { $0.id == shortcutTarget } }
        guard !targets.isEmpty else { return false }
        if step != 0 {
            for monitor in targets {
                let value = DisplayPolicy.brightness(monitor.brightness + step, minimum: brightness.minimum(monitor.id))
                setBrightness(value, id: monitor.id)
                hud.show(name: targets.count > 1 ? "Các màn hình ngoài" : monitor.name, value: value, screen: screen(for: monitor.id))
            }
        }
        return true
    }
    func requestShortcutAccess() {
        keys.start(requestPermission: true)
        shortcutReady = keys.isRunning
        if !shortcutReady, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    private func snapshot(_ monitor: Monitor, reconnect: Bool = false) -> RecoveryRecord {
        let origin = CGDisplayBounds(monitor.displayID).origin
        let mode = CGDisplayCopyDisplayMode(monitor.displayID)
        let profile = mode.map { ScreenProfile(width: $0.width, height: $0.height, virtual: false, pixelWidth: $0.pixelWidth, refresh: $0.refreshRate) }
        return RecoveryRecord(uuid: monitor.id, displayID: monitor.displayID, modeID: mode?.ioDisplayModeID,
                              x: Int32(origin.x), y: Int32(origin.y), reconnect: reconnect, modeProfile: profile)
    }
    @discardableResult private func preserve(_ monitor: Monitor, reconnect: Bool = false) -> Bool {
        if originals[monitor.id] == nil { originals[monitor.id] = snapshot(monitor, reconnect: reconnect) }
        if reconnect { originals[monitor.id]?.reconnect = true }
        do {
            try FileManager.default.createDirectory(at: self.recoveryFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(originals.values)).write(to: self.recoveryFileURL, options: .atomic)
            if watchdog == nil, let executable = Bundle.main.executableURL {
                let process = Process()
                process.executableURL = executable
                process.arguments = ["--watchdog", "\(getpid())", self.recoveryFileURL.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                watchdog = process
            }
            return true
        } catch {
            message = "Không lưu được cấu hình khôi phục: \(error.localizedDescription)"
            return false
        }
    }
    private func error(_ action: String, _ error: CGError) { message = "\(action) không thành công (macOS: \(error.rawValue))."; busy = false }

    func setMainDisplay(_ monitor: Monitor) {
        guard canChange && monitor.connected else { return }
        let outputs = currentDesktopOutputs()
        let source = virtuals[monitor.id]?.displayID ?? (CGDisplayMirrorsDisplay(monitor.displayID) == 0
            ? monitor.displayID : CGDisplayMirrorsDisplay(monitor.displayID))
        guard let layout = DesktopPolicy.mainLayout(outputs, target: source) else {
            message = "Chưa xác định được bố cục để chọn màn hình chính."; return
        }
        let previous = DesktopPolicy.positions(outputs)
        if CGMainDisplayID() == source { refresh(); return }
        message = nil; busy = true
        operationGeneration += 1; let generation = operationGeneration
        onDisplayConfigurationWillChange?()
        guard applyDisplayPlacements(layout, permanently: true) else {
            _ = applyDisplayPlacements(previous, permanently: true); busy = false; refresh()
            message = "Không đổi được màn hình chính. Đã giữ bố cục trước."; return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.stopping, self.operationGeneration == generation else { return }
            guard CGMainDisplayID() == source, displayPlacementsMatch(layout) else {
                _ = applyDisplayPlacements(previous, permanently: true); self.busy = false; self.refresh()
                self.message = "macOS chưa áp dụng đúng màn hình chính. Đã trả lại bố cục trước."; return
            }
            // A user-selected main display is a new baseline, so recovery and
            // virtual-display teardown cannot put the old main back later.
            let positions = Dictionary(uniqueKeysWithValues: layout.map { ($0.id, $0) })
            func relocate(_ record: RecoveryRecord) -> RecoveryRecord {
                guard let physical = resolveDisplay(record.uuid, fallback: record.displayID) else { return record }
                let effective = self.virtuals[record.uuid]?.displayID ?? (CGDisplayMirrorsDisplay(physical) == 0
                    ? physical : CGDisplayMirrorsDisplay(physical))
                guard let position = positions[effective] else { return record }
                return DesktopPolicy.relocated(record, x: position.x, y: position.y)
            }
            self.originals = self.originals.mapValues(relocate)
            self.virtualLayouts = self.virtualLayouts.mapValues { $0.map(relocate) }
            self.disabledLayouts = self.disabledLayouts.mapValues { $0.map(relocate) }
            let inactivePlan = DesktopPolicy.startupRecovery(Array(self.originals.values), outputs: currentDesktopOutputs())
            for recovered in inactivePlan {
                self.originals[recovered.uuid] = recovered
                if let saved = self.disabledConfigurations[recovered.uuid] {
                    self.disabledConfigurations[recovered.uuid] = DesktopPolicy.relocated(saved, x: recovered.x, y: recovered.y)
                }
                self.disabledLayouts = self.disabledLayouts.mapValues { records in
                    records.map { $0.uuid == recovered.uuid ? DesktopPolicy.relocated($0, x: recovered.x, y: recovered.y) : $0 }
                }
            }
            if !self.originals.isEmpty {
                do { try JSONEncoder().encode(Array(self.originals.values)).write(to: self.recoveryFileURL, options: .atomic) }
                catch { self.message = "Không lưu được cấu hình khôi phục: \(error.localizedDescription)" }
            }
            self.busy = false; self.refresh()
        }
    }

    func toggleConnection(_ monitor: Monitor) {
        guard canChange else { return }
        message = nil
        if monitor.connected {
            guard DisplayPolicy.canDisconnect(monitor.id, monitors: monitors) else { message = "Cần giữ ít nhất một màn hình hoạt động để điều khiển máy."; return }
            if monitor.virtual {
                // Suspend the virtual display but retain its saved profile for reconnect.
                removeVirtual(monitor.id, restore: originals[monitor.id]) { [weak self] in
                    if let self, let physical = self.monitors.first(where: { $0.id == monitor.id }) { self.toggleConnection(physical) }
                }
                return
            }
            guard preserve(monitor, reconnect: true) else { return }
            let configuration = snapshot(monitor, reconnect: true)
            let layout = monitors.filter(\.connected).map { snapshot($0, reconnect: $0.id == monitor.id) }
            busy = true
            onDisplayConfigurationWillChange?()
            let result = MMSetEnabled(monitor.displayID, false)
            guard result == .success else { error("Ngắt kết nối", result); return }
            disabled.insert(monitor.id)
            disconnectRetries.removeValue(forKey: monitor.id)
            disabledConfigurations[monitor.id] = configuration
            disabledLayouts[monitor.id] = layout
            brightness.remove(monitor.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.stopping else { return }
                self.busy = false; self.refresh()
                if self.monitors.first(where: { $0.id == monitor.id })?.connected == true {
                    self.disabled.remove(monitor.id)
                    self.disabledConfigurations.removeValue(forKey: monitor.id)
                    self.disabledLayouts.removeValue(forKey: monitor.id)
                    self.message = "macOS chưa ngắt màn hình này. Chức năng có thể chưa tương thích với kết nối hiện tại."
                    return
                }
                // The switch is an explicit off request. Keep the display off
                // until the user reconnects it; only mode/HiDPI changes need
                // a timed confirmation to recover from an unreadable image.
                self.message = "Đã ngắt \(monitor.name). Bật lại bằng công tắc hoặc Khôi phục tất cả."
            }
        } else { reconnect(monitor, restoreSaved: true) }
    }

    private func reconnect(_ monitor: Monitor, restoreSaved: Bool) {
        busy = true
        guard let id = resolveDisplay(monitor.id, fallback: monitor.displayID) else {
            busy = false; message = "Chưa tìm thấy màn hình. Kiểm tra dây HDMI/USB-C rồi bấm Làm mới."; return
        }
        onDisplayConfigurationWillChange?()
        // Enabling and configuring are separate commits: wait for WindowServer
        // to publish the active output before applying its saved configuration.
        var configuration = disabledConfigurations[monitor.id] ?? originals[monitor.id] ?? snapshot(monitor)
        configuration.displayID = id
        configuration.reconnect = true
        let layout = disabledLayouts[monitor.id] ?? [configuration]
        enableForReconnect(monitor, displayID: id, restoreSaved: restoreSaved, layout: layout, attempts: 16)
    }

    private func enableForReconnect(_ monitor: Monitor, displayID id: CGDirectDisplayID,
                                    restoreSaved: Bool, layout: [RecoveryRecord], attempts: Int) {
        guard !stopping else { return }
        let result = MMSetEnabled(id, true)
        if result == .success || CGDisplayIsActive(id) != 0 {
            finishReconnect(monitor, restoreSaved: restoreSaved, layout: layout, applyConfiguration: true, attempts: 12)
        } else if attempts > 1 {
            // WindowServer can reject an otherwise valid enable request while
            // it is still moving the primary desktop after a disconnect.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.enableForReconnect(monitor, displayID: id, restoreSaved: restoreSaved, layout: layout, attempts: attempts - 1)
            }
        } else { error("Kết nối lại", result) }
    }

    private func finishReconnect(_ monitor: Monitor, restoreSaved: Bool, layout: [RecoveryRecord],
                                 applyConfiguration: Bool, configurationRestored: Bool = true, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard !self.stopping else { return }
            if applyConfiguration, CGDisplayIsOnline(monitor.displayID) != 0,
               CGDisplayIsActive(monitor.displayID) != 0, CGDisplayCopyDisplayMode(monitor.displayID) != nil {
                // Other active outputs can shift while this one is off. Restore
                // their saved placement without enabling any other off output.
                let activeLayout = layout.filter { $0.uuid == monitor.id ||
                    resolveDisplay($0.uuid, fallback: $0.displayID).map { CGDisplayIsActive($0) != 0 } == true }
                let restored = restoreRecords(activeLayout)
                self.finishReconnect(monitor, restoreSaved: restoreSaved, layout: layout,
                    applyConfiguration: false, configurationRestored: restored, attempts: 12)
                return
            }
            self.refresh()
            guard !applyConfiguration, let current = self.monitors.first(where: { $0.id == monitor.id }), current.connected else {
                if attempts > 1 {
                    self.finishReconnect(monitor, restoreSaved: restoreSaved, layout: layout,
                        applyConfiguration: applyConfiguration, configurationRestored: configurationRestored, attempts: attempts - 1)
                } else {
                    self.busy = false
                    self.message = "macOS chưa bật lại được \(monitor.name). Thử lại công tắc hoặc bấm Khôi phục tất cả."
                }
                return
            }
            self.busy = false
            self.disabled.remove(monitor.id)
            self.disconnectRetries.removeValue(forKey: monitor.id)
            self.disabledConfigurations.removeValue(forKey: monitor.id)
            self.disabledLayouts.removeValue(forKey: monitor.id)
            self.probing.remove(monitor.id)
            if restoreSaved && self.restoreOnReconnect { self.restoreProfile(current) }
            if !configurationRestored { self.message = "Đã bật lại \(monitor.name), nhưng chưa khôi phục đầy đủ bố cục màn hình." }
        }
    }

    func selectMode(_ choice: ModeChoice, for monitor: Monitor) {
        guard canChange && !monitor.virtual && monitor.connected else { return }
        guard CGDisplayMirrorsDisplay(monitor.displayID) == 0 else { message = "Hãy tắt phản chiếu màn hình hiện tại trước khi đổi độ phân giải."; return }
        guard preserve(monitor) else { return }
        message = nil; busy = true
        let previous = snapshot(monitor)
        let previousLayout = snapshotLayout()
        onDisplayConfigurationWillChange?()
        let result = choice.apply(to: monitor.displayID)
        guard result == .success else { error("Đổi độ phân giải", result); return }
        operationGeneration += 1; let generation = operationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.stopping, self.operationGeneration == generation else { return }
            let actual = currentDisplayChoice(monitor.displayID)
            guard actual?.width == choice.width, actual?.height == choice.height,
                  actual?.pixelWidth == choice.pixelWidth, actual?.pixelHeight == choice.pixelHeight,
                  abs((actual?.refreshRate ?? 0) - choice.refreshRate) < 1 else {
                _ = restoreRecords([previous]); self.busy = false; self.refresh()
                self.message = "macOS chưa áp dụng đúng độ phân giải hoặc Hz. Đã trả về cấu hình trước."; return
            }
            guard applyDisplayLayout(previousLayout, substitutions: self.layoutSubstitutions()),
                  displayLayoutMatches(previousLayout, substitutions: self.layoutSubstitutions()) else {
                _ = restoreRecords([previous]); _ = applyDisplayLayout(previousLayout, substitutions: self.layoutSubstitutions())
                self.busy = false; self.refresh()
                self.message = "macOS chưa giữ đúng vị trí màn hình. Đã quay lại bố cục trước."; return
            }
            self.busy = false; self.refresh()
            self.beginConfirmation("Hình ảnh có rõ và dễ đọc không?", rollback: { [weak self] in
                if !restoreRecords([previous]) { self?.message = "Chưa khôi phục được độ phân giải. Thử Khôi phục tất cả." }
                if let self { _ = applyDisplayLayout(previousLayout, substitutions: self.layoutSubstitutions()); self.refresh() }
            }, commit: { [weak self] in
                self?.saveProfile(ScreenProfile(width: choice.width, height: choice.height, virtual: false, pixelWidth: choice.pixelWidth, refresh: actual?.refreshRate ?? choice.refreshRate), id: monitor.id)
                if let self {
                    let reconnect = self.originals[monitor.id]?.reconnect ?? false
                    self.originals[monitor.id] = self.snapshot(monitor, reconnect: reconnect)
                    _ = self.preserve(monitor)
                }
            })
        }
    }

    func scalingSizes(_ monitor: Monitor) -> [HiDPISize] {
        let native = monitor.modes.filter(\.hiDPI).map { HiDPISize(width: $0.width, height: $0.height) }
        let sizes = HiDPIScaling.sizes(panel: monitor.panel) + native + (customSizes[monitor.id] ?? [])
        return Array(Set(sizes.filter { $0.valid &&
            abs(Double($0.width) / Double($0.height) - Double(monitor.panel.width) / Double(monitor.panel.height)) < 0.005 }))
            .sorted { $0.width < $1.width }
    }
    func scalingModes(_ monitor: Monitor) -> [ModeChoice] {
        virtuals[monitor.id].map { displayModes($0.displayID) } ?? monitor.modes
    }
    func scalingRates(_ monitor: Monitor) -> [Double] {
        let rates = Set(monitor.modes.map { Double(Int($0.refreshRate.rounded())) }.filter { (24...240).contains($0) })
        return rates.isEmpty ? [60] : rates.sorted(by: >)
    }
    func addScalingWidth(_ width: Int, monitor: Monitor) {
        guard (640...3840).contains(width) else { message = "Chiều rộng cần nằm trong khoảng 640–3840."; return }
        let unit = HiDPIScaling.gcd(monitor.panel.width, monitor.panel.height)
        let x = monitor.panel.width / unit, y = monitor.panel.height / unit
        let n = max(1, Int((Double(width) / Double(x)).rounded()))
        let size = HiDPISize(width: n * x, height: n * y)
        guard size.valid else { message = "Kích thước này vượt giới hạn HiDPI 2× của app."; return }
        var saved = customSizes[monitor.id] ?? []
        if !saved.contains(size) { saved.append(size) }
        customSizes[monitor.id] = saved
        if let data = try? JSONEncoder().encode(customSizes) { UserDefaults.standard.set(data, forKey: "customHiDPISizes") }
        message = "Đã thêm mức trông như \(size.label), giữ đúng tỉ lệ màn hình."
    }
    func overrideInstalled(_ monitor: Monitor) -> Bool {
        let vendor = CGDisplayVendorNumber(monitor.displayID), product = CGDisplayModelNumber(monitor.displayID)
        let path = "/Library/Application Support/MacMonitor/DisplayOverrides/\(String(vendor, radix: 16))-\(String(product, radix: 16)).plist"
        return FileManager.default.fileExists(atPath: path)
    }
    func configureNativeScaling(_ monitor: Monitor, enabled: Bool) {
        guard canChange && monitor.connected && !monitor.builtin && !monitor.virtual else { return }
        let vendor = CGDisplayVendorNumber(monitor.displayID), product = CGDisplayModelNumber(monitor.displayID)
        let sizes = scalingSizes(monitor)
        guard vendor > 0, product > 0, !sizes.isEmpty, sizes.count <= 256 else {
            message = "Chưa có đủ thông tin để cấu hình mẫu màn này."; return
        }
        busy = true; message = nil
        let args = [enabled ? "enable" : "disable", String(vendor), String(product), sizes.map(\.id).joined(separator: ",")]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = OverrideServiceClient.run(args)
            DispatchQueue.main.async {
                guard let self, !self.stopping else { return }
                self.busy = false
                let (status, output) = result
                if status == 0 && output.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
                    self.message = enabled
                        ? "Đã thêm \(sizes.count) mức HiDPI cho mẫu \(monitor.name). Kết nối lại dây hoặc khởi động lại Mac để macOS nạp cấu hình; sau đó bấm Làm mới. Cấu hình áp dụng cho các màn cùng mẫu."
                        : "Đã gỡ cấu hình của Mac Monitor và trả lại bản cũ. Kết nối lại dây hoặc khởi động lại Mac để áp dụng."
                } else if status == -60006 { self.message = "Đã hủy cấp phép. Cấu hình màn hình chưa thay đổi." }
                else { self.message = "Chưa áp dụng được cấu hình HiDPI. \(output.isEmpty ? "macOS chưa cho phép thao tác này (\(status))." : output)" }
                self.refresh()
            }
        }
    }
    func removeOverrideService() {
        guard canChange else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = (try? OverrideServiceClient.unregister()) != nil
            DispatchQueue.main.async {
                self?.busy = false
                self?.message = success ? "Đã gỡ dịch vụ quản trị. Cấu hình màn hình đã cài vẫn được giữ." : "Chưa gỡ được dịch vụ quản trị. Kiểm tra Login Items & Extensions."
            }
        }
    }
    func applyScaling(_ size: HiDPISize, refresh: Double, virtual: Bool, monitor: Monitor) {
        guard size.valid, canChange else { return }
        if monitor.virtual {
            if !virtual, HiDPIScaling.bestMode(size: size, refresh: refresh, modes: monitor.modes) != nil {
                profiles.removeValue(forKey: monitor.id); persistProfiles()
                removeVirtual(monitor.id, restore: originals[monitor.id]) { [weak self] in
                    if let self, let updated = self.monitors.first(where: { $0.id == monitor.id }),
                       let mode = HiDPIScaling.bestMode(size: size, refresh: refresh, modes: updated.modes) { self.selectMode(mode, for: updated) }
                }
            } else { createHiDPI(monitor, width: size.width, height: size.height, refresh: refresh) }
        } else if !virtual, let mode = HiDPIScaling.bestMode(size: size, refresh: refresh, modes: monitor.modes) {
            selectMode(mode, for: monitor)
        } else if virtual { createHiDPI(monitor, width: size.width, height: size.height, refresh: refresh) }
        else { message = "Mức này chưa có trực tiếp. Bổ sung các mức HiDPI vào macOS rồi kết nối lại màn, hoặc chọn Màn ảo." }
    }
    private func snapshotLayout() -> [RecoveryRecord] {
        monitors.filter(\.connected).map { monitor in
            let effective = virtuals[monitor.id]?.displayID ?? monitor.displayID
            let origin = CGDisplayBounds(effective).origin
            return RecoveryRecord(uuid: monitor.id, displayID: monitor.displayID, modeID: nil,
                                  x: Int32(origin.x), y: Int32(origin.y), reconnect: false)
        }
    }
    private func layoutSubstitutions() -> [String: CGDirectDisplayID] {
        virtuals.mapValues(\.displayID)
    }
    private struct VirtualRollback {
        let record: RecoveryRecord
        let layout: [RecoveryRecord]
        let virtual: MMVirtualScreen?
        let mode: ModeChoice?
    }
    private func waitForVirtualRemoval(_ ids: [CGDirectDisplayID], generation: Int, attempts: Int = 30, completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.stopping, self.operationGeneration == generation else { return }
            if ids.contains(where: { CGDisplayIsOnline($0) != 0 }) && attempts > 1 {
                self.waitForVirtualRemoval(ids, generation: generation, attempts: attempts - 1, completion: completion)
            } else { completion() }
        }
    }
    private func restoreVirtual(_ monitor: Monitor, previous: VirtualRollback) {
        guard let virtual = previous.virtual, let mode = previous.mode else {
            removeVirtual(monitor.id, restore: previous.record); return
        }
        operationGeneration += 1; let generation = operationGeneration
        onDisplayConfigurationWillChange?()
        let removedID = virtuals[monitor.id]?.displayID
        virtuals[monitor.id] = virtual
        busy = true
        waitForVirtualRemoval(removedID.map { $0 == virtual.displayID ? [] : [$0] } ?? [], generation: generation) { [weak self] in
            guard let self else { return }
            var config: CGDisplayConfigRef?
            var result = CGBeginDisplayConfiguration(&config)
            if result == .success, let config {
                result = mode.configure(config, display: virtual.displayID)
                if result == .success { result = CGConfigureDisplayMirrorOfDisplay(config, monitor.displayID, virtual.displayID) }
                if result == .success { result = configureDisplayLayout(previous.layout, substitutions: self.layoutSubstitutions(), config: config) }
                if result == .success { result = CGCompleteDisplayConfiguration(config, .forSession) }
                else { CGCancelDisplayConfiguration(config) }
            }
            _ = applyDisplayLayout(previous.layout, substitutions: self.layoutSubstitutions())
            self.busy = false; self.refresh()
            if result != .success { self.message = "Chưa khôi phục được màn ảo trước đó. Thử Khôi phục tất cả." }
        }
    }

    func createHiDPI(_ monitor: Monitor, width: Int, height: Int, refresh rate: Double = 60) {
        guard canChange && monitor.connected && HiDPISize(width: width, height: height).valid else { return }
        if !monitor.virtual && (CGDisplayMirrorsDisplay(monitor.displayID) != 0 || CGDisplayIsInMirrorSet(monitor.displayID) != 0) {
            message = "Màn này đang phản chiếu. Tắt phản chiếu trong Cài đặt màn hình trước."; return
        }
        // Preserve the entire native desktop for watchdog recovery, including
        // the main display and outputs that are not the selected target.
        for item in monitors.filter(\.connected) where !item.virtual {
            guard preserve(item) else { return }
        }
        guard preserve(monitor) else { return }
        message = nil; busy = true
        let oldVirtual = virtuals[monitor.id]
        let previous = VirtualRollback(record: snapshot(monitor), layout: snapshotLayout(), virtual: oldVirtual,
                                       mode: oldVirtual.flatMap { currentDisplayChoice($0.displayID) })
        if virtualLayouts[monitor.id] == nil { virtualLayouts[monitor.id] = previous.layout }
        onDisplayConfigurationWillChange?()
        guard let virtual = MMVirtualScreen(physicalID: monitor.displayID, width: UInt32(width), height: UInt32(height), serial: DisplayPolicy.stableSerial(monitor.id), sizes: scalingSizes(monitor).map { ["width": $0.width, "height": $0.height] }, refreshRates: scalingRates(monitor).map { NSNumber(value: $0) }, preferredRate: rate) else {
            busy = false; message = "macOS không tạo được màn hình HiDPI ảo trên cấu hình này."; return
        }
        virtuals[monitor.id] = virtual
        operationGeneration += 1
        let generation = operationGeneration
        finishVirtual(monitor, virtual: virtual, width: width, height: height, previous: previous, rate: rate, attempts: 12, generation: generation)
    }
    private func finishVirtual(_ monitor: Monitor, virtual: MMVirtualScreen, width: Int, height: Int, previous: VirtualRollback, rate: Double, attempts: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.stopping, self.operationGeneration == generation else { return }
            let wanted = HiDPIScaling.bestMode(size: HiDPISize(width: width, height: height), refresh: rate, modes: displayModes(virtual.displayID))
            guard let wanted else {
                if attempts > 1 { self.finishVirtual(monitor, virtual: virtual, width: width, height: height, previous: previous, rate: rate, attempts: attempts - 1, generation: generation) }
                else { self.restoreVirtual(monitor, previous: previous); self.message = "macOS chưa cung cấp chế độ HiDPI yêu cầu. Đã quay về cấu hình cũ." }
                return
            }
            var config: CGDisplayConfigRef?
            var result = CGBeginDisplayConfiguration(&config)
            if result == .success, let config {
                result = wanted.configure(config, display: virtual.displayID)
                if result == .success { result = CGConfigureDisplayMirrorOfDisplay(config, monitor.displayID, virtual.displayID) }
                if result == .success { result = configureDisplayLayout(previous.layout, substitutions: self.layoutSubstitutions(), config: config) }
                if result == .success { result = CGCompleteDisplayConfiguration(config, .forSession) }
                else { CGCancelDisplayConfiguration(config) }
            }
            guard result == .success else {
                self.restoreVirtual(monitor, previous: previous); self.error("Tạo HiDPI", result); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, self.operationGeneration == generation else { return }
                let current = currentDisplayChoice(virtual.displayID) ?? currentDisplayChoice(monitor.displayID)
                guard CGDisplayMirrorsDisplay(monitor.displayID) == virtual.displayID,
                      current?.width == width, current?.height == height, current?.pixelWidth == width * 2,
                      current?.pixelHeight == height * 2, abs((current?.refreshRate ?? 0) - rate) < 1 else {
                    self.restoreVirtual(monitor, previous: previous)
                    self.message = "macOS chưa áp dụng đúng chế độ HiDPI. Đã quay về cấu hình cũ."; return
                }
                // WindowServer can normalize origins during the mirror
                // transaction. Reapply all origins once the topology settles.
                let substitutions = self.layoutSubstitutions()
                guard applyDisplayLayout(previous.layout, substitutions: substitutions),
                      displayLayoutMatches(previous.layout, substitutions: substitutions) else {
                    self.restoreVirtual(monitor, previous: previous)
                    self.message = "macOS chưa giữ đúng vị trí màn hình. Đã quay lại bố cục trước."; return
                }
                self.busy = false; self.refresh()
                self.beginConfirmation("Giữ HiDPI \(width) × \(height)?", rollback: { [weak self] in
                    self?.restoreVirtual(monitor, previous: previous)
                }, commit: { [weak self] in
                    self?.saveProfile(ScreenProfile(width: width, height: height, virtual: true, pixelWidth: width * 2, refresh: current?.refreshRate ?? wanted.refreshRate), id: monitor.id)
                    guard let self else { return }
                    let layout = previous.layout
                    let oldID = previous.virtual?.displayID
                    self.busy = true
                    self.waitForVirtualRemoval(oldID.map { [$0] } ?? [], generation: generation) { [weak self] in
                        guard let self else { return }
                        if !applyDisplayLayout(layout, substitutions: self.layoutSubstitutions()) ||
                           !displayLayoutMatches(layout, substitutions: self.layoutSubstitutions()) {
                            self.message = "HiDPI đã áp dụng nhưng macOS chưa giữ đúng vị trí màn. Thử Khôi phục tất cả."
                        }
                        self.busy = false; self.refresh()
                    }
                })
            }
        }
    }
    private func removeVirtual(_ id: String, restore record: RecoveryRecord?, completion: (() -> Void)? = nil) {
        operationGeneration += 1; let generation = operationGeneration
        onDisplayConfigurationWillChange?()
        let removedID = virtuals[id]?.displayID
        let layout = virtualLayouts.removeValue(forKey: id) ?? []
        virtuals.removeValue(forKey: id)
        busy = true
        waitForVirtualRemoval(removedID.map { [$0] } ?? [], generation: generation) { [weak self] in
            guard let self else { return }
            if let record, !restoreRecords([record]) { self.message = "Chưa khôi phục được cấu hình màn hình. Thử kết nối lại dây." }
            if !applyDisplayLayout(layout, substitutions: self.layoutSubstitutions()) {
                self.message = "Chưa trả lại được đầy đủ vị trí màn hình. Thử Khôi phục tất cả."
            }
            self.busy = false; self.refresh(); completion?()
        }
    }
    func disableHiDPI(_ monitor: Monitor) {
        guard canChange else { return }
        removeVirtual(monitor.id, restore: originals[monitor.id])
        profiles.removeValue(forKey: monitor.id); persistProfiles()
    }
    private func restoreProfile(_ monitor: Monitor) {
        guard let profile = profiles[monitor.id], canChange else { return }
        if profile.virtual { createHiDPI(monitor, width: profile.width, height: profile.height, refresh: profile.refresh) }
        else if let mode = DisplayPolicy.matchingMode(profile, modes: monitor.modes), mode.id != monitor.currentModeID { selectMode(mode, for: monitor) }
    }
    private func saveProfile(_ profile: ScreenProfile, id: String) { profiles[id] = profile; persistProfiles() }
    private func persistProfiles() { if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "profiles") } }
    private func beginConfirmation(_ title: String, rollback: @escaping () -> Void, commit: @escaping () -> Void) {
        pendingRollback = rollback; pendingCommit = commit
        pendingTitle = title; pendingDeadline = Date().addingTimeInterval(20); secondsRemaining = 20
        onPresent?()
    }
    func confirm() {
        let commit = pendingCommit
        clearPending(); commit?()
    }
    func revert() {
        let rollback = pendingRollback
        clearPending(); rollback?()
    }
    private func clearPending() { pendingTitle = nil; pendingDeadline = nil; pendingRollback = nil; pendingCommit = nil; secondsRemaining = 0 }
    func reconnectAll() {
        if pendingTitle != nil { revert() }
        operationGeneration += 1; let generation = operationGeneration
        onDisplayConfigurationWillChange?()
        let removedIDs = virtuals.values.map(\.displayID)
        virtuals.removeAll(); busy = true
        waitForVirtualRemoval(removedIDs, generation: generation) { [weak self] in
            guard let self else { return }
            let success = restoreRecords(Array(self.originals.values))
            self.disabled.removeAll(); self.disconnectRetries.removeAll(); self.disabledConfigurations.removeAll(); self.disabledLayouts.removeAll(); self.busy = false
            self.message = success ? "Đã gửi lệnh khôi phục các màn hình." : "Có màn chưa khôi phục được. Kiểm tra dây kết nối rồi thử lại."
            self.refresh()
        }
    }
    func shutdown() {
        let needsRecovery = !virtuals.isEmpty || !disabled.isEmpty || pendingTitle != nil
        stopping = true; timer?.invalidate(); keys.stop(); brightness.stop()
        if !needsRecovery {
            // Native modes and a layout chosen in macOS are user settings.
            // A normal quit must not put an earlier main display back.
            operationGeneration += 1; clearPending()
            try? FileManager.default.removeItem(at: recoveryFileURL)
            return
        }
        let hadVirtuals = !virtuals.isEmpty
        operationGeneration += 1; clearPending(); virtuals.removeAll()
        let restored = originals.isEmpty || restoreRecords(Array(originals.values))
        // Teardown can complete after the main process exits. Leave recovery
        // for the watchdog to reapply native modes after virtual surfaces vanish.
        if restored && !hadVirtuals { try? FileManager.default.removeItem(at: self.recoveryFileURL) }
        // The watchdog makes one more recovery attempt after exit if the file remains.
    }
}
