import Foundation

@main enum PopoverDismissalTests {
    static func main() {
        var state = PopoverDismissal()
        // Reproduce the captured failing order: mouse-down closes the panel
        // before the native status action arrives 10–20 ms later.
        let outside = state.pointerDown(at: 10)!
        let focus = state.deactivated()
        state.statusAction(at: 10.02)
        precondition(!state.shouldDismiss(outside, appIsActive: false))
        precondition(!state.shouldDismiss(focus, appIsActive: false))
        // A global callback for the same press can arrive late, after opening.
        precondition(state.pointerDown(at: 10) == nil)
        // The next real outside click still dismisses, even with focus restored.
        let nextDown = state.pointerDown(at: 10.05)!
        precondition(!state.shouldDismiss(nextDown, appIsActive: true))
        let next = state.pointerUp(at: 10.10)!
        precondition(state.shouldDismiss(next, appIsActive: true))
        state.cancel()
        precondition(!state.shouldDismiss(next, appIsActive: false))
        // Keyboard switching away closes; a temporary deactivation does not.
        let switchAway = state.deactivated()
        precondition(state.shouldDismiss(switchAway, appIsActive: false))
        precondition(!state.shouldDismiss(switchAway, appIsActive: true))
        // Both callback orders for outside mouse/focus changes keep the click.
        let pointer = state.pointerDown(at: 11)!
        let laterFocus = state.deactivated()
        precondition(!state.shouldDismiss(pointer, appIsActive: true))
        precondition(!state.shouldDismiss(laterFocus, appIsActive: true))
        let release = state.pointerUp(at: 11.01)!
        precondition(state.shouldDismiss(release, appIsActive: true))
        state.statusAction(at: 11.02)
        precondition(!state.shouldDismiss(laterFocus, appIsActive: false))
        // Holding a mouse button must not dismiss before its forwarded action.
        _ = state.pointerDown(at: 12)
        let heldFocus = state.deactivated()
        precondition(!state.shouldDismiss(heldFocus, appIsActive: false))
        let heldRelease = state.pointerUp(at: 15)!
        state.statusAction(at: 15.02)
        precondition(!state.shouldDismiss(heldRelease, appIsActive: false))
        // Releasing one button while another is held must also wait.
        _ = state.pointerDown(at: 16, button: 0)
        _ = state.pointerDown(at: 16.01, button: 1)
        precondition(state.pointerUp(at: 16.1, button: 0) == nil)
        let allReleased = state.pointerUp(at: 16.2, button: 1)!
        precondition(state.shouldDismiss(allReleased, appIsActive: true))
        state.cancel()
        // Rapid real clicks must each invalidate all older dismissal work.
        for i in 0..<100 {
            let time = 20 + Double(i) * 0.04
            let token = state.pointerDown(at: time)!
            let released = state.pointerUp(at: time + 0.005)!
            state.statusAction(at: time + 0.01)
            precondition(!state.shouldDismiss(token, appIsActive: false))
            precondition(!state.shouldDismiss(released, appIsActive: false))
        }
        print("PASS: recorded status-click/focus race, late mouse callback, real outside click, keyboard focus changes and rapid repeated clicks")
    }
}
