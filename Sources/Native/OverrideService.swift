import Foundation
import Darwin

final class DisplayOverrideService: NSObject, NSXPCListenerDelegate, DisplayOverrideServiceProtocol {
    // Serialize all clients so backup/read/check/write is one logical operation.
    private let operations = DispatchQueue(label: "MacMonitor.PrivilegedOverrides")
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard geteuid() == 0, connection.effectiveUserIdentifier != 0,
              let team = OverrideServiceSecurity.teamIdentifier,
              let requirement = OverrideServiceSecurity.requirement(identifier: OverrideServiceSecurity.appIdentifier, team: team) else { return false }
        // Framework validates the actual message sender, not a PID looked up later.
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = OverrideServiceSecurity.interface()
        connection.exportedObject = self
        connection.resume()
        return true
    }
    func apply(_ arguments: [String], authorization: Data, reply: @escaping (Int32, String) -> Void) {
        guard arguments.count == 4, arguments.allSatisfy({ $0.utf8.count <= 16384 }), authorization.count == 32 else {
            reply(-1, "Invalid request"); return
        }
        operations.async {
            guard OverrideServiceSecurity.authorized(authorization) else { reply(-60005, "Administrator authorization required"); return }
            do { try OverrideHelper.run(arguments); reply(0, "OK") }
            catch { reply(-1, error.localizedDescription) }
        }
    }
    static func run() -> Never {
        // No elevated CLI mode or legacy privileged execution fallback.
        guard geteuid() == 0, CommandLine.arguments.count == 1,
              OverrideServiceSecurity.teamIdentifier != nil else { exit(1) }
        let delegate = DisplayOverrideService()
        let listener = NSXPCListener(machServiceName: OverrideServiceSecurity.serviceName)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime((delegate, listener)) { RunLoop.current.run() }
        exit(0)
    }
}
