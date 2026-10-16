import AppKit

@main enum DesktopPolicyTests {
    static func record(_ id: String, display: UInt32, x: Int32 = 0, y: Int32 = 0, reconnect: Bool = true) -> RecoveryRecord {
        RecoveryRecord(uuid: id, displayID: display, modeID: 7, x: x, y: y, reconnect: reconnect,
                       modeProfile: ScreenProfile(width:1920,height:1080,virtual:false,pixelWidth:3840,refresh:75))
    }
    static func main() {
        let mi = DesktopOutput(id:3,uuid:"Mi",frame:CGRect(x:-1920,y:-100,width:1920,height:1080),active:true)
        let vu = DesktopOutput(id:2,uuid:"VU",frame:CGRect(x:0,y:0,width:1920,height:1080),active:true)
        let builtIn = DesktopOutput(id:1,uuid:"Mac",frame:CGRect(x:0,y:1080,width:1728,height:1117),active:true)
        let outputs = [mi,vu,builtIn]
        let layout = DesktopPolicy.mainLayout(outputs,target:3)!
        precondition(layout.first == DisplayPlacement(id:3,x:0,y:0))
        precondition(layout.contains(DisplayPlacement(id:2,x:1920,y:100)))
        precondition(layout.contains(DisplayPlacement(id:1,x:1920,y:1180)))
        let before = DesktopPolicy.positions(outputs)
        for a in before {for b in before {
            let afterA=layout.first{$0.id==a.id}!,afterB=layout.first{$0.id==b.id}!
            precondition(Int64(a.x)-Int64(b.x)==Int64(afterA.x)-Int64(afterB.x))
            precondition(Int64(a.y)-Int64(b.y)==Int64(afterA.y)-Int64(afterB.y))
        }}
        precondition(DesktopPolicy.mainLayout(outputs,target:99)==nil)
        // A follower's physical name selects its virtual/native mirror source.
        let source=DesktopOutput(id:9,uuid:"virtual",frame:mi.frame,active:true)
        let mirrored=DesktopOutput(id:3,uuid:"Mi",frame:mi.frame,active:false,mirrorSource:9,inMirrorSet:true)
        let mirroredLayout=DesktopPolicy.mainLayout([source,mirrored,vu],target:3)!
        precondition(mirroredLayout.first?.id==9 && !mirroredLayout.contains{$0.id==3})
        // Most important regression: stale recovery must not change any live desktop.
        let stale = [record("Mi",display:3,x:0),record("VU",display:2,x:1920)]
        precondition(DesktopPolicy.startupRecovery(stale,outputs:outputs).isEmpty)
        precondition(DesktopPolicy.startupRecovery([record("Mi",display:3)],outputs:[source,mirrored,vu]).isEmpty)
        let disabled=DesktopOutput(id:2,uuid:"VU",frame:.zero,active:false)
        let mainMi=DesktopOutput(id:3,uuid:"Mi",frame:CGRect(x:0,y:0,width:1920,height:1080),active:true)
        let plan=DesktopPolicy.startupRecovery([record("Mi",display:3,x:-1920),record("VU",display:2,x:0)],outputs:[mainMi,disabled])
        precondition(plan.count==1 && plan[0].uuid=="VU" && plan[0].x==1920 && plan[0].y==0,
                     "Reconnecting the old main must not take (0,0) from the current main")
        precondition(DesktopPolicy.startupRecovery([record("VU",display:2,reconnect:false)],outputs:[disabled]).isEmpty)
        precondition(DesktopPolicy.startupRecovery([record("old-VU",display:2)],outputs:[disabled]).isEmpty,
                     "A reused display ID does not authorize restoring another monitor")
        let original=record("Mi",display:3,x:-1920)
        let moved=DesktopPolicy.relocated(original,x:0,y:100)
        precondition(moved.modeID==original.modeID && moved.modeProfile?.pixelWidth==3840 && moved.reconnect)
        print("PASS: main-display translation, relative layout, mirror routing, read-only startup and safe disabled-display recovery")
    }
}
