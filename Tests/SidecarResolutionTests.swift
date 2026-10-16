import Foundation
import CoreGraphics

@main enum SidecarResolutionTests {
    static func key(_ id: Int32 = 1, width: Int = 1366, height: Int = 1024,
                    pixels: Int = 2732, refresh: Double = 60) -> SidecarModeKey {
        SidecarModeKey(id: id, width: width, height: height, pixelWidth: pixels, pixelHeight: height * 2, refresh: refresh)
    }
    static func main() throws {
        precondition(key().matches(key(refresh: 59.94)))
        precondition(!key().matches(key(2)))
        precondition(!key().matches(key(width: 1400)), "Mode IDs can be reused after reconnect")
        precondition(!key().matches(key(pixels: 1366)), "Retina backing dimensions must match")
        precondition(!key().matches(key(refresh: 120)))
        precondition(key(refresh: 0).matches(key(refresh: 0)), "Unknown Hz is valid when both report zero")
        precondition(!key(width: 0).valid && !key(width: 999999).valid)
        precondition(!key(refresh: .nan).valid && !key(refresh: .infinity).valid)
        let old = Data(#"{"uuid":"ipad","modeID":1,"x":0,"y":0,"reconnect":false}"#.utf8)
        let legacy = try JSONDecoder().decode(RecoveryRecord.self, from: old)
        precondition(legacy.sidecar == nil)
        let record = RecoveryRecord(uuid:"ipad",displayID:77,modeID:1,x:0,y:0,reconnect:false,
                                    modeProfile:ScreenProfile(width:1366,height:1024,virtual:false,pixelWidth:2732,refresh:60),sidecar:true)
        let restored = try JSONDecoder().decode(RecoveryRecord.self, from: JSONEncoder().encode(record))
        precondition(restored.sidecar == true && restored.modeProfile?.pixelWidth == 2732)
        precondition(DesktopPolicy.relocated(restored,x:1920,y:0).sidecar == true)
        precondition(sidecarDisplayModes(UInt32.max).isEmpty)
        let live = sidecarDisplayModes(CGMainDisplayID())
        precondition(!live.isEmpty && live.allSatisfy { $0.mode != nil && $0.sidecarKey.valid })
        precondition(Set(live.map(\.id)).count == live.count)
        if let current = CGDisplayCopyDisplayMode(CGMainDisplayID()) {
            precondition(live.contains { $0.id == current.ioDisplayModeID })
        }
        print("PASS: Sidecar stale/reused mode rejection, Retina backing, refresh matching, legacy and Sidecar recovery metadata")
    }
}
