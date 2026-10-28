import Foundation

public enum StagedSearch {
    /// Stages are lazy: neither capture nor OCR starts until the preceding stage misses.
    public static func candidates(prefix: String, excluding currentWord: String? = nil, stages: [() async throws -> [String]]) async throws -> [String] {
        var firstError: Error?
        for stage in stages {
            try Task.checkCancellation()
            do {
                let matches = Matcher.candidates(lines: try await stage(), prefix: prefix, excluding: currentWord)
                if !matches.isEmpty { return matches }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A window can disappear or decline capture; wider stages can still succeed.
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
        return []
    }
}
