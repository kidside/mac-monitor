import Foundation
import Security
import ServiceManagement

// Called only by an explicit install/remove button, never during app startup.
enum OverrideServiceClient {
    static var supported: Bool { OverrideServiceSecurity.teamIdentifier != nil }
    static func run(_ arguments: [String]) -> (Int32, String) {
        guard let team = OverrideServiceSecurity.teamIdentifier,
              let requirement = OverrideServiceSecurity.requirement(identifier: OverrideServiceSecurity.helperIdentifier, team: team) else {
            return (-1, "Cài thêm cấu hình hệ thống cần bản phát hành Developer ID đã được Apple xác nhận. Bản thử nghiệm này vẫn dùng được HiDPI có sẵn và màn ảo.")
        }
        let service = SMAppService.daemon(plistName: OverrideServiceSecurity.plistName)
        do {
            if service.status == .notRegistered || service.status == .notFound { try service.register() }
            guard service.status == .enabled else {
                if service.status == .requiresApproval {
                    DispatchQueue.main.async { SMAppService.openSystemSettingsLoginItems() }
                    return (-1, "Cho phép dịch vụ Mac Monitor trong Login Items & Extensions, rồi thử lại.")
                }
                return (-1, "Dịch vụ cấu hình màn hình chưa sẵn sàng.")
            }
            let (authorization, data) = try OverrideServiceSecurity.authorize()
            defer { AuthorizationFree(authorization, [.destroyRights]) }
            let connection = NSXPCConnection(machServiceName: OverrideServiceSecurity.serviceName, options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            connection.remoteObjectInterface = OverrideServiceSecurity.interface()
            let result = OverrideServiceReply()
            connection.invalidationHandler = { result.finish(-1, "Không kết nối được dịch vụ cấu hình màn hình.") }
            connection.interruptionHandler = { result.finish(-1, "Kết nối dịch vụ bị gián đoạn. Kiểm tra cấu hình trước khi thử lại.") }
            connection.resume()
            defer { connection.invalidate() }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                result.finish(-1, "Không xác thực được dịch vụ cấu hình màn hình.")
            }) as? DisplayOverrideServiceProtocol else { return (-1, "Dịch vụ cấu hình màn hình chưa sẵn sàng.") }
            proxy.apply(arguments, authorization: data) { status, output in result.finish(status, output) }
            return result.wait()
        } catch {
            let error = error as NSError
            return (Int32(clamping: error.code), "Không hoàn tất cấp phép dịch vụ cấu hình màn hình.")
        }
    }
    static func unregister() throws {
        // Unregistering the daemon does not delete existing display overrides.
        try SMAppService.daemon(plistName: OverrideServiceSecurity.plistName).unregister()
    }
}

private final class OverrideServiceReply {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: (Int32, String)?
    func finish(_ status: Int32, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        guard value == nil else { return }
        value = (status, message); semaphore.signal()
    }
    func wait() -> (Int32, String) {
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            return (-1, "Chưa nhận được xác nhận từ dịch vụ. Kiểm tra cấu hình trước khi thử lại.")
        }
        lock.lock(); defer { lock.unlock() }
        return value ?? (-1, "Dịch vụ cấu hình màn hình chưa sẵn sàng.")
    }
}
