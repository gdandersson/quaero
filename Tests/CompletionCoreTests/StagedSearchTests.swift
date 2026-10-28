import XCTest
@testable import CompletionCore

final class StagedSearchTests: XCTestCase {
    func testCurrentWordDoesNotStopSearchBeforeWiderMatches() async throws {
        let result = try await StagedSearch.candidates(prefix: "", excluding: "multi", stages: [
            { ["multi"] }, { ["MULTI!"] }, { ["multi multiple"] }
        ])
        XCTAssertEqual(result, ["multiple"])
    }
    func testStopsAtFirstMatchingScope() async throws {
        for hit in 0..<4 {
            var visited: [Int] = []
            let stages: [() async throws -> [String]] = (0..<4).map { index in
                { visited.append(index); return index == hit ? ["apple application"] : ["banana"] }
            }
            let result = try await StagedSearch.candidates(prefix: "app", stages: stages)
            XCTAssertEqual(result, ["apple", "application"])
            XCTAssertEqual(visited, Array(0...hit))
        }
    }

    func testSingleMatchDoesNotVisitWiderScopes() async throws {
        var visitedWiderScope = false
        let result = try await StagedSearch.candidates(prefix: "app", stages: [
            { ["apple Apple app"] },
            { visitedWiderScope = true; return ["application"] }
        ])
        XCTAssertEqual(result, ["apple"])
        XCTAssertFalse(visitedWiderScope)
    }

    func testFallsThroughNonmatchingTextAndEmptyStages() async throws {
        let result = try await StagedSearch.candidates(prefix: "app", stages: [
            { ["banana"] }, { [] }, { ["app"] }, { ["apple"] }
        ])
        XCTAssertEqual(result, ["apple"])
    }

    func testFailedWindowCanFallBackToDisplay() async throws {
        struct CaptureError: Error {}
        let result = try await StagedSearch.candidates(prefix: "app", stages: [
            { throw CaptureError() }, { ["apple"] }
        ])
        XCTAssertEqual(result, ["apple"])
    }

    func testNoMatchesAcrossAnyScope() async throws {
        let result = try await StagedSearch.candidates(prefix: "app", stages: [{ [] }, { ["banana"] }])
        XCTAssertEqual(result, [])
    }
}
