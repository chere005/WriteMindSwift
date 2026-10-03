import XCTest
@testable import WriteMind

/// FIT OR REAL SIZE for the tablet over the notes (Sean, 2026-10-02: "Make
/// sure in wacom over the wysiwyg editor that there's a toggle from scaling
/// to real drawing size or the mapping to the entire visible screen").
/// Fit — the default and what it always was — maps the whole tablet onto the
/// visible notes; Real size makes a millimetre on the tablet a millimetre of
/// the screen, the tablet's area centred on the notes and clipped by the
/// pane when it is bigger, never shrunk.
final class NotebookScaleTests: XCTestCase {
    /// The One by Wacom's active area held a quarter turn: 95 × 152 mm.
    private let portraitMM = CGSize(width: 95, height: 152)
    private var aspect: CGFloat { portraitMM.width / portraitMM.height }
    private let perMM = TabletMapping.pointsPerMillimetre

    private func place(_ pane: CGSize, scale: NotebookScale, scroll: CGFloat = 0,
                       mm: CGSize? = nil) -> NotebookPlace {
        NotebookPlace(pane: pane, scroll: scroll, aspect: aspect, scale: scale, millimetres: mm ?? portraitMM)
    }

    func testAMillimetreIsAPointAndAFractionOfAnInch() {
        XCTAssertEqual(perMM, 72 / 25.4, accuracy: 1e-9, "a point is 1/72 inch, an inch 25.4 mm")
    }

    func testFitIsWhatItAlwaysWasAndTheDefault() {
        let pane = CGSize(width: 800, height: 900)
        XCTAssertEqual(NotebookScale.fit, .fit)
        XCTAssertEqual(place(pane, scale: .fit).area, TabletMapping.fit(aspect: aspect, in: pane, margin: NotebookPlace.margin))
        XCTAssertEqual(NotebookPlace(pane: pane, scroll: 0, aspect: aspect).area,
                       place(pane, scale: .fit).area, "no scale given is fit")
    }

    func testRealSizeIsMillimetresOnTheScreenCentredOnTheNotes() {
        let pane = CGSize(width: 800, height: 900)
        let area = place(pane, scale: .real).area
        XCTAssertEqual(area.width, 95 * perMM, accuracy: 0.001)
        XCTAssertEqual(area.height, 152 * perMM, accuracy: 0.001)
        XCTAssertEqual(area.midX, pane.width / 2, accuracy: 0.001)
        XCTAssertEqual(area.midY, pane.height / 2, accuracy: 0.001)
    }

    /// Clipped, not shrunk: a pane smaller than the tablet shows part of it.
    func testRealSizeIsNotShrunkToAPaneTooSmallForIt() {
        let pane = CGSize(width: 200, height: 300)
        let area = place(pane, scale: .real).area
        XCTAssertEqual(area.width, 95 * perMM, accuracy: 0.001)
        XCTAssertEqual(area.height, 152 * perMM, accuracy: 0.001)
        XCTAssertGreaterThan(area.width, pane.width, "wider than the pane, and left so")
        XCTAssertEqual(area.midX, pane.width / 2, accuracy: 0.001)
    }

    func testThePageMapsOntoTheRealAreaCornerToCorner() {
        let pane = CGSize(width: 800, height: 900)
        let real = place(pane, scale: .real)
        let area = real.area
        XCTAssertEqual(real.onPane(CGPoint(x: 0, y: 0)), area.origin)
        XCTAssertEqual(real.onPane(CGPoint(x: 1, y: 1)).x, area.maxX, accuracy: 0.001)
        XCTAssertEqual(real.onPane(CGPoint(x: 0.5, y: 0.5)).y, pane.height / 2, accuracy: 0.001)
        // A centimetre across the tablet is a centimetre across the screen.
        let across = real.onPane(CGPoint(x: 10 / 95.0, y: 0)).x - real.onPane(.zero).x
        XCTAssertEqual(across, 10 * perMM, accuracy: 0.001)
    }

    /// Off the notes is off: the pen past the edge writes along the edge.
    func testThePartOfARealSizeTabletOffTheNotesWritesAlongTheEdge() {
        let pane = CGSize(width: 200, height: 300)
        let real = place(pane, scale: .real)
        XCTAssertLessThan(real.area.minX, 0)
        XCTAssertEqual(real.onPane(CGPoint(x: 0, y: 0)), .zero)
        XCTAssertEqual(real.onPane(CGPoint(x: 1, y: 1)), CGPoint(x: pane.width, y: pane.height))
        let middle = real.onPane(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(middle.x, 100, accuracy: 0.001)
        XCTAssertEqual(middle.y, 150, accuracy: 0.001)
    }

    func testAScrolledNoteStillPutsTheAreaOnTheVisibleNotes() {
        let pane = CGSize(width: 800, height: 900)
        let real = place(pane, scale: .real, scroll: 400)
        XCTAssertEqual(real.inDocument(CGPoint(x: 0.5, y: 0.5)).y, pane.height / 2 + 400, accuracy: 0.001)
    }

    func testAnUnmeasuredTabletFallsBackToFit() {
        let pane = CGSize(width: 800, height: 900)
        XCTAssertEqual(place(pane, scale: .real, mm: .zero).area, place(pane, scale: .fit).area)
    }

    func testRealSizeDoesNotChangeWhetherThereAreNotesToWriteOn() {
        XCTAssertTrue(place(.zero, scale: .real).isEmpty)
        XCTAssertFalse(place(CGSize(width: 800, height: 600), scale: .real).isEmpty)
    }

    // MARK: - Remembered

    @MainActor
    func testTheChoiceIsRememberedBetweenLaunches() {
        let suite = "WriteMindTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = AppState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(first.notebookScale, .fit)
        first.notebookScale = .real
        XCTAssertEqual(AppState(defaults: UserDefaults(suiteName: suite)!).notebookScale, .real)
    }

    func testEachScaleHasItsWords() {
        XCTAssertEqual(NotebookScale.allCases.map(\.title), ["Fit", "Real size"])
        for scale in NotebookScale.allCases {
            XCTAssertFalse(scale.icon.isEmpty)
            XCTAssertFalse(scale.help.isEmpty)
        }
    }
}
