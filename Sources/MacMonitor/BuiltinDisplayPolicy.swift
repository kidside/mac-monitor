import Foundation

// Pure decisions: Sidecar/virtual outputs never justify disabling the built-in panel.
enum BuiltinDisplayPolicy {
    enum Action: Equatable { case none, disconnect, reconnect }
    static func action(enabled: Bool, allowed: Bool, suspended: Bool, busy: Bool,
                       connected: Bool, owned: Bool, externalAvailable: Bool, lidState: Int = 0) -> Action {
        guard lidState == 0, !busy else { return .none }
        if owned && !connected && !externalAvailable { return .reconnect }
        if enabled && allowed && !suspended && connected && externalAvailable { return .disconnect }
        return .none
    }
}
