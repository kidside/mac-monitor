import Foundation

enum HiDPIScaling {
    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    static func sizes(panel: HiDPISize) -> [HiDPISize] {
        guard panel.width > 0, panel.height > 0 else { return [] }
        let divisor = gcd(panel.width, panel.height)
        let x = panel.width / divisor, y = panel.height / divisor
        let minWidth = max(640, panel.width / 2)
        let maxWidth = min(3840, panel.width)
        let lower = max(1, (minWidth + x - 1) / x), upper = maxWidth / x
        guard lower <= upper else { return [] }
        // Approximately 16-pixel steps while keeping the panel's exact ratio.
        let step = max(1, 16 / x)
        var result = stride(from: lower, through: upper, by: step).map { HiDPISize(width: $0 * x, height: $0 * y) }
        result.append(panel)
        return Array(Set(result.filter(\.valid))).sorted { $0.width < $1.width }
    }
    static func nativeChoices(_ sizes: [HiDPISize], modes: [ModeChoice]) -> [HiDPISize] {
        Array(Set(modes.filter(\.hiDPI).map { HiDPISize(width: $0.width, height: $0.height) }))
            .filter { $0.valid }.sorted { $0.width < $1.width }
    }
    static func bestMode(size: HiDPISize, refresh: Double, modes: [ModeChoice]) -> ModeChoice? {
        modes.filter { $0.hiDPI && $0.width == size.width && $0.height == size.height }
            .min { abs($0.refreshRate - refresh) < abs($1.refreshRate - refresh) }
    }
}
