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
//
// AND THE PICTURE OF IT SHOWS THE TABLET'S LIGHT (Sean, 2026-10-02: "make
// the tablet orientation icon show the led on the tablet for the icon to
// give orientation"). The first glyph marked the tablet's top edge with a
// heavy line — a mark the real tablet does not have, so it told him
// nothing. The light is on the thing in front of him: find it on the desk,
// find it in the picture, and the two lie the same way.

enum TabletOrientation: Int, CaseIterable, Identifiable {
    /// As it ships: wide, its light on the left.
    case landscape = 0
    /// A quarter turn clockwise — its light at the top. THE DEFAULT
    /// (Sean, 2026-10-02: "i want to rotate the wacom 90 degrees clockwise
    /// for when its in use in WriteMind").
    case portraitRight = 1
    /// Turned half way round: wide again, its light on the right —
    /// Wacom's "landscape flipped".
    case landscapeUpsideDown = 2
    /// A quarter turn anticlockwise — its light at the bottom; Wacom's
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

    /// What was done to the tablet.
    private var turned: String {
        switch self {
        case .landscape: return "As it ships"
        case .portraitRight: return "A quarter turn clockwise"
        case .landscapeUpsideDown: return "Turned half way round, for the other hand"
        case .portraitLeft: return "A quarter turn anticlockwise, for the other hand"
        }
    }

    /// One line under the name: what was done to the tablet, and where
    /// that leaves its light — the thing to look for on the desk. The
    /// light's words are held together and to the dot before them
    /// (no-break spaces): a row that has to wrap broke as "light at / the
    /// top", and then left the dot hanging at the end of the line above.
    var detail: String {
        turned + " · light \(lightPlace)".replacingOccurrences(of: " ", with: "\u{A0}")
    }

    // MARK: - The light

    /// THE TABLET'S STATUS LIGHT, ON THE TABLET AS IT SHIPS — the one fact
    /// every picture and every word about the light comes from. Wacom's own
    /// product photo of the small One by Wacom (CTL-472) lying landscape,
    /// the frame the pen's raw counts have their origin top left in: the
    /// LED is a small dot just inside the LEFT edge, half way down. (Its
    /// fabric tag is on the right edge above the middle, and the cable
    /// leaves the top.) A fraction of the tablet, raw landscape.
    static let led = CGPoint(x: 0, y: 0.5)

    /// WHERE THE LIGHT IS on the tablet turned this way, as a fraction of
    /// it, origin top left: `led` carried through the very quarter turns
    /// the pen's counts go through (`TabletMapping.page`) — never a second
    /// table of four, which could drift from the one the pen writes by.
    var ledPoint: CGPoint {
        TabletMapping.page(Self.led, extent: TabletExtent(width: 1, height: 1), quarterTurns: quarterTurns)
    }

    /// The edge the light is on: the one `ledPoint` is nearest.
    var ledEdge: Edge {
        let at = ledPoint
        let across: (edge: Edge, away: CGFloat) = at.x <= 1 - at.x ? (.leading, at.x) : (.trailing, 1 - at.x)
        let down: (edge: Edge, away: CGFloat) = at.y <= 1 - at.y ? (.top, at.y) : (.bottom, 1 - at.y)
        return across.away <= down.away ? across.edge : down.edge
    }

    /// That edge in words, for a row, the tip and the popover's last line.
    var lightPlace: String {
        switch ledEdge {
        case .leading: return "on the left"
        case .top: return "at the top"
        case .trailing: return "on the right"
        case .bottom: return "at the bottom"
        }
    }
}

/// THE TABLET AS IT LIES ON THE DESK, ITS LIGHT WHERE THE LIGHT REALLY IS
/// (Sean, 2026-10-02: "make the tablet orientation icon show the led on the
/// tablet for the icon to give orientation"): its outline in this
/// orientation's shape, and a small lit dot just inside the edge the LED is
/// on, half way along it — so the four are four different pictures, the
/// light going round a side a quarter turn, and the one in the corner is
/// matched to the tablet by looking at the tablet. Nothing else is marked:
/// the heavy "top edge" the first glyph drew is on no tablet. SwiftUI
/// shapes, never an NSView: it is over the tablet's pane (AGENTS.md, the
/// eighth cause).
struct TabletGlyph: View {
    let orientation: TabletOrientation
    /// The tablet's long side, in points.
    var size: CGFloat = 16
    /// Drawn on the corner's glass, over the pane's black — a ground the
    /// appearance does not say (`lightHex`).
    var onPane = false
    @Environment(\.colorScheme) private var colorScheme

    /// The small One by Wacom's short side over its long (95 / 152 mm).
    nonisolated static let shape: CGFloat = 0.625

    /// The outline's weight.
    nonisolated static func line(size: CGFloat) -> CGFloat { max(size / 12, 1.1) }

    /// The tablet's outline in the glyph's own square of `size`, centred.
    nonisolated static func outline(_ orientation: TabletOrientation, size: CGFloat) -> CGRect {
        let long = size, short = (size * shape).rounded()
        let width = orientation.isPortrait ? short : long
        let height = orientation.isPortrait ? long : short
        return CGRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
    }

    /// THE LIGHT'S DOT in that square: `ledPoint` laid on the outline and
    /// brought just inside it — clear of the line by a hair, so it is a
    /// dot ON the tablet and not a bump in its edge. Far bigger than the
    /// real one against the real tablet: at 14 points it has to be seen.
    nonisolated static func light(_ orientation: TabletOrientation, size: CGFloat) -> CGRect {
        let across = max(size / 4.5, 3)
        let inset = line(size: size) + size / 24 + across / 2
        let outline = outline(orientation, size: size)
        let at = orientation.ledPoint
        let centre = CGPoint(x: outline.minX + inset + at.x * (outline.width - 2 * inset),
                             y: outline.minY + inset + at.y * (outline.height - 2 * inset))
        return CGRect(x: centre.x - across / 2, y: centre.y - across / 2, width: across, height: across)
    }

    /// LIT, SO IT IS A LIGHT AND NOT A HOLE: the outline takes whatever
    /// colour the control is drawn in, and the dot never does — a blue
    /// white on a dark ground, a full blue on a light one, where a pale
    /// dot would be the paper showing through. BY THE GROUND, WHICH THE
    /// APPEARANCE ALONE DOES NOT SAY: a popover is dark or light with it,
    /// but the corner's glass lies over the pane's black and is a dark
    /// ground in both — as the window server composites it (a probe
    /// window, 2026-10-02) #202423 in dark and #6E706F in light, where
    /// the full blue was 1.25 to 1 against it, a light told from the
    /// glass by its hue alone. Explicit sRGB.
    nonisolated static func lightHex(onPane: Bool, dark: Bool) -> String {
        onPane || dark ? "#A8DCFF" : "#0A7AFF"
    }

    var body: some View {
        let outline = Self.outline(orientation, size: size)
        let light = Self.light(orientation, size: size)
        let lit = Color(hex: Self.lightHex(onPane: onPane, dark: colorScheme == .dark)) ?? .accentColor
        ZStack {
            RoundedRectangle(cornerRadius: max(size / 8, 1.5))
                .strokeBorder(lineWidth: Self.line(size: size))
                .frame(width: outline.width, height: outline.height)
                .position(x: outline.midX, y: outline.midY)
            // The real one glows.
            Circle()
                .fill(lit)
                .frame(width: light.width, height: light.height)
                .shadow(color: lit.opacity(0.85), radius: light.width * 0.45)
                .position(x: light.midX, y: light.midY)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
