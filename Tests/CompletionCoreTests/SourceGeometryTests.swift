import XCTest
@testable import CompletionCore

final class SourceGeometryTests: XCTestCase {
    func testWordBoundsOnDisplayToLeftAndAboveMainDisplay() {
        let rect = SourceGeometry.screenRect(normalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), captureFrame: CGRect(x: -1000, y: -500, width: 1000, height: 800))
        XCTAssertEqual(rect, CGRect(x: -750, y: -300, width: 500, height: 200))
    }

    func testWordBoundsUseWindowOffsetAndPointsRatherThanPixels() {
        let rect = SourceGeometry.screenRect(normalized: CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25), captureFrame: CGRect(x: 100, y: 200, width: 800, height: 400))
        XCTAssertEqual(rect, CGRect(x: 100, y: 200, width: 400, height: 100))
    }

    func testTokenRangesPreserveOriginalUnicodeSourceOffsets() {
        let text = "👋 Sources/Autocomplete/‘TextTarget.swift’ café"
        let tokens = Matcher.tokenRanges(in: text)
        XCTAssertEqual(tokens.map { String(text[$0]) }, ["👋", "Sources", "Autocomplete", "‘TextTarget.swift’", "café"])
        XCTAssertEqual((text as NSString).substring(with: NSRange(tokens[3], in: text)), "‘TextTarget.swift’")
    }
}
