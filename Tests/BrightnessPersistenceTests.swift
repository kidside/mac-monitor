import AppKit

@main
enum BrightnessPersistenceTests {
    static func waitUntil(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(predicate(), "Brightness operation timed out")
    }
    static func main() {
        let monitor = Monitor(id: "test-VU", displayID: 1, name: "VU", online: true,
                              connected: true, builtin: false, inches: 24, modes: [],
                              current: "", currentModeID: nil, hiDPI: true)
        var backlight = 61
        var writes = 0
        var overlayAttempts = 0
        let helper: ([String]) -> (Int32, String) = { args in
            if args.contains("set") { backlight = Int(args.last!)!; writes += 1; return (0, "") }
            return (0, "{\"current\":\(backlight),\"maximum\":100}")
        }
        var last: Double?
        var completed = false
        let first = BrightnessController(helper: helper)
        first.screenForID = { _ in overlayAttempts += 1; return nil }
        first.onStatus = { _, value, _ in if let value { last = value; completed = true } }
        first.probe(monitor)
        waitUntil { completed }
        precondition(last == 0.61 && writes == 0 && overlayAttempts == 0,
                     "Launch reads current DDC without writing or applying dimming")
        completed = false
        first.set(0.42, monitor: monitor)
        waitUntil { completed }
        precondition(last == 0.42 && writes == 1, "Explicit slider changes still write hardware")
        // Extra dimming is only enabled by an explicit action in this session.
        completed = false
        var adjusted = monitor; adjusted.brightness = 0.42
        first.setExtraDimming(true, monitor: adjusted)
        waitUntil { completed }
        precondition(first.usesExtraDimming(monitor.id) && overlayAttempts > 0)
        first.stop()

        // The user adjusts the physical monitor while the app is closed.
        backlight = 75
        let reopened = BrightnessController(helper: helper)
        precondition(!reopened.usesExtraDimming(monitor.id), "A restart must not reapply an old dimming layer")
        overlayAttempts = 0
        reopened.screenForID = { _ in overlayAttempts += 1; return nil }
        completed = false
        reopened.onStatus = { _, value, _ in if let value { last = value; completed = true } }
        let priorWrites = writes
        reopened.probe(monitor)
        waitUntil { completed }
        precondition(last == 0.75 && backlight == 75 && writes == priorWrites && overlayAttempts == 0,
                     "Restart follows current hardware, not the previous slider setting")
        backlight = 0
        completed = false
        reopened.probe(monitor)
        waitUntil { completed }
        precondition(last == 0 && writes == priorWrites, "A genuine hardware minimum remains unchanged")
        reopened.stop()

        let unavailable = BrightnessController(helper: { _ in (1, "unavailable") })
        overlayAttempts = 0; completed = false
        unavailable.screenForID = { _ in overlayAttempts += 1; return nil }
        unavailable.onStatus = { _, value, _ in precondition(value == nil); completed = true }
        unavailable.probe(monitor)
        waitUntil { completed }
        precondition(overlayAttempts == 0, "A failed DDC read must not dim the display")
        print("PASS: read-only startup/restart, current hardware percentage, explicit writes, zero backlight and no automatic dimming")
    }
}
