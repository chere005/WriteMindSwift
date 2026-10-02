import AppKit

// THE PAPERS THE PAGE CAN BE (Sean, 2026-10-02: "it can have themed
// backgrounds and different pen colors and strokes to write with").
//
// A paper is three things: the colour of the sheet, what is printed on it
// before anything is written, and an ink that reads on it. Whatever a paper
// prints it prints in TWO places — the pane (`TabletPaperLayer`) and a
// picture taken off the page (`TabletRender.image`) — and both ask `print`
// here, with the same page and the same millimetres, so a ruling is in
// both or in neither and lands in the same place in each.
//
// THE PRINT IS MEASURED IN THE TABLET'S OWN MILLIMETRES and laid down in
// FRACTIONS OF THE PAGE. Ruled paper is ruled 8 mm apart because a hand
// writes a line of letters that tall, and the page is the tablet: on the
// small One by Wacom (152 × 95 mm, 100 counts a millimetre) held turned, a
// ruling is 8/152 of the page's height, whatever size the pane shows it
// at — so the ruling under the nib is a ruling's height of the TABLET, and
// a bigger tablet gets more lines rather than fatter ones. The weights of
// the lines and the dots are millimetres too, so they grow and shrink with
// the sheet and come out the same in a picture of it. Text is never read
// off any of this: it is the ink alone, black on white
// (`TabletRender.ink`), whatever the paper.

/// The paper, saved WITH the page (`TabletSheet.theme`).
///
/// Stored by its raw value. One this build does not know — a paper added
/// later, opened in an older copy — opens as plain, and costs the page
/// nothing else (`TabletSheet.init(from:)`).
enum PageTheme: String, CaseIterable, Codable, Identifiable {
    case plain
    case dotGrid
    case ruled
    case graph
    case legal
    case blackboard

    var id: String { rawValue }

    /// What the menu calls it.
    var title: String {
        switch self {
        case .plain: return "Plain"
        case .dotGrid: return "Dot Grid"
        case .ruled: return "Ruled"
        case .graph: return "Graph"
        case .legal: return "Legal Pad"
        case .blackboard: return "Blackboard"
        }
    }

    /// One line under the name: what is printed, and how far apart.
    var detail: String {
        switch self {
        case .plain: return "White, nothing printed"
        case .dotGrid: return "Grey dots 5 mm apart"
        case .ruled: return "Blue lines 8 mm apart, a red margin"
        case .graph: return "5 mm squares"
        case .legal: return "Yellow, ruled 8 mm, a red margin"
        case .blackboard: return "Dark, for chalk"
        }
    }

    // MARK: - Colours

    /// The sheet, as six hex digits — explicit sRGB, never a dynamic
    /// colour: a picture of the page in Dark Mode is still the paper.
    var paperHex: String {
        switch self {
        case .plain, .dotGrid, .ruled, .graph: return "#FFFFFF"
        case .legal: return "#FBF2A0"
        // Deep green-black, the slate of a school board.
        case .blackboard: return "#1E2A24"
        }
    }

    var paper: NSColor { NSColor(hex: paperHex) ?? .white }

    /// The ink that reads on it — what the page's pen goes to when the
    /// paper changes under ink that would not (`readable`). Near-black
    /// on paper, the app's own darkest swatch; chalk on the board.
    var defaultInk: String {
        switch self {
        case .blackboard: return "#F1EFE6"
        default: return "#1C1C1E"
        }
    }

    /// A dark sheet, which needs an edge to be seen against the black pane.
    var isDark: Bool { Self.luminance(paperHex).map { $0 < 0.2 } ?? false }

    /// The colours the page's pen offers on this paper: the app's own six,
    /// and the paper's own ink when it is not one of them — chalk, on the
    /// board.
    var swatches: [String] {
        let presets = AppState.presetColors
        guard !presets.contains(where: { $0.caseInsensitiveCompare(defaultInk) == .orderedSame }) else { return presets }
        return presets + [defaultInk]
    }

