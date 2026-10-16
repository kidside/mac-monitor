import AppKit
import CoreGraphics

struct ModeChoice: Identifiable {
    let mode: CGDisplayMode?
    let id: Int32
    let width, height, pixelWidth, pixelHeight: Int
    let refreshRate: Double
    init(mode: CGDisplayMode) {
        self.mode = mode; id = mode.ioDisplayModeID
        width = mode.width; height = mode.height
        pixelWidth = mode.pixelWidth; pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
    }
    init(native: MMNativeMode) {
        mode = nil; id = native.modeID
        width = native.width; height = native.height
        pixelWidth = native.pixelWidth; pixelHeight = native.pixelHeight
        refreshRate = native.refreshRate
    }
    var hiDPI: Bool { pixelWidth > width }
    var label: String {
        let refresh = refreshRate > 1 ? " · \(Int(refreshRate.rounded())) Hz" : ""
        return "\(width) × \(height)\(hiDPI ? " · HiDPI" : "")\(refresh)"
    }
    func configure(_ config: CGDisplayConfigRef, display: CGDirectDisplayID) -> CGError {
        if let mode { return CGConfigureDisplayWithDisplayMode(config, display, mode, nil) }
        return MMConfigureHiDPIMode(config, display, id)
    }
    func apply(to display: CGDirectDisplayID) -> CGError {
        if let mode { return CGDisplaySetDisplayMode(display, mode, nil) }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { return begin }
        let result = configure(config, display: display)
        guard result == .success else { CGCancelDisplayConfiguration(config); return result }
        return CGCompleteDisplayConfiguration(config, .forSession)
    }
}

struct ScreenProfile: Codable {
    var width: Int
    var height: Int
    var virtual: Bool
    var pixelWidth: Int
    var refresh: Double
}

struct RecoveryRecord: Codable {
    let uuid: String
    var displayID: CGDirectDisplayID? = nil
    let modeID: Int32?
    let x: Int32
    let y: Int32
    var reconnect: Bool
    var modeProfile: ScreenProfile? = nil
    var sidecar: Bool? = nil
}

struct Monitor: Identifiable {
    let id: String
    var displayID: CGDirectDisplayID
    var name: String
    var online: Bool
    var connected: Bool
    var builtin: Bool
    var inches: Double
    var modes: [ModeChoice]
    var current: String
    var currentModeID: Int32?
    var hiDPI: Bool
    var brightness: Double = 1
    var brightnessBackend: String = "Đang kiểm tra độ sáng…"
    var main: Bool = false
    var virtual: Bool = false
    var panel: HiDPISize = HiDPISize(width: 2560, height: 1440)
}

enum DisplayPolicy {
    static func canDisconnect(_ id: String, monitors: [Monitor]) -> Bool {
        guard let target = monitors.first(where: { $0.id == id }), target.connected, !target.builtin else { return false }
        return monitors.contains { $0.id != id && $0.connected }
    }
    static func brightness(_ value: Double, minimum: Double = 0.05) -> Double { min(1, max(minimum, value)) }
    static func stableSerial(_ string: String) -> UInt32 {
        string.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
    }
    static func matchingMode(_ profile: ScreenProfile, modes: [ModeChoice]) -> ModeChoice? {
        modes.filter { $0.width == profile.width && $0.height == profile.height && $0.pixelWidth == profile.pixelWidth }
            .min { abs($0.refreshRate - profile.refresh) < abs($1.refreshRate - profile.refresh) }
    }
}

func displayUUID(_ id: CGDirectDisplayID) -> String {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
    return CFUUIDCreateString(nil, uuid) as String
}

func resolveDisplay(_ uuid: String, fallback: CGDirectDisplayID? = nil) -> CGDirectDisplayID? {
    // The UUID-to-ID API asserts inside SkyLight in a cold recovery process.
    // Enumerating first is safe without an NSApplication and also lets us
    // validate a cached ID against the outputs that actually still exist.
    let displays = MMAllDisplays().map(\.uint32Value)
    if let id = displays.first(where: { displayUUID($0) == uuid }) { return id }
    if let fallback, displays.contains(fallback),
       displayUUID(fallback) == "display-\(fallback)" {
        return fallback
    }
    return nil
}

