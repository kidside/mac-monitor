import AppKit

// Positions are logical desktop coordinates. Replace a physical output with
// its virtual source while preserving the original main display at (0, 0).
func configureDisplayLayout(_ records: [RecoveryRecord], substitutions: [String: CGDirectDisplayID], config: CGDisplayConfigRef) -> CGError {
    for record in records {
        guard let id = substitutions[record.uuid] ?? resolveDisplay(record.uuid, fallback: record.displayID),
              CGDisplayIsOnline(id) != 0 else { continue }
        if CGDisplayMirrorsDisplay(id) != 0 && substitutions[record.uuid] == nil { continue }
        let result = CGConfigureDisplayOrigin(config, id, record.x, record.y)
        if result != .success { return result }
    }
    return .success
}

func applyDisplayLayout(_ records: [RecoveryRecord], substitutions: [String: CGDirectDisplayID] = [:]) -> Bool {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
    let result = configureDisplayLayout(records, substitutions: substitutions, config: config)
    guard result == .success else { CGCancelDisplayConfiguration(config); return false }
    return CGCompleteDisplayConfiguration(config, .forSession) == .success
}

func displayLayoutMatches(_ records: [RecoveryRecord], substitutions: [String: CGDirectDisplayID] = [:]) -> Bool {
    records.allSatisfy { record in
        guard let id = substitutions[record.uuid] ?? resolveDisplay(record.uuid, fallback: record.displayID),
              CGDisplayIsOnline(id) != 0 else { return true }
        if CGDisplayMirrorsDisplay(id) != 0 && substitutions[record.uuid] == nil { return true }
        let origin = CGDisplayBounds(id).origin
        return Int32(origin.x) == record.x && Int32(origin.y) == record.y
    }
}

func currentDesktopOutputs() -> [DesktopOutput] {
    MMAllDisplays().map(\.uint32Value).map { id in
        DesktopOutput(id: id, uuid: displayUUID(id), frame: CGDisplayBounds(id),
                      active: CGDisplayIsActive(id) != 0, mirrorSource: CGDisplayMirrorsDisplay(id),
                      inMirrorSet: CGDisplayIsInMirrorSet(id) != 0)
    }
}

func applyDisplayPlacements(_ placements: [DisplayPlacement], permanently: Bool = false) -> Bool {
    guard !placements.isEmpty else { return true }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
    for placement in placements where CGDisplayIsOnline(placement.id) != 0 {
        let result = CGConfigureDisplayOrigin(config, placement.id, placement.x, placement.y)
        if result != .success { CGCancelDisplayConfiguration(config); return false }
    }
    return CGCompleteDisplayConfiguration(config, permanently ? .permanently : .forSession) == .success
}

func displayPlacementsMatch(_ placements: [DisplayPlacement]) -> Bool {
    placements.allSatisfy { placement in
        let origin = CGDisplayBounds(placement.id).origin
        return CGDisplayIsOnline(placement.id) != 0 && origin.x == CGFloat(placement.x) && origin.y == CGFloat(placement.y)
    }
}
