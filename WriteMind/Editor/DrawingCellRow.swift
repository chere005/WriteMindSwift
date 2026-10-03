import SwiftUI

/// A DRAWING CELL ON THE RENDERED PAGE: as wide as the column it is offered
/// and as tall as the cell is shown in that column (`DrawingCellLook.shown`),
/// painted by the one painter (`DrawingCellPainter`), with the pane's
/// hairline round it — lit with the accent while it is the cursor. Its
/// objects are drawn here and nowhere else on this page; what is being done
/// to them (a stroke under way, a selection's outline) is the drawing
/// layer's, over it.
struct DrawingCellRow: View {
    let look: DrawingCellLook
    let media: URL?
    var lit = false
    /// THE COLUMN IT IS SHOWN IN, the page's, decided by the page from its
    /// window: not what the row is offered. The scroll view offers 17
    /// points less while a legacy scroller shows, the scroller shows when
    /// the page is taller than its window, and a cell is taller the wider
    /// the column — a cell that filled the window to within a few points had
    /// the row measured 62 and then 59.7 and then 62 for ever, and the main
    /// thread never came back (found docking a stroke into one, 2026-10-02).
    /// Shown at the page's column it hangs into the right margin by a
    /// scroller's width at worst, and nothing feeds back.
    var column: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DrawingCellFit(look: look, column: column) {
            Canvas { context, size in
                let paper = DrawingCellPainter.Paper.screen(hex: InkPaths.notePaperHex(dark: colorScheme == .dark))
                context.withCGContext { cg in
                    DrawingCellPainter.paint(look, in: cg, at: .zero, column: size.width, paper: paper, media: media)
                }
                let shown = look.shown(column: size.width).size
                let width: CGFloat = lit ? 1.5 : 0.5
                context.stroke(Path(CGRect(origin: .zero, size: shown).insetBy(dx: width / 2, dy: width / 2)),
                               with: lit ? .color(.accentColor) : .style(.tertiary), lineWidth: width)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(look.why ?? "Drawing")
    }
}

/// As wide as it is offered and as tall as the cell is shown at that width:
/// a cell shrinks whole in a narrower column, so its height is the
/// column's to decide, and the row's height is what the page stacks by.
private struct DrawingCellFit: Layout {
    let look: DrawingCellLook
    /// The page's column, when it says (`DrawingCellRow.column`).
    let column: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = column > 0 ? column
            : (proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(look.cell?.width ?? 0))
        let width = max(offered, 1)
        return CGSize(width: width, height: look.shown(column: width).size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}
