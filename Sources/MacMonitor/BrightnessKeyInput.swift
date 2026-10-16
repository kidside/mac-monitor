import AppKit

struct BrightnessKeyInput: Equatable {
    let step: Double
    let down: Bool
    let label: String

    static func decode(type: UInt32, keyCode: Int64, subtype: Int = 0, data1: Int = 0, flags: CGEventFlags = []) -> Self? {
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return nil }
        if type == CGEventType.keyDown.rawValue || type == CGEventType.keyUp.rawValue {
            // macOS can deliver the sun keys as ordinary key events with
            // dedicated brightness codes (144/145), rather than NX_SYSDEFINED.
            let decrease: Bool
            let label: String
            switch keyCode {
            case 145: decrease = true; label = "Giảm sáng ☀"
            case 144: decrease = false; label = "Tăng sáng ☀"
            default: return nil
            }
            return Self(step: decrease ? -0.0625 : 0.0625,
                        down: type == CGEventType.keyDown.rawValue,
                        label: label)
        }
        if type == 14 && subtype == 8 {
            let key = (data1 >> 16) & 0xffff
            let state = (data1 >> 8) & 0xff
            guard (key == 2 || key == 3), (state == 0x0a || state == 0x0b) else { return nil }
            return Self(step: key == 3 ? -0.0625 : 0.0625, down: state == 0x0a, label: key == 3 ? "Giảm sáng ☀" : "Tăng sáng ☀")
        }
        return nil
    }
}
