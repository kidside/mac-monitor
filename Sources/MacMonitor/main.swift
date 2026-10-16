import AppKit
import SwiftUI
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private var popover = NSPopover()
    private let model = DisplayController()
    private var window: NSWindow?
    private var started = false
    private var displayTransition = false
    private var reopenAfterDisplayChange = false
    private var displaySettleWork: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var dismissal = PopoverDismissal()
    private var dismissalWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: "local.anle.MacMonitor")
        if let existing = siblings.first(where: { $0.processIdentifier != getpid() }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Mac Monitor")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = L("Mac Monitor — màn hình & độ sáng")
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
            name: Notification.Name("MacMonitorLanguageChanged"), object: nil)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: .leftMouseUp)
        installDismissalMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        model.onDisplayConfigurationWillChange = { [weak self] in self?.prepareForDisplayChange() }
        model.onPresent = { [weak self] in self?.showPopover() }
        model.start()
        started = true
        if CommandLine.arguments.contains("--window") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Mac Monitor"
            window.contentView = NSHostingView(rootView: MonitorView(model: model))
            window.center(); window.makeKeyAndOrderFront(nil)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
        } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showPopover() } }
    }
    private let popoverLogger = Logger(subsystem: "local.anle.MacMonitor", category: "Popover")
    private func tracePopover(_ message: String) {
        guard CommandLine.arguments.contains("--trace-popover") else { return }
        popoverLogger.debug("\(message, privacy: .public) shown=\(self.popover.isShown) active=\(NSApp.isActive) transition=\(self.displayTransition) queued=\(self.reopenAfterDisplayChange)")
    }
    @objc private func languageChanged() { item.button?.toolTip = L("Mac Monitor — màn hình & độ sáng") }
    @objc private func togglePopover() {
        tracePopover("toggle event=\(NSApp.currentEvent?.eventNumber ?? -1)")
        cancelScheduledDismissal()
        dismissal.statusAction(at: ProcessInfo.processInfo.systemUptime)
        if popover.isShown || (displayTransition && reopenAfterDisplayChange) { hidePopover() }
        else { showPopover() }
    }
    private func hidePopover() {
        tracePopover("hide")
        cancelScheduledDismissal()
        reopenAfterDisplayChange = false
        popover.performClose(nil)
        tracePopover("hide returned")
    }
    private func cancelScheduledDismissal() {
        dismissalWork?.cancel()
        dismissalWork = nil
        dismissal.cancel()
    }
    private func scheduleDismissal(_ token: UInt64) {
        dismissalWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dismissal.shouldDismiss(token, appIsActive: NSApp.isActive) else { return }
            self.tracePopover("deferred dismissal")
            self.hidePopover()
        }
        dismissalWork = work
        // Leave time for macOS to forward the status item's native action.
        // That action cancels this work before toggling the panel itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + PopoverDismissal.forwardingGrace, execute: work)
    }
    private func installDismissalMonitors() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            guard let self, self.popover.isShown || self.reopenAfterDisplayChange else { return }
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) {
                if let token = self.dismissal.pointerUp(at: event.timestamp, button: event.buttonNumber) {
                    self.tracePopover("queued outside release")
                    self.scheduleDismissal(token)
                }
            } else {
                _ = self.dismissal.pointerDown(at: event.timestamp, button: event.buttonNumber)
                self.tracePopover("observed outside press")
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type),
               let token = self.dismissal.pointerUp(at: event.timestamp, button: event.buttonNumber) {
                self.scheduleDismissal(token)
            }
            self.tracePopover("local type=\(event.type.rawValue) window=\(event.windowNumber) status=\(self.item.button?.window?.windowNumber ?? -1) panel=\(self.popover.contentViewController?.view.window?.windowNumber ?? -1)")
            if event.type == .keyDown, event.keyCode == 53,
               event.window === self.popover.contentViewController?.view.window {
                self.hidePopover()
                return nil
            }
            // Preserve interactions with child menus, pickers and controls.
            // The optional debug window is the only other ordinary app window.
            if event.type != .keyDown, let window = self.window, event.window === window {
                self.hidePopover()
            }
            return event
        }
    }
    func popoverDidClose(_ notification: Notification) {
        tracePopover("did close")
        guard notification.object as? NSPopover === popover else { return }
        if !displayTransition { reopenAfterDisplayChange = false }
    }
    func applicationDidResignActive(_ notification: Notification) {
        tracePopover("resign active")
        guard popover.isShown || reopenAfterDisplayChange else { return }
        scheduleDismissal(dismissal.deactivated())
    }
    private func showPopover() {
        tracePopover("show")
        cancelScheduledDismissal()
        if displayTransition {
            reopenAfterDisplayChange = true
            scheduleAfterDisplayChange()
            return
        }
        guard let button = item?.button, let screen = button.window?.screen ?? NSScreen.main else { return }
        if !popover.isShown {
            // A display disconnect can move the status item to another screen
            // and change its backing scale. Don't reuse that old hosting window.
            let height = max(260, min(680, screen.visibleFrame.height - 32))
            let size = NSSize(width: 420, height: height)
            let hosting = NSHostingController(rootView: MonitorView(model: model, panelHeight: height))
            hosting.sizingOptions = []
            hosting.preferredContentSize = size
            hosting.view.setFrameSize(size)
            let replacement = NSPopover()
            // Manage outside clicks explicitly so the status-item click
            // cannot be consumed once by dismissal and once by toggle.
            replacement.behavior = .applicationDefined
            replacement.animates = false
            replacement.delegate = self
            replacement.contentViewController = hosting
            replacement.contentSize = size
            popover = replacement
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func screenParametersChanged(_ notification: Notification) { prepareForDisplayChange() }
    private func prepareForDisplayChange() {
        tracePopover("display change")
        reopenAfterDisplayChange = reopenAfterDisplayChange || popover.isShown
        displayTransition = true
        popover.close()
        scheduleAfterDisplayChange()
    }
    private func scheduleAfterDisplayChange() {
        displaySettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.displayTransition = false
            self.model.refresh()
            let reopen = self.reopenAfterDisplayChange
            self.reopenAfterDisplayChange = false
            if reopen { self.showPopover() }
        }
        displaySettleWork = work
        // Screen changes arrive in bursts while WindowServer relocates the menu bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { tracePopover("application reopen"); showPopover(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        displaySettleWork?.cancel()
        cancelScheduledDismissal()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        NotificationCenter.default.removeObserver(self)
        if started { model.shutdown() }
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--diagnostics") || arguments.contains("--diagnostics-private") {
    let displays: [[String: Any]] = MMAllDisplays().map { number in
        let id = number.uint32Value
        var record: [String: Any] = ["id": id, "name": MMDisplayName(id),
                "builtin": CGDisplayIsBuiltin(id) != 0, "online": CGDisplayIsOnline(id) != 0,
                "active": CGDisplayIsActive(id) != 0, "mirrorOf": CGDisplayMirrorsDisplay(id),
                "modes": displayModes(id).map { ["label": $0.label, "pixelWidth": $0.pixelWidth, "pixelHeight": $0.pixelHeight] }]
        if arguments.contains("--diagnostics-private") { record["uuid"] = displayUUID(id) }
        return record
    }
    let diagnostics: [String: Any] = ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                                    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                                    "disconnectAPI": MMCanSetEnabled(), "virtualDisplayAPI": MMVirtualScreen.isSupported(),
                                    "accessibility": AXIsProcessTrusted(), "displays": displays]
    if let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else if let index = arguments.firstIndex(of: "--watchdog"), arguments.count > index + 2, let parent = Int32(arguments[index + 1]) {
    // Independent recovery survives an app crash or force quit. No configuration changes while the parent is alive.
    let path = URL(fileURLWithPath: arguments[index + 2])
    while kill(parent, 0) == 0 { Thread.sleep(forTimeInterval: 1) }
    if let data = try? Data(contentsOf: path), let records = try? JSONDecoder().decode([RecoveryRecord].self, from: data) {
        if restoreRecords(records) { try? FileManager.default.removeItem(at: path) }
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
