import CoreGraphics

// Preserve the old main/source origins and keep newly added iPads clear of
// existing desktops. Reject stale snapshots rather than moving unrelated screens.
enum SidecarLayout {
    static func placements(previous: [DesktopOutput], current: [DesktopOutput], ipad: UInt32) -> [DisplayPlacement]? {
        let oldSources = DesktopPolicy.sources(previous)
        guard !oldSources.isEmpty,
              !previous.contains(where: { $0.id == ipad && $0.active }),
              let tablet = current.first(where: { $0.id == ipad }),
              oldSources.allSatisfy({ old in current.contains(where: { $0.id == old.id && $0.uuid == old.uuid && $0.active && $0.mirrorSource == 0 }) }),
              Set(current.filter { $0.active && $0.id != ipad }.map(\.id)).isSubset(of: Set(previous.filter(\.active).map(\.id)))
        else { return nil }
        var result = DesktopPolicy.positions(oldSources)
        guard result.count == oldSources.count,
              let x = Int32(exactly: oldSources.map(\.frame.maxX).max() ?? 0),
              tablet.frame.width.isFinite, tablet.frame.width > 0 else { return nil }
        // Apply the previous main's (0,0) first, before placing the iPad.
        result.sort { ($0.x == 0 && $0.y == 0 ? 0 : 1) < ($1.x == 0 && $1.y == 0 ? 0 : 1) }
        result.append(DisplayPlacement(id: ipad, x: x, y: 0))
        return result
    }
}
