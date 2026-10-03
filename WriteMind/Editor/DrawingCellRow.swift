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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DrawingCellFit(look: look) {
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(look.cell?.width ?? 0)
        let column = max(offered, 1)
        return CGSize(width: column, height: look.shown(column: column).size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}
