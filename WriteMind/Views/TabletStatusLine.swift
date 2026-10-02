import Foundation

/// THE PANE'S ONE LINE ABOUT THE PEN, as words: pure, so every status is
/// known to have its line and each line is known to say the one useful
/// thing (`TabletPaneLineTests`).
///
/// Sean, 2026-10-02, with the pen dragging the pointer about under the old
/// line: "shouldn't WriteMind need some permissions like this?" — it does,
/// Input Monitoring, and when that is what stands between the pen and the
/// page the line says so and offers the way to it. Held, it says so
/// quietly. And when WriteMind cannot hold the tablet it says why the pen
/// moves the pointer too, with what macOS said, because the page still
/// writes and a pointer flying about with no reason given is the complaint
/// this line exists to answer.
extension TabletPane {
    /// System Settings › Privacy & Security › Input Monitoring.
    nonisolated static let inputMonitoringSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    struct StatusLine: Equatable {
        let icon: String
        let text: String
        /// Offer the way to Input Monitoring in System Settings — where the
        /// switch is, once WriteMind has asked and is listed there.
        var opensSettings = false
    }

    nonisolated static func line(for status: TabletController.Status, name: String) -> StatusLine? {
        let alsoPointer = "so the pen moves the pointer too"
        switch status {
        case .off, .unplugged:
            return nil
        case .standby:
            return StatusLine(icon: "pencil.tip", text: name)
        case .captured(let driverStillPosts):
            guard driverStillPosts else {
                return StatusLine(icon: "pencil.tip", text: "\(name) — pen captured")
            }
            return StatusLine(icon: "exclamationmark.triangle",
                              text: "WriteMind has the tablet, but the Wacom driver still hears it — the pointer may still move with the pen.")
        case .fallback(let refusal):
            switch refusal {
            case .undecided:
                return StatusLine(icon: "hand.raised",
                                  text: "Pick \(name) in Input Devices again and allow Input Monitoring — until then the pen moves the pointer too.",
                                  opensSettings: true)
            case .denied:
                return StatusLine(icon: "hand.raised",
                                  text: "WriteMind isn't allowed Input Monitoring, \(alsoPointer).",
                                  opensSettings: true)
            case .relaunch:
                return StatusLine(icon: "arrow.clockwise",
                                  text: "Input Monitoring is allowed — quit and reopen WriteMind to take the pen off the pointer.")
            case .driverHolds(let code):
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The Wacom driver won't let go of the tablet (\(TabletCapture.hex(code))), \(alsoPointer).")
            case .failed(let code):
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "macOS wouldn't open the tablet (\(TabletCapture.hex(code))), \(alsoPointer).")
            case .unreadable:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "WriteMind can't read what this tablet sends, \(alsoPointer).")
            case .noDevice:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "The tablet's pen wasn't there to take, \(alsoPointer).")
            case .underTest:
                return StatusLine(icon: "exclamationmark.triangle",
                                  text: "A test run does not open the tablet.")
            }
        }
    }
}
