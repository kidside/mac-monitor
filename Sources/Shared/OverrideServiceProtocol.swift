import Foundation
import Security

// Explicit Objective-C name keeps the XPC interface identical across app/helper modules.
@objc(MMDisplayOverrideServiceProtocol) protocol DisplayOverrideServiceProtocol {
    func apply(_ arguments: [String], authorization: Data, reply: @escaping (Int32, String) -> Void)
}

enum OverrideServiceSecurity {
    static let appIdentifier = "local.anle.MacMonitor"
    static let helperIdentifier = "local.anle.MacMonitor.DisplayOverrideHelper"
    static let serviceName = "local.anle.MacMonitor.DisplayOverrideService"
    static let plistName = serviceName + ".plist"
    static let adminRight = "system.privilege.admin"
    static func interface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: DisplayOverrideServiceProtocol.self)
        let selector = #selector(DisplayOverrideServiceProtocol.apply(_:authorization:reply:))
        interface.setClasses(NSSet(array: [NSArray.self, NSString.self]) as! Set<AnyHashable>, for: selector, argumentIndex: 0, ofReply: false)
        interface.setClasses(NSSet(array: [NSData.self]) as! Set<AnyHashable>, for: selector, argumentIndex: 1, ofReply: false)
        interface.setClasses(NSSet(array: [NSString.self]) as! Set<AnyHashable>, for: selector, argumentIndex: 1, ofReply: true)
        return interface
    }


    // Only a Developer ID release can register a notarized LaunchDaemon.
    // Derive our team from the running code, never a writable preferences file.
    static let teamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        let predicate = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(predicate as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              let flags = values[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & SecCodeSignatureFlags.runtime.rawValue != 0,
              validTeam(team),
              let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let ownPredicate = OverrideServiceSecurity.requirement(identifier: identifier, team: team) else { return nil }
        var ownRequirement: SecRequirement?
        guard SecRequirementCreateWithString(ownPredicate as CFString, [], &ownRequirement) == errSecSuccess,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), ownRequirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], ownRequirement) == errSecSuccess else { return nil }
        return team
    }()

    static func validTeam(_ team: String) -> Bool {
        team.utf8.count == 10 && team.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }
    static func requirement(identifier: String, team: String) -> String? {
        guard [appIdentifier, helperIdentifier].contains(identifier), validTeam(team) else { return nil }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return text
    }
    static func copyAdminRight(_ authorization: AuthorizationRef, interactive: Bool) -> OSStatus {
        adminRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                let flags: AuthorizationFlags = interactive ? [.extendRights, .interactionAllowed] : [.extendRights]
                return AuthorizationCopyRights(authorization, &rights, nil, flags, nil)
            }
        }
    }
    static func authorize() throws -> (AuthorizationRef, Data) {
        var reference: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &reference)
        guard status == errAuthorizationSuccess, let reference else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let result = copyAdminRight(reference, interactive: true)
        var external = AuthorizationExternalForm()
        let encoded = result == errAuthorizationSuccess ? AuthorizationMakeExternalForm(reference, &external) : result
        guard encoded == errAuthorizationSuccess else {
            AuthorizationFree(reference, [.destroyRights])
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(encoded))
        }
        return (reference, withUnsafeBytes(of: &external) { Data($0) })
    }
    static func authorized(_ data: Data) -> Bool {
        guard data.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
        var external = AuthorizationExternalForm()
        _ = withUnsafeMutableBytes(of: &external) { data.copyBytes(to: $0) }
        var reference: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&external, &reference) == errAuthorizationSuccess,
              let reference else { return false }
        defer { AuthorizationFree(reference, []) }
        // No UI interaction or rights database mutation is allowed in the daemon.
        return copyAdminRight(reference, interactive: false) == errAuthorizationSuccess
    }
}
