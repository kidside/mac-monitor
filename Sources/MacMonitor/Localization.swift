import Foundation

enum AppLanguage: String, CaseIterable {
    case automatic, vietnamese = "vi", english = "en"
    static func resolved(_ preference: String?, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if preference == "vi" { return .vietnamese }
        if preference == "en" { return .english }
        return preferred.first?.lowercased().hasPrefix("vi") == true ? .vietnamese : .english
    }
}

struct TranslationCatalog {
    private let exact: [String: String]
    private let patterns: [(NSRegularExpression, String, Int)]
    init(_ values: [String: String]) {
        exact = values
        patterns = values.filter { $0.key.contains("{0}") }
            .sorted { $0.key.count > $1.key.count }.compactMap { source, target in
                let parts = source.components(separatedBy: try! NSRegularExpression(pattern: "\\{[0-9]+\\}"))
                let count = parts.count - 1
                let expression = "^" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.+?)") + "$"
                guard let regex = try? NSRegularExpression(pattern: expression, options: .dotMatchesLineSeparators) else { return nil }
                return (regex, target, count)
            }
    }
    func translate(_ text: String) -> String {
        if let translated = exact[text] { return translated }
        for (pattern, target, count) in patterns {
            guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            var translated = target
            // Replace higher indices first so values containing braces cannot
            // accidentally become another format argument.
            for i in (0..<count).reversed() {
                guard let range = Range(match.range(at: i + 1), in: text) else { continue }
                let argument = String(text[range])
                translated = translated.replacingOccurrences(of: "{\(i)}", with: argument.count < text.count ? translate(argument) : argument)
            }
            return translated
        }
        return text
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        var result: [String] = []; var start = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self) else { continue }
            result.append(String(self[start..<range.lowerBound])); start = range.upperBound
        }
        result.append(String(self[start...])); return result
    }
}

private let englishCatalog: TranslationCatalog = {
    guard let url = Bundle.main.url(forResource: "English", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let values = try? JSONDecoder().decode([String: String].self, from: data) else { return TranslationCatalog([:]) }
    return TranslationCatalog(values)
}()

func L(_ text: String) -> String {
    AppLanguage.resolved(UserDefaults.standard.string(forKey: "appLanguage")) == .vietnamese
        ? text : englishCatalog.translate(text)
}
