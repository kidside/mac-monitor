import Foundation

struct SidecarDevice: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let connected: Bool
    let displayID: UInt32
}
struct SidecarSnapshot: Codable {
    let supported: Bool
    let error: String
    let devices: [SidecarDevice]

    static func decode(_ data: Data) throws -> SidecarSnapshot {
        guard data.count <= 65536 else { throw CocoaError(.coderReadCorrupt) }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.devices.count <= 64,
              Set(result.devices.map(\.id)).count == result.devices.count,
              result.devices.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 4096 && $0.name.utf8.count <= 2048 })
        else { throw CocoaError(.coderReadCorrupt) }
        return result
    }
    var displayIDs: Set<UInt32> { Set(devices.filter(\.connected).map(\.displayID).filter { $0 != 0 }) }
}
