import Foundation

// macOS forwards status-item actions after global mouse/deactivation events.
// A single physical click must belong to the button, not both dismissal paths.
struct PopoverDismissal {
    static let forwardingGrace: TimeInterval = 0.15
    private(set) var generation: UInt64 = 0
    private var pointerPending = false
    private var pressedButtons = Set<Int>()
    private var lastStatusAction: TimeInterval = -.infinity

    mutating func cancel() {
        generation &+= 1
        pointerPending = false
        pressedButtons.removeAll()
    }
    mutating func statusAction(at uptime: TimeInterval) {
        cancel()
        lastStatusAction = uptime
    }
    mutating func pointerDown(at eventUptime: TimeInterval, button: Int = 0) -> UInt64? {
        // Also handle a delayed global callback delivered after the button action.
        guard eventUptime > lastStatusAction else { return nil }
        pointerPending = true
        pressedButtons.insert(button)
        generation &+= 1
        return generation
    }
    mutating func pointerUp(at eventUptime: TimeInterval, button: Int = 0) -> UInt64? {
        guard eventUptime > lastStatusAction, pointerPending, pressedButtons.contains(button) else { return nil }
        pressedButtons.remove(button)
        guard pressedButtons.isEmpty else { return nil }
        generation &+= 1
        return generation
    }
    mutating func deactivated() -> UInt64 {
        // Preserve a pending outside click even if focus later changes back.
        generation &+= 1
        return generation
    }
    func shouldDismiss(_ token: UInt64, appIsActive: Bool) -> Bool {
        token == generation && pressedButtons.isEmpty && (pointerPending || !appIsActive)
    }
}
