import XCTest
@testable import WriteMind

/// What ⌘9 makes (Sean, 2026-09-22: "default to wolfram" and "remember last
/// used cell type when inserting").
@MainActor
final class EvaluatorMemoryTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "WriteMindTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testANewEvaluationCellIsWolframUntilAnotherHasBeenPicked() {
        XCTAssertEqual(AppState(defaults: UserDefaults(suiteName: suite)!).evaluator, .wolfram)
    }

    func testTheLastEnvironmentPickedIsWhatTheNextCellIsAcrossLaunches() {
        let first = AppState(defaults: UserDefaults(suiteName: suite)!)
        first.evaluator = .python
        XCTAssertEqual(AppState(defaults: UserDefaults(suiteName: suite)!).evaluator, .python)
    }

    func testThePickOnABadgeIsWhatIsRemembered() throws {
        let source = try String(contentsOfFile: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "WriteMind/Views/EditorPane.swift").path, encoding: .utf8)
        XCTAssertTrue(source.contains("onPickEvaluator: { appState.evaluator = $0;"),
                      "choosing an environment on a cell's badge must be remembered for the next one")
    }
}
