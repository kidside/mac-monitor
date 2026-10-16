import Foundation

@main enum SidecarDiscoveryRepairTests {
    static func main() {
        precondition(SidecarDiscoveryRepair.executable.path == "/usr/bin/killall")
        precondition(SidecarDiscoveryRepair.arguments(uid: 501, effectiveUID: 501) == ["-TERM", "sharingd"])
        precondition(SidecarDiscoveryRepair.arguments(uid: 0, effectiveUID: 0) == nil)
        precondition(SidecarDiscoveryRepair.arguments(uid: 501, effectiveUID: 0) == nil)
        precondition(!SidecarDiscoveryRepair.allowed(uid:501,effectiveUID:501,connected:true,busy:false), "Do not drop an active Sidecar display")
        precondition(!SidecarDiscoveryRepair.allowed(uid:501,effectiveUID:501,connected:false,busy:true), "No overlapping resets or configuration changes")
        precondition(SidecarDiscoveryRepair.allowed(uid:501,effectiveUID:501,connected:false,busy:false))
        precondition(SidecarDiscoveryRepair.retryDelays.count == 3 && SidecarDiscoveryRepair.retryDelays.allSatisfy { $0 > 0 })
        print("PASS: exact unprivileged sharingd command, root/setuid refusal, active-session and busy guards, bounded retries; no service restarted")
    }
}
