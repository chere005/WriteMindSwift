import SwiftUI

/// The maths dropdown: type an expression — any formula or function, in
/// Wolfram Language — and see it set as you type, or pick a shape and fill
/// in its parts; either way what goes into the note is the WL underneath,
/// which is the canonical form (Sean, 2026-09-18).
///
/// Sean, 2026-10-03: "maths input should also just allow for an expression
/// so i could insert a function or something and it would appear like the
/// derivatives or integrals". The field is first and has the keyboard when
/// the palette opens; Return inserts, Escape cancels, an expression that
/// does not read says why under it and cannot be inserted. The shapes are
/// below it: each writes an expression into the same field. Everything that
/// can be decided lives in `MathPalette`.
struct MathMenu: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool

    @State private var palette = MathPalette()
    @FocusState private var typing: Bool
    /// The caret as the field last said it, with the text it said it for: a
    /// click on a shape may take the keyboard from the field, and the shape
    /// still goes in where the caret was.
    @State private var lastSelection: (text: String, range: NSRange)?

    private var expression: Binding<String> {
        Binding(get: { palette.expression }, set: { palette.type($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Maths").font(.headline)
                Spacer()
                Text("Wolfram Language").font(.caption).foregroundStyle(.secondary)
            }

            TextField("Expression — Sin[x]^2/(1+x), D[f[x], x], f[x_] := x^2", text: expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($typing)
                .autocorrectionDisabled()
                .onSubmit { insert() }
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.problem == nil ? Color.clear : Color.red, lineWidth: 1.5))

            preview

            Divider()

            // One pane with everything in it, scrolled — not a row of tabs
            // to go hunting through (Sean, 2026-09-18).
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 4)],
                          spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(MathTemplate.Group.allCases) { group in
                        Section {
                            ForEach(MathTemplate.group(group)) { template in
                                Button { pick(template) } label: {
                                    Text(template.glyph)
                                        .font(.system(size: 12, design: .serif))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                        .padding(.horizontal, 3)
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                        .background(palette.template?.id == template.id
                                                    ? Color.accentColor.opacity(0.25)
                                                    : Color.primary.opacity(0.06),
                                                    in: RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help(template.name)
                            }
                        } header: {
                            Text(group.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                                .background(.regularMaterial)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 150)

            if let template = palette.template, !template.slots.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(Array(template.slots.enumerated()), id: \.offset) { index, slot in
                        GridRow {
                            Text(slot.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            TextField(slot.initial, text: value(index))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .onSubmit { insert() }
                        }
                    }
                }
            }

            HStack {
                Toggle("On its own line", isOn: $palette.onItsOwnLine)
                    .toggleStyle(.checkbox)
                    .help("A ```wl block, set large. Off puts it inline in the sentence.")
                Spacer()
                Button("Insert") { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!palette.canInsert)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onExitCommand { isPresented = false }
        .onAppear {
            palette.start(seed: appState.editor.mathsSeed())
            // A turn later: the popover's window is not key yet, and focus
            // asked for in the same breath is not given.
            DispatchQueue.main.async { typing = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            if let editor = note.object as? NSTextView, editor.isFieldEditor, editor.string == palette.expression {
                lastSelection = (editor.string, editor.selectedRange())
            }
        }
    }

    /// A shape picked: it composes with what is in the field at the caret
    /// (`MathPalette.choose`), the keyboard goes back to the field and the
    /// caret to after what was written — so typing goes on.
    private func pick(_ shape: MathTemplate) {
        let text = palette.expression
        let live = MathFieldCaret.selection(holding: text, in: NSApp.keyWindow)
        let remembered = lastSelection.flatMap { $0.text == text ? $0.range : nil }
        palette.choose(shape, selection: live ?? remembered)
        typing = true
        if let caret = palette.caret { MathFieldCaret.settle(caret, holding: palette.expression) }
    }

    /// WHAT WILL BE INSERTED, set the way it will be set: two-dimensional on
    /// a line of its own, in the line of type when it goes in a sentence —
    /// or, when the expression does not read, why not.
    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                switch palette.reading {
                case .empty:
                    Text("Type an expression, or pick a shape below. It is set here as you type.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                case .maths(let canonical):
                    Group {
                        if palette.onItsOwnLine {
                            MathView(source: canonical, size: 22)
                        } else if let line = MathTypesetter.inline(canonical, size: 16) {
                            Text(line)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                case .broken(let error):
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))

            if let stored = palette.storedAs {
                Text("Stored as \(stored)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func value(_ index: Int) -> Binding<String> {
        Binding(
            get: { palette.values.indices.contains(index) ? palette.values[index] : "" },
            set: { palette.setValue($0, at: index) })
    }

    /// Return and the Insert button: the expression through `Insertion`,
    /// which is what puts it where the caret is. Never broken maths — the
    /// field already says why — and never twice for one press.
    private func insert() {
        guard isPresented else { return }
        guard case .maths(let wl, let display)? = palette.insertion else { NSSound.beep(); return }
        appState.editor.insertMath(wl, display: display)
        isPresented = false
    }
}
