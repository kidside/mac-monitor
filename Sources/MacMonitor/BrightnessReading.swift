import Foundation

struct BrightnessReading: Decodable {
    let current: Int
    let maximum: Int
    var normalized: Double? {
        guard maximum > 0, maximum <= 1_000, current >= 0, current <= maximum else { return nil }
        return Double(current) / Double(maximum)
    }
    func matches(requested: Int, maximum: Int) -> Bool {
        normalized != nil && self.maximum == maximum && abs(current - requested) <= 1
    }
}
