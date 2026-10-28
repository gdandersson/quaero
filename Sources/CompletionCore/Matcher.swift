import Foundation

public enum Matcher {
    private static func isTokenBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character == "/" || character == "\\"
    }

    public static func tokenRanges(in text: String) -> [Range<String.Index>] {
        text.split(whereSeparator: isTokenBoundary).map { $0.startIndex..<$0.endIndex }
    }

    public static func ignoringPunctuation(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
    }

    public static func prefix(before text: String) -> String {
        ignoringPunctuation(String(text.reversed().prefix { !isTokenBoundary($0) }.reversed()))
    }

    public static func wordAtCursor(in text: String, selection: NSRange?) -> String? {
        guard let selection else {
            // A one-word field is unambiguous even when the app omits its caret range.
            guard !text.isEmpty, !text.contains(where: isTokenBoundary) else { return nil }
            return ignoringPunctuation(text)
        }
        guard selection.length == 0, let range = Range(selection, in: text) else { return nil }
        let left = text[..<range.lowerBound].reversed().prefix { !isTokenBoundary($0) }.reversed()
        let right = text[range.lowerBound...].prefix { !isTokenBoundary($0) }
        let word = ignoringPunctuation(String(left) + String(right))
        return word.isEmpty ? nil : word
    }

    public static func candidates(lines: [String], prefix: String, excluding currentWord: String? = nil) -> [String] {
        let prefix = ignoringPunctuation(prefix)
        let excluded = currentWord.map { ignoringPunctuation($0).lowercased() }
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            // Split path components before removing punctuation, so filenames remain searchable.
            for raw in line.split(whereSeparator: isTokenBoundary) {
                let word = ignoringPunctuation(String(raw))
                guard word.count > prefix.count,
                      word.lowercased() != excluded,
                      word.lowercased().hasPrefix(prefix.lowercased()),
                      seen.insert(word.lowercased()).inserted else { continue }
                result.append(word)
            }
        }
        return result.sorted {
            if $0.count != $1.count { return $0.count < $1.count }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public static func suffix(of candidate: String, after prefix: String) -> String {
        String(ignoringPunctuation(candidate).dropFirst(ignoringPunctuation(prefix).count))
    }
}
