import AppKit
import XCTest
@testable import WriteMind

/// The tooltips the camera pane and the video panel got (Sean, 2026-09-19:
/// "the camera pane's own buttons never had the tooltip treatment the
/// editor's bar got").
///
/// The bar always has room under it and is as wide as the editor; a pane has
/// neither. The three buttons on a drawn box sit at the BOTTOM of the
/// picture when the box does, and the video panel is 244 points wide and
/// clips its own content — so the rule that decides where a bubble goes, and
/// how wide its detail line may be, is the whole of what is new here.
final class PaneTipTests: XCTestCase {
    private let pane = CGSize(width: 400, height: 600)
    private let bubble = CGSize(width: 200, height: 50)

    private func button(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 22, height: 22)
    }

    // MARK: - Below, unless there is no room

    func testABubbleHangsUnderItsButton() {
        let over = button(x: 100, y: 20)
        let centre = PaneTipPlacement.centre(over: over, bubble: bubble, within: pane)
        XCTAssertEqual(centre.y, over.maxY + PaneTipPlacement.gap + bubble.height / 2,
                       accuracy: 0.01, "the bar's placement, where there is room for it")
        XCTAssertEqual(centre.x, over.midX, accuracy: 0.01, "centred on the button")
    }

    func testAButtonAtTheBottomOfThePaneGetsItsBubbleAbove() {
        // The Image / Writing / Text row when the box is drawn low down.
        let over = button(x: 100, y: 560)
        let centre = PaneTipPlacement.centre(over: over, bubble: bubble, within: pane)
        XCTAssertEqual(centre.y, over.minY - PaneTipPlacement.gap - bubble.height / 2,
                       accuracy: 0.01, "no room below, so it flips above")
        XCTAssertGreaterThanOrEqual(centre.y - bubble.height / 2, PaneTipPlacement.margin,
                                    "and stays on the pane")
    }

    func testTheFlipOnlyHappensWhenItReallyHasTo() {
        // One point of room left below: it must NOT flip, or every tip near
        // the foot of the pane jumps about.
        let bottom = pane.height - PaneTipPlacement.margin - bubble.height - PaneTipPlacement.gap
        let over = button(x: 100, y: bottom - 22)
        let centre = PaneTipPlacement.centre(over: over, bubble: bubble, within: pane)
        XCTAssertEqual(centre.y, over.maxY + PaneTipPlacement.gap + bubble.height / 2, accuracy: 0.01)
    }

    func testWithRoomNowhereTheBubbleIsClampedOntoThePane() {
        // A pane shorter than the bubble: it cannot fit either way, so it is
        // pinned rather than drawn off the top.
        let short = CGSize(width: 400, height: 80)
        let tall = CGSize(width: 200, height: 60)
        let centre = PaneTipPlacement.centre(over: button(x: 100, y: 30), bubble: tall, within: short)
        XCTAssertGreaterThanOrEqual(centre.y, tall.height / 2 + PaneTipPlacement.margin - 0.01)
        XCTAssertLessThanOrEqual(centre.y, short.height - tall.height / 2 - PaneTipPlacement.margin + 0.01)
    }

    // MARK: - Sideways

    func testABubbleIsNudgedInAtEitherEdge() {
        let left = PaneTipPlacement.centre(over: button(x: 0, y: 20), bubble: bubble, within: pane)
        XCTAssertEqual(left.x, bubble.width / 2 + PaneTipPlacement.margin, accuracy: 0.01)

        let right = PaneTipPlacement.centre(over: button(x: pane.width - 22, y: 20),
                                            bubble: bubble, within: pane)
        XCTAssertEqual(right.x, pane.width - bubble.width / 2 - PaneTipPlacement.margin, accuracy: 0.01)
    }

    func testABubbleWiderThanThePaneIsPinnedLeftRatherThanThrownRight() {
        // The ranges cross over; taking the larger end would put the bubble
        // off the far side instead of the near one.
        let wide = CGSize(width: 300, height: 40)
        let panel = CGSize(width: 244, height: 300)
        let centre = PaneTipPlacement.centre(over: button(x: 200, y: 20), bubble: wide, within: panel)
        XCTAssertEqual(centre.x - wide.width / 2, PaneTipPlacement.margin, accuracy: 0.01,
                       "its left edge is on the margin; the overflow is to the right")
    }

    // MARK: - How wide the detail line may be

    func testANarrowPanelGetsANarrowerCapThanTheBar() {
        XCTAssertEqual(PaneTipPlacement.detailCap(within: CGSize(width: 800, height: 600)), 240,
                       "a wide pane keeps the bar's own cap")
        XCTAssertLessThan(PaneTipPlacement.detailCap(within: CGSize(width: 244, height: 300)), 240)
        XCTAssertEqual(PaneTipPlacement.detailCap(within: CGSize(width: 60, height: 300)), 120,
                       "never so narrow that the words stack one per line")
    }

    func testTheVideoPanelsOwnTipsFitInsideIt() {
        // The real strings, in the real 244pt panel.
        let panel = CGSize(width: 244, height: 300)
        let details = ["A quarter turn anticlockwise",
                       "The whole camera picture again, at the size it comes in",
                       "Drag a box on the picture and the pane shows just that much",
                       "Put the notes away and give the window to the video",
                       AppState.PaneWords.page.wholeWindowHelp, AppState.PaneWords.page.sideBySideHelp]
        for detail in details {
            let width = BarTipBubble.detailWidth(detail, cap: PaneTipPlacement.detailCap(within: panel))
            XCTAssertLessThanOrEqual(width + PaneTipPlacement.chrome,
                                     panel.width - 2 * PaneTipPlacement.margin,
                                     "\(detail) would be drawn out of the panel")
        }
    }

    func testTheLongestOfThemReallyWouldOverflowAtTheBarsCap() {
        // Guards the premise: with the bar's 240 these are wider than the
        // panel, which is why the cap has to come from the pane.
        let detail = "The whole camera picture again, at the size it comes in"
        XCTAssertGreaterThan(BarTipBubble.detailWidth(detail) + PaneTipPlacement.chrome,
                             244 - 2 * PaneTipPlacement.margin)
    }
}
