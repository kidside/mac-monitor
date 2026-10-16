import AppKit
import ApplicationServices

final class BrightnessKeys {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var lastEvent: (Double, BrightnessKeyInput)?
    var onStep: ((Double) -> Bool)?
    var onRecognized: ((String, Bool) -> Void)?
    var enabled = true
    var isRunning: Bool { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(requestPermission: Bool = false) {
        if isRunning { return }
        stop()
        if requestPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << 14)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard owner.enabled else { return Unmanaged.passUnretained(event) }
            let ns = type.rawValue == 14 ? NSEvent(cgEvent: event) : nil
            guard let input = BrightnessKeyInput.decode(type: type.rawValue,
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                subtype: Int(ns?.subtype.rawValue ?? 0), data1: ns?.data1 ?? 0, flags: event.flags) else { return Unmanaged.passUnretained(event) }
            let timestamp = Double(event.timestamp) / 1_000_000_000
            return owner.handle(input, timestamp: timestamp) ? nil : Unmanaged.passUnretained(event)
        }
        // Brightness media keys must be captured before WindowServer/macOS consumes them.
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if tap != nil { break }
        }
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        // App-directed key events can bypass a global tap (including UI automation).
        // Handle them while our panel is focused using the same decoder.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined]) { [weak self] event in
            guard let self, self.enabled,
                  let input = BrightnessKeyInput.decode(type: UInt32(event.type.rawValue),
                    keyCode: Int64(event.type == .systemDefined ? 0 : event.keyCode),
                    subtype: Int(event.subtype.rawValue), data1: event.type == .systemDefined ? event.data1 : 0,
                    flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))) else { return event }
            return self.handle(input, timestamp: event.timestamp) ? nil : event
        }
    }
    private func handle(_ input: BrightnessKeyInput, timestamp: Double) -> Bool {
        if let lastEvent, lastEvent.1 == input, abs(lastEvent.0 - timestamp) < 0.001 { return true }
        let handled = onStep?(input.down ? input.step : 0) ?? false
        if handled { lastEvent = (timestamp, input) }
        if input.down { onRecognized?(input.label, handled) }
        return handled
    }
    func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil; lastEvent = nil
    }
    deinit { stop() }
}

final class BrightnessHUD {
    private var panel: NSPanel?
    private var hide: DispatchWorkItem?
    func show(name: String, value: Double, screen: NSScreen?) {
        guard let screen else { return }
        hide?.cancel()
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        let view = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 270, height: 76))
        view.material = .hudWindow; view.state = .active; view.wantsLayer = true; view.layer?.cornerRadius = 18
        let label = NSTextField(labelWithString: "☀  \(L(name))   \(Int(value * 100))%")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 20, y: 43, width: 230, height: 18)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 22, width: 230, height: 8))
        bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1; bar.doubleValue = value
        view.addSubview(label); view.addSubview(bar)
        panel?.contentView = view
        panel?.setFrame(NSRect(x: screen.frame.midX - 135, y: screen.visibleFrame.minY + 60, width: 270, height: 76), display: true)
        panel?.orderFrontRegardless()
        let item = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: item)
    }
}
