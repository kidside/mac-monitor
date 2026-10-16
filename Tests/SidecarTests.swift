import Foundation
import CoreGraphics

@main enum SidecarTests {
    static func main() throws {
        let sameName = Data(#"{"supported":true,"error":"","devices":[{"id":"ipad-a","name":"iPad","connected":true,"displayID":77},{"id":"ipad-b","name":"iPad","connected":false,"displayID":0}]}"#.utf8)
        let decoded = try SidecarSnapshot.decode(sameName)
        precondition(decoded.devices.count == 2 && decoded.devices[0].id != decoded.devices[1].id)
        precondition(decoded.displayIDs == [77])
        let badDuplicate = Data(#"{"supported":true,"error":"","devices":[{"id":"a","name":"iPad","connected":true,"displayID":77},{"id":"a","name":"iPad","connected":false,"displayID":0}]}"#.utf8)
        do { _ = try SidecarSnapshot.decode(badDuplicate); preconditionFailure("Duplicate IDs accepted") } catch {}
        do { _ = try SidecarSnapshot.decode(Data(repeating: 32, count: 65537)); preconditionFailure("Unbounded output accepted") } catch {}
        do { _ = try SidecarSnapshot.decode(Data("{}".utf8)); preconditionFailure("Missing state accepted") } catch {}
        let mi = DesktopOutput(id:3, uuid:"mi", frame:CGRect(x:0,y:0,width:1920,height:1080), active:true)
        let virtual = DesktopOutput(id:9, uuid:"virtual", frame:CGRect(x:1920,y:-100,width:1920,height:1080), active:true)
        let vu = DesktopOutput(id:2, uuid:"vu", frame:virtual.frame, active:false, mirrorSource:9, inMirrorSet:true)
        let ipad = DesktopOutput(id:77, uuid:"ipad", frame:mi.frame, active:false, mirrorSource:3, inMirrorSet:true)
        let old = [mi, virtual, vu]
        let result = SidecarLayout.placements(previous:old,current:old+[ipad],ipad:77)!
        precondition(result.first == DisplayPlacement(id:3,x:0,y:0))
        precondition(result.contains(DisplayPlacement(id:9,x:1920,y:-100)))
        precondition(!result.contains { $0.id == 2 }) // Preserve the physical/virtual HiDPI mirror.
        precondition(result.last == DisplayPlacement(id:77,x:3840,y:0))
        // Refuse to restore stale arrangements after cable changes or output ID reuse.
        precondition(SidecarLayout.placements(previous:old,current:[mi,ipad],ipad:77) == nil)
        let unrelated=DesktopOutput(id:80,uuid:"new",frame:mi.frame,active:true)
        precondition(SidecarLayout.placements(previous:old,current:old+[ipad,unrelated],ipad:77) == nil)
        let reused=DesktopOutput(id:9,uuid:"different",frame:virtual.frame,active:true)
        precondition(SidecarLayout.placements(previous:old,current:[mi,reused,vu,ipad],ipad:77) == nil)
        precondition(SidecarLayout.placements(previous:old+[DesktopOutput(id:77,uuid:"ipad",frame:mi.frame,active:true)],current:old+[ipad],ipad:77)==nil)
        let lostSource=DesktopOutput(id:9,uuid:"virtual",frame:virtual.frame,active:false,mirrorSource:77)
        precondition(SidecarLayout.placements(previous:old,current:[mi,lostSource,vu,ipad],ipad:77)==nil)
        print("PASS: Sidecar device identity, bounded/validated replies, preserve main and virtual HiDPI layout, reject stale topology")
    }
}
