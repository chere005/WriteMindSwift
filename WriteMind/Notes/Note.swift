import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    var modified: Date
    /// First `# heading` in the file, falling back to the file name.
    var title: String
    /// First couple of non-heading lines, for the sidebar row.
    var snippet: String

    var id: String { url.path }
    var filename: String { url.deletingPathExtension().lastPathComponent }

    static func make(url: URL, modified: Date, contents: String) -> Note {
        var title: String?
        var snippetLines: [String] = []

        for raw in contents.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // A drawing cell's line is a file's name, not words to show.
            if DrawingCells.parse(line) != nil { continue }
            if title == nil, line.hasPrefix("#") {
                title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                continue
            }
            if snippetLines.count < 2 { snippetLines.append(stripInlineMarkup(line)) }
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let resolved = (title?.isEmpty == false ? title! : stem)
        return Note(url: url,
                    modified: modified,
                    title: resolved,
                    snippet: snippetLines.joined(separator: " · "))
    }

    /// Plain text from a markdown line: drop the markers it carries.
    static func stripInlineMarkup(_ line: String) -> String {
        var out = line
        // A note's SECOND heading and below land in the snippet, so the
        // hashes have to come off here as well as in the title.
        if out.hasPrefix("#") {
            let hashes = out.prefix { $0 == "#" }
            if hashes.count <= 6 {
                out = String(out.dropFirst(hashes.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        for marker in ["**", "__", "<u>", "</u>", "`", "~~"] {
            out = out.replacingOccurrences(of: marker, with: "")
        }
        if out.hasPrefix("- ") || out.hasPrefix("* ") || out.hasPrefix("> ") { out.removeFirst(2) }
        return out
    }
}
