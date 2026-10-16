import Foundation

@main
enum OverrideHelperTests {
    static func rejected(_ args: [String]) {
        do { try OverrideHelper.run(args); preconditionFailure("Unsafe operation accepted") }
        catch { }
    }
    static func main() throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: OverrideHelper.testRoot) }
        let target = OverrideHelper.base.appendingPathComponent("DisplayVendorID-1234/DisplayProductID-5678")
        let record = OverrideHelper.backups.appendingPathComponent("1234-5678.plist")
        let args = ["enable", "4660", "22136", "1920x1080,1808x1017"]
        try OverrideHelper.run(args)
        precondition(fm.fileExists(atPath: target.path))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: target), format: nil) as! [String: Any]
        precondition((plist["scale-resolutions"] as! [Data]).count == 2)
        try OverrideHelper.run(["disable", "4660", "22136", ""])
        precondition(!fm.fileExists(atPath: target.path) && !fm.fileExists(atPath: record.path))

        let original = try PropertyListSerialization.data(fromPropertyList: ["existing-color-setting": "preserve", "scale-resolutions": [Data([1,2,3])]], format: .xml, options: 0)
        try original.write(to: target)
        try OverrideHelper.run(args)
        try OverrideHelper.run(["enable", "4660", "22136", "2048x1152"])
        let updated = try PropertyListSerialization.propertyList(from: Data(contentsOf: target), format: nil) as! [String: Any]
        precondition(updated["existing-color-setting"] as? String == "preserve")
        precondition((updated["scale-resolutions"] as! [Data]).count == 4)
        try OverrideHelper.run(["disable", "4660", "22136", ""])
        precondition((try! Data(contentsOf: target)) == original, "Disable restores exact pre-existing bytes")
        try OverrideHelper.run(args)
        let installed = try Data(contentsOf: target)
        try Data("foreign change".utf8).write(to: target)
        rejected(args)
        rejected(["disable", "4660", "22136", ""])
        precondition((try! Data(contentsOf: target)) == Data("foreign change".utf8))
        try installed.write(to: target)
        try OverrideHelper.run(["disable", "4660", "22136", ""])
        try fm.removeItem(at: target)
        try fm.createSymbolicLink(at: target, withDestinationURL: record)
        rejected(args)
        try fm.removeItem(at: target)
        rejected(["enable", "../../etc", "22136", "1920x1080"])
        rejected(["enable", "4660", "22136", "999999999x1080"])
        rejected(["enable", "4660", "22136", ""])
        print("PASS: override install/update/remove, exact backups, unrelated settings, conflicts, symlink rejection and input bounds")
    }
}
