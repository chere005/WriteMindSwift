import SwiftUI

// THE PEN'S CONTROLS, ONE OF EACH, for both pens: the notebook's (`PenMenu`,
// under the pen on the editor's bar) and the page's (`TabletPenMenu`, off
// the bar in the tablet page's corner). Two pens with two sets of controls
// drawn twice would be two answers to "what does a size of 5 look like".

/// The tools, a button each, its icon over its name (Sean, 2026-10-02:
/// "different pen colors and strokes to write with"). The one picked is
/// lit; its tooltip says what it writes like.
struct InkToolPicker: View {
    @Binding var tool: InkTool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InkTool.allCases, id: \.self) { candidate in
                let picked = candidate == tool
                Button { tool = candidate } label: {
                    VStack(spacing: 3) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 15))
                            .frame(height: 18)
                        Text(candidate.shortTitle)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(picked ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(picked ? Color.accentColor : Color.clear, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(candidate.title) — \(candidate.help)")
                .accessibilityLabel(candidate.title)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
    }
}

/// Wide enough for "Colour" on one line: at 36 it broke after the u.
private let labelWidth: CGFloat = 46

/// The size: a slider, and a dot of the ink that size beside it.
struct PenSizeRow: View {
    @Binding var width: Double
    let colour: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("Size").lineLimit(1).frame(width: labelWidth, alignment: .leading)
            Slider(value: $width, in: 1...24, step: 1)
            ZStack {
                Circle()
                    .fill(colour)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .frame(width: width, height: width)
            }
            .frame(width: 28, height: 28)
            Text("\(Int(width))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
    }
}

/// The colour: the round colour well, then the swatches, the one in use
/// ringed. Every swatch has a hairline edge, so chalk shows on a light
/// popover. THE RING IS OUTSIDE THE SWATCH, a gap away, on the popover's
/// own ground: drawn on the swatch it was primary on primary's colour —
/// black on the black swatch, the page pen's first ink, and white on
/// chalk in Dark Mode — and the menu opened with nothing ringed.
struct PenColourRow: View {
    @Binding var hex: String
    var swatches: [String] = AppState.presetColors

    var body: some View {
        HStack(spacing: swatches.count > 6 ? 8 : 10) {
            Text("Colour").lineLimit(1).frame(width: labelWidth, alignment: .leading)
            ColorPicker("Pen colour", selection: Binding(get: { Color(hex: hex) ?? .black },
                                                         set: { hex = $0.hexString }),
                        supportsOpacity: false)
                .labelsHidden()
            ForEach(swatches, id: \.self) { swatch in
                Button {
                    hex = swatch
                } label: {
                    Circle()
                        .fill(Color(hex: swatch) ?? .clear)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .background(
                            Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                                .frame(width: 27, height: 27)
                                .opacity(swatch.caseInsensitiveCompare(hex) == .orderedSame ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
