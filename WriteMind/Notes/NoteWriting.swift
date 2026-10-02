import Foundation

/// Whether it is safe to write the open note back to its file.
///
/// A note lost two cells on 2026-09-20 while `tools/deploy.sh` ran with the
/// app still open on it: the deploy smoke-launches a second copy of the
/// bundle, so two instances had the same file open, and `saveNow()` wrote
/// whatever it was holding over whatever was there. Nothing in the app
/// looked at the file before overwriting it, so the newer of the two
/// writers was whichever happened to save last — and what came out was
/// neither of them.
///
/// The rule is the one every editor has to have: the app owns the file only
/// as long as it is the last thing that wrote to it. If the bytes on disk
/// are not the bytes it last read or last wrote, somebody else has been
/// here — another instance, another editor, a script — and the buffer in
/// memory is no longer an edit OF that file. It is not written.
///
/// Refusing loses nothing: the text stays in the buffer, the session caches
/// it, and the folder watcher brings the newer file in. Writing loses the
/// other writer's work, silently, which is what happened.
enum NoteWriting {
    /// `onDisk` is what the file holds now (nil when it cannot be read),
    /// `known` what this app last read from it or wrote to it (nil before
    /// it has ever seen the file).
    static func mayWrite(onDisk: String?, known: String?) -> Bool { owns(onDisk, known) }

    /// The same rule for a file that is not a note — the tablet's page,
    /// read as bytes (`TabletPage`).
    static func mayWrite(dataOnDisk: Data?, known: Data?) -> Bool { owns(dataOnDisk, known) }

    private static func owns<Contents: Equatable>(_ onDisk: Contents?, _ known: Contents?) -> Bool {
        switch (onDisk, known) {
        // A file that is not there yet, and we never saw one: a new note
        // saving itself for the first time.
        case (nil, nil): return true
        // It was there and now it is not — a trash, or a move. Writing
        // would put it back, and the sidebar's gesture is what decides
        // that, not an autosave.
        case (nil, _): return false
        // We have never read it but there is something there: whatever it
        // is, it is not ours to overwrite.
        case (_, nil): return false
        case (let disk?, let known?): return disk == known
        }
    }
}
