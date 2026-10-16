import Foundation

// Fixed, user-scoped action. macOS killall matches the caller's real UID by
// default. Refuse root so this can never become a system-wide service reset.
enum SidecarDiscoveryRepair {
    static let executable = URL(fileURLWithPath: "/usr/bin/killall")
    static func arguments(uid: UInt32, effectiveUID: UInt32) -> [String]? {
        guard uid != 0, effectiveUID == uid else { return nil }
        return ["-TERM", "sharingd"]
    }
    static func allowed(uid: UInt32, effectiveUID: UInt32, connected: Bool, busy: Bool) -> Bool {
        !connected && !busy && arguments(uid: uid, effectiveUID: effectiveUID) != nil
    }
    static let retryDelays: [TimeInterval] = [1.5, 2.5, 4]
}
