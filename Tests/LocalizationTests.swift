import Foundation

@main enum LocalizationTests {
    static func main() throws {
        let values = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: URL(fileURLWithPath:"Resources/English.json")))
        let catalog=TranslationCatalog(values)
        precondition(AppLanguage.resolved(nil,preferred:["vi-VN"]) == .vietnamese)
        precondition(AppLanguage.resolved("automatic",preferred:["fr-FR","vi"]) == .english)
        precondition(AppLanguage.resolved("vi",preferred:["en-US"]) == .vietnamese)
        precondition(AppLanguage.resolved("en",preferred:["vi-VN"]) == .english)
        precondition(AppLanguage.resolved("invalid",preferred:[]) == .english)
        precondition(catalog.translate("Khôi phục tất cả") == "Restore all")
        precondition(catalog.translate("2 màn hình ngoài đang hoạt động") == "2 external displays active")
        precondition(catalog.translate("1 màn hình ngoài đang hoạt động") == "1 external display active")
        precondition(catalog.translate("Giữ HiDPI 1920 × 1080?") == "Keep HiDPI 1920 × 1080?")
        precondition(catalog.translate("Đã nhận Tăng sáng ☀ · chọn màn hình để chỉnh sáng") == "Recognized Brightness up ☀ · select a display to adjust brightness")
        precondition(catalog.translate("Ngắt kết nối không thành công (macOS: 1001).") == "Disconnect failed (macOS: 1001).")
        precondition(catalog.translate("Tự khôi phục sau 12 giây.") == "Reverting in 12 seconds.")
        precondition(catalog.translate("Mi Monitor") == "Mi Monitor")
        precondition(catalog.translate("Restore all") == "Restore all")
        let regex=try NSRegularExpression(pattern:"\\{[0-9]+\\}")
        func placeholders(_ s:String)->Set<String>{Set(regex.matches(in:s,range:NSRange(s.startIndex...,in:s)).compactMap{Range($0.range,in:s).map{String(s[$0])}})}
        for (source,target) in values {
            precondition(!target.isEmpty)
            precondition(placeholders(source)==placeholders(target),"Translation arguments differ for \(source)")
        }
        print("PASS: automatic/manual language, fallback, dynamic messages, nested actions, singular display and all catalog placeholders")
    }
}