func currentDisplayChoice(_ id: CGDirectDisplayID) -> ModeChoice? {
    // CG's public cache can omit modes of a newly created virtual display in
    // its own process, even while other processes already see them.
    if let native = MMCurrentHiDPIMode(id) { return ModeChoice(native: native) }
    return CGDisplayCopyDisplayMode(id).map { ModeChoice(mode: $0) }
}

func displayModes(_ id: CGDirectDisplayID) -> [ModeChoice] {
    let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    var modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
        .filter { $0.isUsableForDesktopGUI() }.map { ModeChoice(mode: $0) }
    // The public list can omit a supported scaled mode after leaving it.
    // Supplement physical displays with validated native 2x descriptors.
    modes += MMNativeHiDPIModes(id).map { ModeChoice(native: $0) }
    var seen = Set<String>()
    return modes.filter {
        let key = "\($0.width)x\($0.height)-\($0.pixelWidth)x\($0.pixelHeight)-\(Int($0.refreshRate.rounded()))"
        return seen.insert(key).inserted
    }.sorted {
        if $0.hiDPI != $1.hiDPI { return $0.hiDPI }
        if $0.width != $1.width { return $0.width > $1.width }
        return $0.refreshRate > $1.refreshRate
    }
}

func restoreRecords(_ records: [RecoveryRecord]) -> Bool {
    var success = true
    for record in records {
        guard let id = resolveDisplay(record.uuid, fallback: record.displayID) else { continue }
        // Re-enabling an already active output can itself return an error on
        // recent macOS releases. It is already in the desired state, so only
        // send the private enable request when the display is actually inactive.
        if record.reconnect && CGDisplayIsActive(id) == 0 && CGDisplayMirrorsDisplay(id) == 0 &&
           CGDisplayIsInMirrorSet(id) == 0 && MMSetEnabled(id, true) != .success { success = false }
    }
    // A mirrored physical output can expose only the source's modes. Detach
    // mirrors in a separate transaction before enumerating its own mode list.
    let mirrored = records.compactMap { resolveDisplay($0.uuid, fallback: $0.displayID) }
        .filter { CGDisplayIsOnline($0) != 0 && (CGDisplayIsInMirrorSet($0) != 0 || CGDisplayMirrorsDisplay($0) != 0) }
    if !mirrored.isEmpty {
        var detach: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&detach) == .success, let detach else { return false }
        for id in mirrored {
            if CGConfigureDisplayMirrorOfDisplay(detach, id, kCGNullDirectDisplay) != .success { success = false }
        }
        if CGCompleteDisplayConfiguration(detach, .forSession) != .success { return false }
    }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
    for record in records {
        guard let id = resolveDisplay(record.uuid, fallback: record.displayID), CGDisplayIsOnline(id) != 0 else { continue }
        // Sidecar recovery uses its public CoreGraphics modes, never physical
        // panel overrides. Older recovery records omit this optional marker.
        let modes: [ModeChoice]
        if record.sidecar == true { modes = sidecarDisplayModes(id) }
        else { modes = MMNativeHiDPIModes(id).map { ModeChoice(native: $0) } + displayModes(id) }
        let mode: ModeChoice?
        if let profile = record.modeProfile { mode = DisplayPolicy.matchingMode(profile, modes: modes) }
        else { mode = record.modeID.flatMap { wanted in modes.first { $0.id == wanted } } }
        if record.modeID != nil || record.modeProfile != nil {
            if let mode { if mode.configure(config, display: id) != .success { success = false } }
            else { success = false }
        }
        if CGConfigureDisplayOrigin(config, id, record.x, record.y) != .success { success = false }
    }
    return CGCompleteDisplayConfiguration(config, .forSession) == .success && success
}
