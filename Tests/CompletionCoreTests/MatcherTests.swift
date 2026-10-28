import XCTest
@testable import CompletionCore

final class MatcherTests: XCTestCase {
    func testCurrentWordIsExcludedWithoutCaretRange() {
        let word = Matcher.wordAtCursor(in: "multi", selection: nil)
        XCTAssertEqual(word, "multi")
        XCTAssertEqual(Matcher.candidates(lines: ["multi MULTI multi! multiple"], prefix: "", excluding: word), ["multiple"])
        XCTAssertNil(Matcher.wordAtCursor(in: "hello multi", selection: nil))
    }

    func testCurrentWordAtEndAndInsideWord() {
        XCTAssertEqual(Matcher.wordAtCursor(in: "hello multi", selection: NSRange(location: 11, length: 0)), "multi")
        let word = Matcher.wordAtCursor(in: "hello multiple", selection: NSRange(location: 9, length: 0))
        XCTAssertEqual(word, "multiple")
        XCTAssertEqual(Matcher.candidates(lines: ["multiple multiply"], prefix: "mul", excluding: word), ["multiply"])
    }

    func testCurrentWordUsesUTF16CaretOffsets() {
        XCTAssertEqual(Matcher.wordAtCursor(in: "👋 café", selection: NSRange(location: 7, length: 0)), "café")
        XCTAssertNil(Matcher.wordAtCursor(in: "multi", selection: NSRange(location: 50, length: 0)))
        XCTAssertNil(Matcher.wordAtCursor(in: "multi", selection: NSRange(location: 0, length: 5)))
    }
    func testPrefixIgnoresPunctuationAndKeepsUnicode() {
        XCTAssertEqual(Matcher.prefix(before: "open /Users/dan"), "dan")
        XCTAssertEqual(Matcher.prefix(before: "hello café"), "café")
        XCTAssertEqual(Matcher.prefix(before: "hello "), "")
    }
    func testPunctuationIsRemovedThroughoutSuggestions() {
        XCTAssertEqual(Matcher.candidates(lines: ["‘apple.’ apple! ap-ple app_le app…le"], prefix: "(app"), ["apple"])
        XCTAssertEqual(Matcher.candidates(lines: ["can't co-operate foo/bar"], prefix: ""), ["bar", "foo", "cant", "cooperate"])
        XCTAssertEqual(Matcher.candidates(lines: ["... — () !!!"], prefix: ""), [])
    }
    func testPunctuationIsIgnoredWhenInsertingSuffix() {
        XCTAssertEqual(Matcher.suffix(of: "‘ap-ple!’", after: "(app"), "le")
        XCTAssertEqual(Matcher.prefix(before: "say ‘ca-fé"), "café")
        XCTAssertEqual(Matcher.ignoringPunctuation("a，b。c—d…"), "abcd")
    }
    func testUniqueMatchIgnoresDuplicatesAndExistingWord() {
        XCTAssertEqual(Matcher.candidates(lines: ["app apple Apple", "apple"], prefix: "app"), ["apple"])
    }
    func testFilenameInsideScreenshotPathMatchesItsOwnPrefix() {
        let lines = ["Sources/Autocomplete/Picker.swift", "Sources/Autocomplete/TextTarget.swift", "Sources/Autocomplete/main.swift"]
        XCTAssertEqual(Matcher.candidates(lines: lines, prefix: "Text"), ["TextTargetswift"])
        XCTAssertEqual(Matcher.suffix(of: "TextTargetswift", after: "Text"), "Targetswift")
    }

    func testPathComponentsDeduplicateAndSupportBackslashes() {
        XCTAssertEqual(Matcher.candidates(lines: ["/Sources/TextTarget.swift", "Sources\\TextTarget.swift", "TextTarget.swift"], prefix: "text"), ["TextTargetswift"])
        XCTAssertEqual(Matcher.prefix(before: "open Sources/Autocomplete/Text"), "Text")
        XCTAssertEqual(Matcher.prefix(before: "open Sources\\Text"), "Text")
    }
    func testMultipleAndNoMatches() {
        XCTAssertEqual(Matcher.candidates(lines: ["apple application banana"], prefix: "app"), ["apple", "application"])
        XCTAssertEqual(Matcher.candidates(lines: ["banana"], prefix: "app"), [])
    }
    func testSuffixDoesNotRepeatTypedText() {
        XCTAssertEqual(Matcher.suffix(of: "Application", after: "app"), "lication")
        XCTAssertEqual(Matcher.suffix(of: "caféine", after: "café"), "ine")
    }
}
