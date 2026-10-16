import Foundation
import Darwin

// Fixed filesystem operation invoked only by the authenticated XPC service.
// All destinations are fixed and input is restricted to display IDs and sizes.
#if !OVERRIDE_TESTS
@main
#endif
struct OverrideHelper {
#if OVERRIDE_TESTS
    static var testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MacMonitor-override-tests-\(UUID().uuidString)")
    static var base: URL { testRoot.appendingPathComponent("overrides") }
    static var backups: URL { testRoot.appendingPathComponent("backups") }
#else
    static let base = URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides", isDirectory: true)
    static let backups = URL(fileURLWithPath: "/Library/Application Support/MacMonitor/DisplayOverrides", isDirectory: true)
#endif
    static func fail(_ text: String) throws -> Never { throw NSError(domain: "MacMonitor", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func safe(_ url: URL) throws {
        var part = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            part.appendPathComponent(component)
#if OVERRIDE_TESTS
            if !part.path.hasPrefix(testRoot.path) { continue }
            let owner = geteuid()
#else
            let owner: uid_t = 0
#endif
            var info = stat()
            if lstat(part.path, &info) == 0 {
                guard info.st_mode & S_IFMT != S_IFLNK, info.st_uid == owner,
                      info.st_mode & 0o022 == 0 else { try fail("Unsafe destination: \(part.lastPathComponent)") }
            } else if errno != ENOENT { try fail("Cannot inspect destination") }
        }
    }
    static func write(_ data: Data, _ url: URL) throws {
        try safe(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o755])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }
    static func run(_ args: [String]) throws {
#if !OVERRIDE_TESTS
        guard geteuid() == 0 else { try fail("Administrator authorization required") }
#endif
        guard args.count == 4, ["enable", "disable"].contains(args[0]),
              let vendor = UInt32(args[1]), let product = UInt32(args[2]), vendor > 0, product > 0,
              vendor != 0x4D4D else { try fail("Invalid display operation") }
        let key = "\(String(vendor, radix: 16))-\(String(product, radix: 16))"
        let target = base.appendingPathComponent("DisplayVendorID-\(String(vendor, radix: 16))")
            .appendingPathComponent("DisplayProductID-\(String(product, radix: 16))")
        let recordURL = backups.appendingPathComponent(key + ".plist")
        try safe(target); try safe(recordURL)
        let existing = FileManager.default.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
        let recordData = FileManager.default.fileExists(atPath: recordURL.path) ? try Data(contentsOf: recordURL) : nil
        var record = try recordData.map { try PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? nil
        if recordData != nil {
            guard let record, record["installed"] is Data,
                  record["original"] == nil || record["original"] is Data else { try fail("Invalid backup; refusing to replace it") }
        }
        if let record, record["installed"] as? Data != existing {
            let pending = record["pending"] as? Bool == true
            let previous = record["previous"] as? Data
            guard pending && previous == existing else { try fail("Configuration changed by another app; refusing to overwrite it") }
        }
        if args[0] == "disable" {
            guard let record else { try fail("No Mac Monitor configuration to remove") }
            if let original = record["original"] as? Data { try write(original, target) }
            else if existing != nil { try FileManager.default.removeItem(at: target) }
            try FileManager.default.removeItem(at: recordURL)
            return
        }
        let tokens = args[3].split(separator: ",")
        guard !tokens.isEmpty, tokens.count <= 256 else { try fail("Invalid resolution count") }
        let sizes = try tokens.map { token -> HiDPISize in
            let parts = token.split(separator: "x")
            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { try fail("Invalid size") }
            let size = HiDPISize(width: width, height: height)
            guard size.valid else { try fail("Resolution exceeds supported range") }
            return size
        }
        var plist: [String: Any] = [:]
        if let existing {
            guard let decoded = try PropertyListSerialization.propertyList(from: existing, format: nil) as? [String: Any] else { try fail("Invalid existing override") }
            plist = decoded
        }
        if plist["scale-resolutions"] != nil && !(plist["scale-resolutions"] is [Data]) {
            try fail("Unknown existing resolution format; refusing to replace it")
        }
        var modes = plist["scale-resolutions"] as? [Data] ?? []
        for size in sizes where !modes.contains(size.overrideData) { modes.append(size.overrideData) }
        plist["DisplayVendorID"] = vendor; plist["DisplayProductID"] = product
        plist["scale-resolutions"] = modes
        let installed = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        if record == nil {
            record = [:]
            if let existing { record?["original"] = existing }
        }
        // Keep the original backup; the current installed bytes detect conflicts.
        record?["installed"] = installed
        record?["pending"] = true
        record?["previous"] = existing
        let data = try PropertyListSerialization.data(fromPropertyList: record!, format: .xml, options: 0)
        // Save a recovery record before the display configuration is changed.
        try write(data, recordURL)
        do { try write(installed, target) }
        catch {
            // Leave the old installation/backup coherent after a failed write.
            if let recordData { try? write(recordData, recordURL) }
            else { try? FileManager.default.removeItem(at: recordURL) }
            throw error
        }
        record?.removeValue(forKey: "pending"); record?.removeValue(forKey: "previous")
        // A crash before cleanup still has a recoverable pending record.
        if let clean = try? PropertyListSerialization.data(fromPropertyList: record!, format: .xml, options: 0) {
            try? write(clean, recordURL)
        }
    }
    static func main() {
#if !OVERRIDE_TESTS
        DisplayOverrideService.run()
#endif
    }
}
