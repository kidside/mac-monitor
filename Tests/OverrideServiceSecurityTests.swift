import Foundation
import Security

private final class Probe: NSObject, DisplayOverrideServiceProtocol, NSXPCListenerDelegate {
    let expectedClient: String
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    init(_ requirement: String) { expectedClient = requirement }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(expectedClient)
        connection.exportedInterface = OverrideServiceSecurity.interface()
        connection.exportedObject = self
        connection.resume()
        return true
    }
    func apply(_ arguments: [String], authorization: Data, reply: @escaping (Int32, String) -> Void) {
        lock.lock(); calls += 1; lock.unlock()
        reply(0, "unexpected")
    }
}

@main enum OverrideServiceSecurityTests {
    static func main() {
        let security = OverrideServiceSecurity.self
        precondition(security.teamIdentifier == nil, "Unsigned/ad-hoc tests must never qualify for root service")
        precondition(security.validTeam("AB12CD34EF"))
        for bad in ["", "A", "12345678901", "ab12cd34ef", "A\" or true"] { precondition(!security.validTeam(bad)) }
        precondition(security.requirement(identifier: "attacker.app", team: "AB12CD34EF") == nil)
        precondition(security.requirement(identifier: security.appIdentifier, team: "\" or true") == nil)
        precondition(!security.authorized(Data()))
        precondition(!security.authorized(Data(repeating: 0, count: 31)))
        precondition(!security.authorized(Data(repeating: 0, count: 32)))
        let client = security.requirement(identifier: security.appIdentifier, team: "AB12CD34EF")!
        precondition(security.requirement(identifier: security.helperIdentifier, team: "AB12CD34EF") != nil)
        var requirement: SecRequirement?
        precondition(SecRequirementCreateWithString(client as CFString, [], &requirement) == errSecSuccess)
        var ownCode: SecCode?
        precondition(SecCodeCopySelf([], &ownCode) == errSecSuccess)
        precondition(SecCodeCheckValidity(ownCode!, [], requirement) != errSecSuccess)
        // First verify the real interface can round-trip Foundation arguments.
        let allowedListener = NSXPCListener.anonymous()
        var staticCode: SecStaticCode?
        precondition(SecCodeCopyStaticCode(ownCode!, [], &staticCode) == errSecSuccess)
        var ownRequirement: SecRequirement?
        precondition(SecCodeCopyDesignatedRequirement(staticCode!, [], &ownRequirement) == errSecSuccess)
        var ownRequirementText: CFString?
        precondition(SecRequirementCopyString(ownRequirement!, [], &ownRequirementText) == errSecSuccess)
        let allowedProbe = Probe(ownRequirementText! as String)
        allowedListener.delegate = allowedProbe; allowedListener.resume()
        let allowedConnection = NSXPCConnection(listenerEndpoint: allowedListener.endpoint)
        allowedConnection.remoteObjectInterface = OverrideServiceSecurity.interface()
        allowedConnection.resume()
        let replied = DispatchSemaphore(value: 0)
        let allowedProxy = allowedConnection.remoteObjectProxy as! DisplayOverrideServiceProtocol
        allowedProxy.apply(["disable", "1", "1", ""], authorization: Data(repeating: 1, count: 32)) { status, text in
            precondition(status == 0 && text == "unexpected"); replied.signal()
        }
        precondition(replied.wait(timeout: .now() + 5) == .success)
        precondition(allowedProbe.count == 1)
        allowedConnection.invalidate(); allowedListener.invalidate()
        // Exercise the real XPC framework: a caller with the wrong signature
        // must be rejected before the exported privileged method is reached.
        let listener = NSXPCListener.anonymous()
        let probe = Probe(client)
        listener.delegate = probe; listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = OverrideServiceSecurity.interface()
        connection.resume()
        let rejected = DispatchSemaphore(value: 0)
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in rejected.signal() } as! DisplayOverrideServiceProtocol
        proxy.apply(["disable", "1", "1", ""], authorization: Data(repeating: 0, count: 32)) { _, _ in rejected.signal() }
        precondition(rejected.wait(timeout: .now() + 5) == .success, "XPC did not report signature failure")
        precondition(probe.count == 0, "Untrusted caller reached exported method")
        connection.invalidate(); listener.invalidate()
        let denied = OverrideServiceClient.run(["enable", "1", "1", "1920x1080"])
        precondition(denied.0 != 0 && !denied.1.isEmpty, "Ad-hoc client must fail before service registration or authorization UI")
        print("PASS: signature requirements, malformed authorization rejection, real XPC rejects untrusted caller, ad-hoc client fails closed")
    }
}
