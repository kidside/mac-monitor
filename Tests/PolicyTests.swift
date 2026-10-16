import AppKit

@main
enum PolicyTests {
    static func monitor(_ id: String, connected: Bool = true, builtin: Bool = false) -> Monitor {
        Monitor(id: id, displayID: 1, name: id, online: connected, connected: connected,
                builtin: builtin, inches: 27, modes: [], current: "2560 × 1440", currentModeID: nil, hiDPI: false)
    }
    static func main() throws {
        // Runs before any display calls initialize a WindowServer connection,
        // like the standalone crash-recovery process. The reverse UUID API
        // used to abort here rather than returning an unavailable display.
        precondition(resolveDisplay("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") == nil)
        precondition(resolveDisplay("missing-display", fallback: UInt32.max) == nil)
        let reading = try JSONDecoder().decode(BrightnessReading.self, from: Data("{\"current\":51,\"maximum\":100}".utf8))
        precondition(reading.normalized == 0.51)
        precondition(reading.matches(requested: 51, maximum: 100))
        precondition(!reading.matches(requested: 0, maximum: 100), "A successful transport does not verify a brightness change")
        precondition(!reading.matches(requested: 51, maximum: 200))
        precondition(BrightnessReading(current: 0, maximum: 100).normalized == 0)
        precondition(BrightnessReading(current: 51, maximum: 0).normalized == nil)
        precondition(BrightnessReading(current: -1, maximum: 100).normalized == nil)
        precondition(BrightnessReading(current: 101, maximum: 100).normalized == nil)
        precondition(BrightnessReading(current: 1, maximum: 65_535).normalized == nil)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 122) == nil, "F1 must remain available to other apps")
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 120) == nil, "F2 must remain available to other apps")
        precondition(BrightnessKeyInput.decode(type: 11, keyCode: 122) == nil)
        precondition(BrightnessKeyInput.decode(type: 11, keyCode: 120) == nil)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 120, flags: .maskCommand) == nil)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 0) == nil)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 145)?.step == -0.0625)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 144)?.step == 0.0625)
        precondition(BrightnessKeyInput.decode(type: 11, keyCode: 145)?.down == false)
        precondition(BrightnessKeyInput.decode(type: 11, keyCode: 144)?.down == false)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 144, flags: .maskAlternate) == nil)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 145, flags: .maskSecondaryFn)?.down == true)
        // Flags captured from the user's Magic Keyboard sun keys.
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 145, flags: CGEventFlags(rawValue: 8388864))?.step == -0.0625)
        precondition(BrightnessKeyInput.decode(type: 10, keyCode: 144, flags: CGEventFlags(rawValue: 8388864))?.step == 0.0625)
        precondition(BrightnessKeyInput.decode(type: 14, keyCode: 0, subtype: 8, data1: (3 << 16) | (0x0a << 8))?.step == -0.0625)
        precondition(BrightnessKeyInput.decode(type: 14, keyCode: 0, subtype: 8, data1: (2 << 16) | (0x0a << 8))?.down == true)
        precondition(BrightnessKeyInput.decode(type: 14, keyCode: 0, subtype: 8, data1: (2 << 16) | (0x0b << 8))?.down == false)
        precondition(BrightnessKeyInput.decode(type: 14, keyCode: 0, subtype: 8, data1: (0 << 16) | (0x0a << 8)) == nil)
        let external = monitor("external")
        let builtin = monitor("builtin", builtin: true)
        precondition(!DisplayPolicy.canDisconnect("external", monitors: [external]), "Must not disconnect the last display")
        precondition(DisplayPolicy.canDisconnect("external", monitors: [external, builtin]), "An active built-in display permits disconnect")
        precondition(!DisplayPolicy.canDisconnect("builtin", monitors: [external, builtin]), "Built-in screen is not a target")
        precondition(!DisplayPolicy.canDisconnect("external", monitors: [external, monitor("other", connected: false)]), "An offline display cannot serve as fallback")
        precondition(!DisplayPolicy.canDisconnect("missing", monitors: [external, builtin]))
        precondition(DisplayPolicy.brightness(-0.5) == 0.05)
        precondition(DisplayPolicy.brightness(0, minimum: 0) == 0, "Hardware brightness may reach its true minimum")
        precondition(DisplayPolicy.brightness(1.5) == 1)
        precondition(DisplayPolicy.brightness(0.5) == 0.5)
        precondition(DisplayPolicy.stableSerial("display-a") == DisplayPolicy.stableSerial("display-a"))
        precondition(DisplayPolicy.stableSerial("display-a") != DisplayPolicy.stableSerial("display-b"))
        let profile = ScreenProfile(width: 2048, height: 1152, virtual: true, pixelWidth: 4096, refresh: 60)
        let decoded = try JSONDecoder().decode(ScreenProfile.self, from: JSONEncoder().encode(profile))
        precondition(decoded.width == 2048 && decoded.virtual && decoded.pixelWidth == 4096)
        let record = RecoveryRecord(uuid: "A", displayID: 3, modeID: 17, x: -2560, y: 0, reconnect: true)
        let recovery = try JSONDecoder().decode(RecoveryRecord.self, from: JSONEncoder().encode(record))
        precondition(recovery.x == -2560 && recovery.reconnect && recovery.modeID == 17 && recovery.displayID == 3)
        let legacy = try JSONDecoder().decode(RecoveryRecord.self, from: Data("{\"uuid\":\"A\",\"x\":0,\"y\":0,\"reconnect\":true}".utf8))
        precondition(legacy.displayID == nil, "Old recovery records remain readable")
        precondition(legacy.modeProfile == nil)
        var described = record
        described.modeProfile = ScreenProfile(width: 1920, height: 1080, virtual: false, pixelWidth: 3840, refresh: 100)
        let restored = try JSONDecoder().decode(RecoveryRecord.self, from: JSONEncoder().encode(described))
        precondition(restored.modeProfile?.pixelWidth == 3840 && restored.modeProfile?.refresh == 100,
                     "Recover HiDPI geometry and refresh rate even when numeric mode IDs change")
        print("PASS: brightness validation, F1/F2 pass through, sun keys, display protection and recovery persistence")
    }
}
