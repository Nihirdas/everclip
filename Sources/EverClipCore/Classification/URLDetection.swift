import Foundation

/// Conservative URL detection: a string is treated as a URL only when a single
/// detected link spans the entire trimmed string. "See example.com now" is not a
/// URL; "https://example.com" and "example.com" are.
public enum URLDetection {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func isWholeStringURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }
        guard let detector else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: range)
        guard matches.count == 1, let match = matches.first, match.resultType == .link else {
            return false
        }
        return match.range == range
    }
}