    // MARK: - Reading on it

    /// Under this the ink is taken not to read: WCAG's contrast ratio,
    /// which runs from 1 (the paper itself) to 21 (black on white). Two is
    /// where it stops reading — the amber swatch on white is 1.8 and on the
    /// legal pad 1.6, black on the board 1.1 — while every other swatch
    /// still reads on every paper it is not the colour of (green on white
    /// is 2.4 and on the legal pad 2.1, purple on the board 2.5).
    static let readableContrast = 2.0

    /// This ink if it reads on this paper, and the paper's own if it does
    /// not — black on a blackboard is chalk, chalk on white paper is
    /// black. A colour that is not a colour reads as nothing.
    func readable(_ inkHex: String) -> String {
        guard let contrast = Self.contrast(inkHex, paperHex), contrast >= Self.readableContrast else { return defaultInk }
        return inkHex
    }

    /// WHEN THE PAPER CHANGES, INK THE CHANGE LEAVES UNREADABLE BECOMES THE
    /// PAPER'S OWN: ink this paper does not read, and reads WORSE than the
    /// paper it came off did. That is all the change answers for. A colour
    /// that read no worse on the paper before was picked on a paper just
    /// like this one, and stays — amber from plain to ruled is still amber,
    /// the board picked again leaves black on it black — while amber onto
    /// the yellow pad, black onto the board and chalk off it are changed.
    func ink(_ inkHex: String, after old: PageTheme) -> String {
        let here = readable(inkHex)
        guard here != inkHex,
              let now = Self.contrast(inkHex, paperHex), let before = Self.contrast(inkHex, old.paperHex),
              now >= before else { return here }
        return inkHex
    }

