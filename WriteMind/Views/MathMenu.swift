import SwiftUI

/// The maths dropdown: pick the shape, fill in its parts, see it set — and
/// what goes into the note is the Wolfram Language underneath, which is the
/// canonical form (Sean, 2026-09-18). The WL line is editable, so anything
/// the palette does not cover can simply be typed.
struct MathMenu: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool

    @State private var selected: MathTemplate = MathTemplate.all[0]
    @State private var values: [String] = MathTemplate.all[0].initialValues
    @State private var wl: String = ""
    @State private var onItsOwnLine = true
    /// The selection the palette was opened over, when it reads as maths.
    @State private var seed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Maths").font(.headline)
                Spacer()
                Text("Wolfram Language").font(.caption).foregroundStyle(.secondary)
            }

            // One pane with everything in it, scrolled — not a row of tabs
            // to go hunting through (Sean, 2026-09-18).
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 4)],
                          spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(MathTemplate.Group.allCases) { group in
                        Section {
                            ForEach(MathTemplate.group(group)) { template in
                                Button { choose(template) } label: {
                                    Text(template.glyph)
                                        .font(.system(size: 12, design: .serif))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                        .padding(.horizontal, 3)
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                        .background(selected.id == template.id
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
            .frame(height: 176)

            if !selected.slots.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(Array(selected.slots.enumerated()), id: \.offset) { index, slot in
                        GridRow {
                            Text(slot.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            TextField(slot.initial, text: value(index))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
            }

            TextField("Wolfram Language", text: $wl, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...3)

            MathView(source: wl, size: 22)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))

            HStack {
                Toggle("On its own line", isOn: $onItsOwnLine)
                    .toggleStyle(.checkbox)
                    .help("A ```wl block, set large. Off puts it inline in the sentence.")
                Spacer()
                Button("Insert") { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(wl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { start() }
    }

    private func value(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < values.count ? values[index] : "" },
            set: { typed in
                guard index < values.count else { return }
                values[index] = typed
                rebuild()
            })
    }

    private func choose(_ template: MathTemplate) {
        selected = template
        values = template.values(seed: seed)
        rebuild()
    }

    /// OPENED OVER A SELECTION THAT READS AS MATHS, the palette starts from
    /// it (Sean, 2026-10-02: "make math and code block insertion
    /// sensible.."): the WL is the selection, so Insert sets exactly what
    /// was selected, in the sentence when it sits in one; and a shape
    /// picked afterwards takes it into its first slot. It used to start
    /// from the first shape whatever was selected, and Insert replaced the
    /// selection with that.
    private func start() {
        guard let found = appState.editor.mathsSeed() else { return rebuild() }
        seed = found.wl
        onItsOwnLine = !found.inline
        values = selected.values(seed: found.wl)
        wl = found.wl
    }

    /// The fields drive the WL, until the WL itself is edited — then that is
    /// what gets inserted.
    private func rebuild() { wl = selected.wl(values) }

    private func insert() {
        appState.editor.insertMath(wl, display: onItsOwnLine)
        isPresented = false
    }
}
