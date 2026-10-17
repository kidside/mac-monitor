import Foundation
@main enum BuiltinDisplayPolicyTests {
    static func main() {
        typealias P = BuiltinDisplayPolicy
        precondition(P.action(enabled: true, allowed: true, suspended: false, busy: false, connected: true, owned: false, externalAvailable: true) == .disconnect)
        for allowed in [false, true] {
            precondition(P.action(enabled: true, allowed: allowed, suspended: false, busy: false, connected: true, owned: false, externalAvailable: false) == .none)
        }
        precondition(P.action(enabled: true, allowed: false, suspended: false, busy: false, connected: true, owned: false, externalAvailable: true) == .none)
        precondition(P.action(enabled: true, allowed: true, suspended: true, busy: false, connected: true, owned: false, externalAvailable: true) == .none)
        precondition(P.action(enabled: true, allowed: true, suspended: false, busy: true, connected: true, owned: false, externalAvailable: true) == .none)
        precondition(P.action(enabled: false, allowed: false, suspended: true, busy: false, connected: false, owned: true, externalAvailable: false) == .reconnect)
        precondition(P.action(enabled: true, allowed: true, suspended: false, busy: false, connected: false, owned: false, externalAvailable: false) == .none)
        for lid in [-1, 1] {
            precondition(P.action(enabled: true, allowed: true, suspended: false, busy: false, connected: true, owned: false, externalAvailable: true, lidState: lid) == .none)
            precondition(P.action(enabled: false, allowed: false, suspended: false, busy: false, connected: false, owned: true, externalAvailable: false, lidState: lid) == .none)
        }
        print("PASS: built-in opt-in, physical-screen requirement, busy/suspension guards and owned-screen recovery")
    }
}
