import Foundation
import CoreGraphics

struct DesktopOutput {
    let id: CGDirectDisplayID
    let uuid: String
    let frame: CGRect
    let active: Bool
    var mirrorSource: CGDirectDisplayID = 0
    var inMirrorSet: Bool = false
}

struct DisplayPlacement: Equatable {
    let id: CGDirectDisplayID
    let x, y: Int32
}

enum DesktopPolicy {
    static func sources(_ outputs: [DesktopOutput]) -> [DesktopOutput] {
        outputs.filter { $0.active && $0.mirrorSource == 0 }
    }
    static func positions(_ outputs: [DesktopOutput]) -> [DisplayPlacement] {
        sources(outputs).compactMap {
            guard $0.frame.origin.x.isFinite, $0.frame.origin.y.isFinite,
                  let x = Int32(exactly: $0.frame.origin.x), let y = Int32(exactly: $0.frame.origin.y) else { return nil }
            return DisplayPlacement(id: $0.id, x: x, y: y)
        }
    }
    static func mainLayout(_ outputs: [DesktopOutput], target: CGDirectDisplayID) -> [DisplayPlacement]? {
        guard let selected = outputs.first(where: { $0.id == target }) else { return nil }
        let sourceID = selected.mirrorSource == 0 ? selected.id : selected.mirrorSource
        let positions = positions(outputs)
        guard let origin = positions.first(where: { $0.id == sourceID }) else { return nil }
        var translated: [DisplayPlacement] = []
        for position in positions {
            guard let x = Int32(exactly: Int64(position.x) - Int64(origin.x)),
                  let y = Int32(exactly: Int64(position.y) - Int64(origin.y)) else { return nil }
            translated.append(DisplayPlacement(id: position.id, x: x, y: y))
        }
        // Configure the selected origin first if macOS sees overlapping sources.
        return translated.sorted { ($0.id == sourceID ? 0 : 1) < ($1.id == sourceID ? 0 : 1) }
    }
    static func relocated(_ record: RecoveryRecord, x: Int32, y: Int32) -> RecoveryRecord {
        RecoveryRecord(uuid: record.uuid, displayID: record.displayID, modeID: record.modeID,
                       x: x, y: y, reconnect: record.reconnect, modeProfile: record.modeProfile, sidecar: record.sidecar, builtin: record.builtin)
    }
    static func startupRecovery(_ records: [RecoveryRecord], outputs: [DesktopOutput]) -> [RecoveryRecord] {
        var occupied = sources(outputs).map(\.frame)
        return records.compactMap { record in
            guard record.reconnect, let output = outputs.first(where: {
                $0.uuid == record.uuid || ($0.id == record.displayID && $0.uuid == "display-\($0.id)")
            }), !output.active, output.mirrorSource == 0, !output.inMirrorSet else { return nil }
            let width = max(640, min(16384, record.modeProfile?.width ?? 1920))
            let height = max(480, min(16384, record.modeProfile?.height ?? 1080))
            var frame = CGRect(x: Int(record.x), y: Int(record.y), width: width, height: height)
            if occupied.contains(where: { existing in
                let intersection = existing.intersection(frame)
                return !intersection.isNull && intersection.width > 0 && intersection.height > 0
            }) {
                // Never displace the live main display to recover an old output.
                frame.origin = CGPoint(x: occupied.map(\.maxX).max() ?? 0, y: 0)
            }
            guard let x = Int32(exactly: frame.origin.x), let y = Int32(exactly: frame.origin.y) else { return nil }
            occupied.append(frame)
            return relocated(record, x: x, y: y)
        }
    }
}
