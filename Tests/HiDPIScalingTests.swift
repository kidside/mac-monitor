import AppKit

@main
enum HiDPIScalingTests {
    static func main() {
        let qhd = HiDPIScaling.sizes(panel: HiDPISize(width: 2560, height: 1440))
        precondition(qhd.count == 81 && qhd.first?.width == 1280 && qhd.last?.width == 2560)
        precondition(qhd.contains(HiDPISize(width: 1920, height: 1080)))
        precondition(qhd.contains(HiDPISize(width: 1808, height: 1017)))
        for panel in [HiDPISize(width: 1920, height: 1080), HiDPISize(width: 3840, height: 2160),
                      HiDPISize(width: 3440, height: 1440), HiDPISize(width: 1920, height: 1200),
                      HiDPISize(width: 1440, height: 2560)] {
            let modes = HiDPIScaling.sizes(panel: panel)
            precondition(!modes.isEmpty)
            precondition(modes.allSatisfy { $0.valid && $0.width * panel.height == $0.height * panel.width }, "Maintain aspect ratio for QHD, FHD, 4K, ultrawide and portrait")
            precondition(Set(modes).count == modes.count)
        }
        precondition(HiDPIScaling.sizes(panel: HiDPISize(width: 0, height: 0)).isEmpty)
        precondition(!HiDPISize(width: -1, height: 1080).valid)
        precondition(!HiDPISize(width: 4000, height: 2160).valid)
        precondition(!HiDPISize(width: 3840, height: 3840).valid)
        let bytes = Array(HiDPISize(width: 1920, height: 1080).overrideData)
        precondition(bytes == [0,0,15,0, 0,0,8,112, 0,0,0,1, 2,0,0,0], "Override is 3840x2160 backing with HiDPI flags, in big endian")
        let data = try! PropertyListSerialization.data(fromPropertyList: ["scale-resolutions": [Data(bytes)]], format: .xml, options: 0)
        let decoded = try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        precondition((decoded["scale-resolutions"] as! [Data])[0] == Data(bytes))
        print("PASS: dense scaling, custom 1808 mode, aspect ratios, size limits and native override encoding")
    }
}
