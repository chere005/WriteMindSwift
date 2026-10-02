import SwiftUI

// HOW THE TABLET SITS ON THE DESK, BY NAME (Sean, 2026-10-02: "make sure i
// can orient the page with the device by rotating or flipping to make it
// match portrait or landscape").
//
// The four ways Wacom's own driver names — landscape, portrait, landscape
// flipped, portrait flipped, "flipped" being turned half way round, for the
// other hand — said here as what you would do to the tablet on the desk.
// Each is a number of quarter turns clockwise from the landscape it ships
// in, and that number is the one thing stored (`AppState.tabletQuarterTurns`):
// the one control for it, in the page's corner (`TabletOrientationButton`),
// writes it, and nothing else here keeps a copy.

enum TabletOrientation: Int, CaseIterable, Identifiable {
    /// As it ships: wide, its own top edge at the top.
    case landscape = 0
    /// A quarter turn clockwise — its top edge on the right. THE DEFAULT
    /// (Sean, 2026-10-02: "i want to rotate the wacom 90 degrees clockwise
    /// for when its in use in WriteMind").
    case portraitRight = 1
    /// Turned half way round: wide again, its top edge at the bottom —
    /// Wacom's "landscape flipped".
    case landscapeUpsideDown = 2
    /// A quarter turn anticlockwise — its top edge on the left; Wacom's
    /// "portrait flipped", the other portrait.
    case portraitLeft = 3

    var id: Int { rawValue }

    /// Whatever number of turns, as one of the four.
    init(quarterTurns: Int) {
        self = Self(rawValue: TabletMapping.turns(quarterTurns)) ?? .portraitRight
    }

    var quarterTurns: Int { rawValue }

    /// Taller than it is wide.
    var isPortrait: Bool { rawValue % 2 == 1 }

    /// What the menu and the tip call it.
    var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portraitRight: return "Portrait — turned right"
        case .landscapeUpsideDown: return "Landscape — upside down"
        case .portraitLeft: return "Portrait — turned left"
        }
    }

    /// One line under the name: what was done to the tablet.
    var detail: String {
        switch self {
        case .landscape: return "As it ships"
        case .portraitRight: return "A quarter turn clockwise"
        case .landscapeUpsideDown: return "Turned half way round, for the other hand"
        case .portraitLeft: return "A quarter turn anticlockwise, for the other hand"
        }
    }

    /// WHERE THE TABLET'S OWN TOP EDGE IS, on the page turned this way —
    /// what the glyph marks, so the glyph is the tablet as it lies on the
    /// desk. It is the funnel's own mapping asked about the edge at y = 0
    /// (`TabletMapping.page`), and a test holds it to that.
    var topEdge: Edge {
        switch self {
        case .landscape: return .top
        case .portraitRight: return .trailing
        case .landscapeUpsideDown: return .bottom
        case .portraitLeft: return .leading
        }
    }
}

/// THE TABLET AS IT LIES ON THE DESK: its outline in this orientation's
/// shape, the edge that is its top as it ships drawn heavy — so the four are
/// four different pictures, the heavy edge going round a side a quarter
/// turn, and the one in the corner says at a glance how the tablet is meant
/// to sit. SwiftUI shapes, never an NSView: it is over the tablet's pane
/// (AGENTS.md, the eighth cause).
struct TabletGlyph: View {
    let orientation: TabletOrientation
    /// The tablet's long side, in points.
    var size: CGFloat = 16

    /// The small One by Wacom's short side over its long (95 / 152 mm).
    static let shape: CGFloat = 0.625

    var body: some View {
        let long = size, short = (size * Self.shape).rounded()
        let width = orientation.isPortrait ? short : long
        let height = orientation.isPortrait ? long : short
        let line = max(size / 12, 1.1)
        RoundedRectangle(cornerRadius: max(size / 8, 1.5))
            .strokeBorder(lineWidth: line)
            .frame(width: width, height: height)
            .overlay(alignment: Alignment(orientation.topEdge)) {
                // On the edge, over the outline: the top edge, heavier.
                let along = (orientation.isPortrait ? height : width) * 0.6
                let across = line * 2.4
                Capsule()
                    .frame(width: orientation.isPortrait ? across : along,
                           height: orientation.isPortrait ? along : across)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension Alignment {
    init(_ edge: Edge) {
        switch edge {
        case .top: self = .top
        case .bottom: self = .bottom
        case .leading: self = .leading
        case .trailing: self = .trailing
        }
    }
}
