import CoreGraphics

struct SidecarModeKey {
    let id: Int32
    let width, height, pixelWidth, pixelHeight: Int
    let refresh: Double
    var valid: Bool {
        [width, height, pixelWidth, pixelHeight].allSatisfy { (1...16384).contains($0) } &&
            refresh.isFinite && refresh >= 0
    }
    func matches(_ other: SidecarModeKey) -> Bool {
        valid && other.valid && id == other.id && width == other.width && height == other.height &&
            pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight && abs(refresh - other.refresh) < 0.5
    }
}

extension ModeChoice {
    var sidecarKey: SidecarModeKey {
        SidecarModeKey(id: id, width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight, refresh: refreshRate)
    }
}

// Read the modes actually advertised by the connected Sidecar display. Do not
// fabricate iPad sizes or call physical-panel HiDPI override APIs for this list.
func sidecarDisplayModes(_ id: CGDirectDisplayID) -> [ModeChoice] {
    guard CGDisplayIsOnline(id) != 0 else { return [] }
    let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    var modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
        .filter { $0.isUsableForDesktopGUI() }.map { ModeChoice(mode: $0) }
    if let current = CGDisplayCopyDisplayMode(id) { modes.insert(ModeChoice(mode: current), at: 0) }
    var seen = Set<Int32>()
    return modes.filter { $0.sidecarKey.valid && seen.insert($0.id).inserted }.sorted {
        if $0.hiDPI != $1.hiDPI { return $0.hiDPI }
        if $0.width != $1.width { return $0.width > $1.width }
        if $0.height != $1.height { return $0.height > $1.height }
        return $0.refreshRate > $1.refreshRate
    }
}