    /// WCAG 2's contrast ratio between two `#RRGGBB` colours, nil when
    /// either is not one.
    static func contrast(_ a: String, _ b: String) -> Double? {
        guard let x = luminance(a), let y = luminance(b) else { return nil }
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Relative luminance, sRGB.
    static func luminance(_ hex: String) -> Double? {
        guard let colour = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return nil }
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.redComponent) + 0.7152 * linear(colour.greenComponent)
            + 0.0722 * linear(colour.blueComponent)
    }

    // MARK: - The print

    /// A hand's line of writing: the ruling.
    static let ruling = 8.0
    /// The dot grid's pitch and the graph's square.
    static let grid = 5.0
    /// Ruled paper's first line and its margin are two rulings in.
    static let ruledInset = 2 * ruling

    /// What this paper prints on a page `millimetres` big (turned the way
    /// the page is), in PAGE FRACTIONS. Pure: the measurements are tested
    /// here, and both painters only scale them.
    func layout(millimetres: CGSize) -> PagePrint {
        let width = Double(millimetres.width), height = Double(millimetres.height)
        guard width > 0, height > 0 else { return PagePrint() }
        func across(_ mm: Double) -> CGFloat { CGFloat(mm / width) }
        func down(_ mm: Double) -> CGFloat { CGFloat(mm / height) }
        func row(_ mm: Double, _ hex: String, _ weight: Double) -> PagePrint.Rule {
            PagePrint.Rule(from: CGPoint(x: 0, y: down(mm)), to: CGPoint(x: 1, y: down(mm)), colorHex: hex, weight: weight)
        }
        func column(_ mm: Double, _ hex: String, _ weight: Double) -> PagePrint.Rule {
            PagePrint.Rule(from: CGPoint(x: across(mm), y: 0), to: CGPoint(x: across(mm), y: 1), colorHex: hex, weight: weight)
        }
        // Ruled lines from two rulings down to the last that leaves half a
        // ruling below it.
        func ruled(_ hex: String) -> [PagePrint.Rule] {
            stride(from: Self.ruledInset, through: height - Self.ruling / 2, by: Self.ruling).map { row($0, hex, 0.2) }
        }
        switch self {
        case .plain, .blackboard:
            return PagePrint()
        case .dotGrid:
            let xs = Self.lattice(length: width, spacing: Self.grid)
            let ys = Self.lattice(length: height, spacing: Self.grid)
            return PagePrint(dots: ys.flatMap { y in xs.map { x in CGPoint(x: across(x), y: down(y)) } },
                             dotHex: "#9A9A9A", dotDiameter: 0.5)
        case .graph:
            let colour = "#A9CBE8"
            return PagePrint(rules: Self.lattice(length: width, spacing: Self.grid).map { column($0, colour, 0.15) }
                                 + Self.lattice(length: height, spacing: Self.grid).map { row($0, colour, 0.15) })
        case .ruled:
            return PagePrint(rules: ruled("#9EC3E6") + [column(Self.ruledInset, "#E57373", 0.25)])
        case .legal:
            // A legal pad's margin is a DOUBLE red line.
            return PagePrint(rules: ruled("#8DB1D3")
                                 + [column(Self.ruledInset, "#D9534F", 0.2), column(Self.ruledInset + 1.2, "#D9534F", 0.2)])
        }
    }

    /// Evenly `spacing` apart along `length`, as many as fit, centred — so
    /// the paper left at the two ends is the same, and between half a
    /// spacing and a spacing.
    static func lattice(length: Double, spacing: Double) -> [Double] {
        guard length > 0, spacing > 0 else { return [] }
        let count = Int((length / spacing).rounded(.down))
        guard count > 0 else { return [] }
        let first = (length - Double(count - 1) * spacing) / 2
        return (0..<count).map { first + Double($0) * spacing }
    }

    /// Print the paper onto a y-down context in page points, the page
    /// `pageSize` points and `millimetres` big. THE ONE PRINTER, for the
    /// pane and for a picture of the page alike. `weight` thickens the
    /// lines and the dots and nothing else — 1 for the page; a swatch in
    /// the paper menu prints heavier, so a hairline still shows at the size
    /// of an icon.
    func print(in context: CGContext, pageSize: CGSize, millimetres: CGSize, weight: CGFloat = 1) {
        let print = layout(millimetres: millimetres)
        guard pageSize.width > 0, pageSize.height > 0, millimetres.height > 0 else { return }
        let perMillimetre = pageSize.height / millimetres.height
        context.saveGState()
        context.setLineCap(.butt)
        for rule in print.rules {
            context.setStrokeColor((NSColor(hex: rule.colorHex) ?? .gray).cgColor)
            context.setLineWidth(CGFloat(rule.weight) * perMillimetre * weight)
            context.move(to: CGPoint(x: rule.from.x * pageSize.width, y: rule.from.y * pageSize.height))
            context.addLine(to: CGPoint(x: rule.to.x * pageSize.width, y: rule.to.y * pageSize.height))
            context.strokePath()
        }
        if !print.dots.isEmpty {
            let radius = CGFloat(print.dotDiameter) * perMillimetre * weight / 2
            context.setFillColor((NSColor(hex: print.dotHex) ?? .gray).cgColor)
            for dot in print.dots {
                context.addEllipse(in: CGRect(x: dot.x * pageSize.width - radius, y: dot.y * pageSize.height - radius,
                                              width: 2 * radius, height: 2 * radius))
            }
            context.fillPath()
        }
        context.restoreGState()
    }
}

/// What a paper has printed on it, in PAGE FRACTIONS — 0…1 across and
/// down from the top left — with its weights in millimetres.
struct PagePrint: Equatable {
    struct Rule: Equatable {
        var from: CGPoint
        var to: CGPoint
        var colorHex: String
        /// How thick, in millimetres.
        var weight: Double
    }

    var rules: [Rule] = []
    var dots: [CGPoint] = []
    var dotHex = "#000000"
    /// Millimetres across.
    var dotDiameter = 0.0
}
