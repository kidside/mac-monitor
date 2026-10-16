import Foundation

struct HiDPISize: Codable, Hashable, Identifiable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }
    var valid: Bool {
        (640...3840).contains(width) && (360...3840).contains(height) &&
        width * 2 <= 7680 && height * 2 <= 7680 && width * height <= 8_294_400
    }
    // Explicit 2x backing dimensions, encoded as big-endian override data.
    var overrideData: Data {
        [UInt32(width * 2), UInt32(height * 2), 1, 0x02000000].reduce(into: Data()) { data, word in
            var big = word.bigEndian
            withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
        }
    }
}

