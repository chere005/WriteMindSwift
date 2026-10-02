import AppKit
import IOKit
import IOKit.hid

// WRITEMIND TAKES THE TABLET ITSELF.
//
// Sean, 2026-10-02, with the page up and the pointer flying round the
// other display under his pen: "how can i disable wacom from taking over my
// mouse?", "i did, it's still controlling my mouse", "shouldn't WriteMind
// need some permissions like this?", "fix the wacom not being captured by
// writemind properly issues".
//
// THE DRIVER CANNOT BE ASKED TO LET GO. Measured that day against driver
// 6.4.14-2 with probes of its Apple Event interface: it answers every READ
// ('WaWT': one tablet, Xdim 9499, Ydim 15199, "One by Wacom"; the pen's
// mapping, its mode, its orientation) and IGNORES EVERY WRITE — a context
// asked for five different ways came back an empty reply with no context
// afterwards, the pen's screen mapping set four ways read back unchanged,
// and the dictionary's own 'Core' class is errAEEventNotHandled (-1708).
// So there is no context and no Mvsc on this driver, and the port of
// Wacom's Driver Request Interface that used to live beside this file is
// gone with its Automation prompt. Nor does
// CGAssociateMouseAndMouseCursorPosition(0) hold the pointer: the driver
// posts absolute positions (493 pointer moves in 509 pen events).
//
// So while the pen has something of WriteMind's to write on, WriteMind
// opens the tablet's HID device with kIOHIDOptionsTypeSeizeDevice and reads
// the pen's raw reports itself. A seized device delivers nothing to the
// system or to any other client — the driver's IOHIDLibUserClient and
// WindowServer's event service are both clients of that one device (ioreg,
// same day) — so the driver goes quiet and the pointer stays where the
// trackpad left it. Closing the device gives the driver the pen back.
//
// NOTHING BUT THE APP ITSELF MAY OPEN THE TABLET — never a test, a script
// or a probe — so this was written without the seize ever having been run
// against it. What the tablet and the driver actually do is in
// /tmp/writemind-debug.log after the first sessions: each device's open
// with its IOReturn, the mode report, the first reports in hex. And every
// way it can go wrong ends in the fallback, with the pane saying why.
//
// Three parts, and only the last touches anything:
//   WacomPenPacket   one raw report read into what the pen is doing — pure
//   TabletCapture    when to ask, seize and release — a value, pure
//   TabletHID        the doors to macOS: Input Monitoring and the device.
//                    `LiveTabletHID` is the real one and REFUSES UNDER
//                    `TestHost`; the tests put a stand-in in its place.

/// One pen report from a One by Wacom. The layout is the Bamboo-pen class's,
/// as the Linux kernel driver reads it (drivers/hid/wacom_wac.c,
/// `wacom_bpt_pen` — the LAYOUT is taken from there, none of its code,
/// which is GPL):
///
///     byte 0     the report id, 2
///     byte 1     0x80 in range · 0x40 proximity: x and y are good ·
///                0x20 ready: the tip, the switches and the pressure are
///                good · 0x08 the eraser end · 0x04 the upper side switch ·
///                0x02 the lower side switch · 0x01 the tip
///     bytes 2–3  x, little-endian — RAW LANDSCAPE counts, origin top left
///     bytes 4–5  y, little-endian, increasing downward
///     bytes 6–7  pressure, little-endian, 0…2047
///     byte 8     distance from the surface
///     byte 9     nothing
///
/// The same frame `TabletMapping` already assumes, whichever way the
/// driver's own orientation setting is turned.
struct WacomPenPacket {
    static let reportID: UInt8 = 2
    static let length = 10
    static let fullPressure = 2047.0

    /// The pen is within reach of the tablet at all.
    let inRange: Bool
    /// Near enough that x and y mean something.
    let hasPosition: Bool
    /// The tip, the switches and the pressure mean something.
    let isReady: Bool
    let tip: Bool
    let lowerSwitch: Bool
    let upperSwitch: Bool
    let eraser: Bool
    let x: Int
    let y: Int
    /// 0…1.
    let pressure: Double
    let distance: Int

    /// Nil for anything that is not exactly this report: a short one, a
    /// long one (the tablet's second interface sends 64-byte reports under
    /// the same id), another id. NOTHING IS GUESSED — what is not known is
    /// written to the log in hex and left alone.
    init?(_ report: [UInt8]) {
        guard report.count == Self.length, report[0] == Self.reportID else { return nil }
        let flags = report[1]
        inRange = flags & 0x80 != 0
        hasPosition = flags & 0x40 != 0
        isReady = flags & 0x20 != 0
        tip = flags & 0x01 != 0
        lowerSwitch = flags & 0x02 != 0
        upperSwitch = flags & 0x04 != 0
        eraser = flags & 0x08 != 0
        x = Int(report[2]) | Int(report[3]) << 8
        y = Int(report[4]) | Int(report[5]) << 8
        let raw = Double(Int(report[6]) | Int(report[7]) << 8)
        pressure = min(raw / Self.fullPressure, 1)
        distance = Int(report[8])
    }

    /// What this report says about the pen, in the funnel's own words — the
    /// same `TabletReading` an NSEvent is read into, so the pen's state, the
    /// turn and the page are one path for both routes.
    ///
    /// Out of range is the pen leaving. In range without a position is the
    /// pen coming near: nothing to put a marker on yet, and (0, 0) is not
    /// where it is. With a position it is a point, and the tip, the
    /// switches and the pressure count only once the tablet says they are
    /// ready — until then the reading says the nib is up and that it CANNOT
    /// SAY what the switches are doing (nil), which is not "let go": read as
    /// that, an unready report at the edge of the tablet's reach could make
    /// a click of a switch still held. A precaution — how the LP-190K's
    /// reports end there is unmeasured. EACH SWITCH IS ITS OWN
    /// (`PenSwitch`): 0x02 the lower one, nearer the nib — the Linux
    /// driver's BTN_STYLUS — and 0x04 the upper.
    func reading(at timestamp: TimeInterval) -> TabletReading {
        guard inRange else {
            return TabletReading(kind: .proximity(entering: false), timestamp: timestamp, native: true)
        }
        guard hasPosition else {
            return TabletReading(kind: .proximity(entering: true), timestamp: timestamp, native: true)
        }
        let down = isReady && tip
        var buttons: UInt = 0
        var switches: Set<PenSwitch>?
        if isReady {
            switches = []
            if tip { buttons |= 0x1 }
            if lowerSwitch {
                buttons |= 0x2
                switches?.insert(.lower)
            }
            if upperSwitch {
                buttons |= 0x4
                switches?.insert(.upper)
            }
        }
        return TabletReading(kind: .point(counts: CGPoint(x: x, y: y), tip: down, switches: switches,
                                          pressure: down ? pressure : 0, buttons: buttons),
                             timestamp: timestamp, native: true)
    }

    /// A report as the log writes it.
    static func hex(_ report: [UInt8]) -> String {
        report.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

/// WHEN WRITEMIND HOLDS THE TABLET — a value, so a test can walk it through
/// anything.
///
/// It holds it only while all three are true: a tablet is the chosen input
/// and plugged in, what the pen writes on is on screen (its page, or in
/// Notebook mode a note), and WriteMind is the active app. Any one of them
/// going gives the tablet back — a pen held off the pointer for a page
/// nobody can see writes nowhere, and a pen held while another app is in
/// front is a dead pen there.
///
/// Opening a pointer-class HID device needs Input Monitoring, and A FIRST
/// LAUNCH NEVER ASKS: the answer is only ever READ here, except as the
/// direct result of Sean picking the tablet from a menu (`picked`), which is
/// the one thing that may put macOS's question up. And nothing is opened
/// until the answer reads granted — IOKit's own open would ask on its own
/// otherwise.
struct TabletCapture {
    /// Input Monitoring, as macOS has it down for WriteMind.
    enum Access: Equatable {
        case granted, denied
        /// Nobody has answered — or nobody has been asked.
        case undecided
    }

    /// Why WriteMind does not have the tablet, and the pen is still the
    /// driver's — which moves the pointer with it.
    enum Refusal: Equatable {
        /// Input Monitoring has never been answered. Only a pick asks.
        case undecided
        /// Input Monitoring is switched off for WriteMind.
        case denied
        /// It reads granted, and the open was still refused
        /// (kIOReturnNotPermitted): macOS gives a running app its new
        /// permission only once it has been quit and opened again.
        case relaunch
        /// Somebody else has seized it (kIOReturnExclusiveAccess).
        case driverHolds(IOReturn)
        /// Anything else, as the IOReturn it came back as.
        case failed(IOReturn)
        /// No HID device of the tablet's was there to open.
        case noDevice
        /// It was held, it sent reports, and none of them was a pen report
        /// this build can read. Held on like that the pen would write
        /// nothing at all, so it is given back — until it is picked again.
        case unreadable
        /// This process is the test host or the smoke, which never open a
        /// device.
        case underTest

        /// For the log line: what IOKit actually said.
        var code: IOReturn? {
            switch self {
            case .relaunch: return TabletCapture.notPermitted
            case .driverHolds(let code), .failed(let code): return code
            case .undecided, .denied, .noDevice, .unreadable, .underTest: return nil
            }
        }
    }

    /// kIOReturnNotPermitted and kIOReturnExclusiveAccess, spelled out: the
    /// log and the pane say them in hex, and these are what to look for.
    static let notPermitted = IOReturn(bitPattern: 0xE000_02E2)
    static let exclusiveAccess = IOReturn(bitPattern: 0xE000_02C5)

    /// How many reports in a row, inside how long, with not one of them the
    /// pen's, say the tablet cannot be read: a quarter of a second of the
    /// pen's own traffic (about 133 a second), which no status report or
    /// second interface comes near.
    static let unreadableBurst = 32
    static let unreadableWithin: TimeInterval = 1

    static func hex(_ code: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: code))
    }

    /// One HID device of the tablet's, and what opening it came back with.
    struct Opened {
        let usagePage: Int
        let usage: Int
        let status: IOReturn
        /// Generic Desktop: the mouse the pen is to macOS. THE DEVICE THAT
        /// MOVES THE POINTER is the one that has to be held.
        var movesPointer: Bool { usagePage == 0x01 }
    }

    /// Whether what was opened is the tablet taken — nil — or why not. The
    /// pointer's device must have opened; an interface beside it that would
    /// not (the One by Wacom has a second, vendor-defined, that nobody
    /// reads) is the log's business and not a failure. A tablet with no
    /// pointer device at all is held only if everything it has opened.
    static func verdict(of opened: [Opened]) -> Refusal? {
        let pointers = opened.filter(\.movesPointer)
        let needed = pointers.isEmpty ? opened : pointers
        guard !needed.isEmpty else { return .noDevice }
        guard let failed = needed.first(where: { $0.status != kIOReturnSuccess }) else { return nil }
        switch failed.status {
        case notPermitted: return .relaunch
        case exclusiveAccess: return .driverHolds(failed.status)
        default: return .failed(failed.status)
        }
    }

    /// What decides it, as the controller sees it at any moment.
    struct Conditions {
        /// The picked tablet's USB product, while it is plugged in.
        var productID: Int?
        /// What the pen writes on is on screen.
        var targetShowing = false
        /// WriteMind is the active app.
        var active = false

        var wanted: Bool { productID != nil && targetShowing && active }
    }

    /// What the shell is to do about it, in order.
    enum Command: Equatable {
        /// Put macOS's Input Monitoring question up.
        case ask
        /// Open the tablet's HID devices, seizing them. `attempt` comes
        /// back with the answer, so one that lands late is known for it.
        case seize(productID: Int, attempt: Int)
        /// Close them: the driver has the pen again.
        case release
    }

    enum Holding: Equatable {
        case nothing
        /// The question is up, or on its way.
        case asking
        /// The open is under way.
        case seizing
        case captured
    }

    private(set) var holding = Holding.nothing
    /// Why not, the last time it was tried or read — gone the moment the
    /// tablet is taken.
    private(set) var refusal: Refusal?
    private(set) var attempt = 0
    private var conditions = Conditions()
    /// Which tablet the open under way, or the hold, is of.
    private var seizedProductID: Int?
    /// A pen report has been read in this capture; and, until one has, the
    /// run of reports that were not (`reported`).
    private var penRead = false
    private var burstSince: TimeInterval?
    private var burst = 0

    var isCaptured: Bool { holding == .captured }

    /// Something changed — the pick, the plug, the target, the app coming
    /// to the front or leaving it — or `picked`: Sean has just chosen the
    /// tablet from a menu. `access` is Input Monitoring as it READS now.
    ///
    /// A refused open is tried again at the next change, never on its own:
    /// the driver may have let go, a relaunch may have happened, and one
    /// more open per coming-to-the-front costs nothing. (Not so a tablet
    /// that opened and could not be READ — below.)
    mutating func changed(_ conditions: Conditions, access: Access, picked: Bool = false) -> [Command] {
        self.conditions = conditions
        guard let productID = conditions.productID else {
            refusal = nil
            return letGo()
        }
        switch access {
        case .denied:
            refusal = .denied
            return letGo()
        case .undecided:
            if holding == .asking { return [] }
            guard picked else {
                refusal = .undecided
                return letGo()
            }
            let release = letGo()
            holding = .asking
            return release + [.ask]
        case .granted:
            if refusal == .denied || refusal == .undecided { refusal = nil }
            guard conditions.wanted else { return letGo() }
            if holding == .captured || holding == .seizing {
                // THE HOLD FOLLOWS THE PICK: with two tablets plugged in,
                // the other one picked is the other one taken. Left as it
                // was, the first stayed seized and went on writing under
                // "pen captured", and the one ticked in the menu was a dead
                // pen on the page — its driver's events ignored for the
                // raw reports of a tablet nobody was holding the pen over.
                guard productID != seizedProductID else { return [] }
                return letGo() + seize(productID)
            }
            // A tablet that could not be read is not taken again for the
            // same dead pen at every coming-to-the-front: a pick tries it.
            if refusal == .unreadable, !picked { return [] }
            return seize(productID)
        }
    }

    /// macOS's question was answered — or put away unanswered.
    mutating func answered(_ access: Access) -> [Command] {
        guard holding == .asking else { return [] }
        holding = .nothing
        switch access {
        case .granted:
            refusal = nil
            guard conditions.wanted, let productID = conditions.productID else { return [] }
            return seize(productID)
        case .denied:
            refusal = .denied
        case .undecided:
            refusal = .undecided
        }
        return []
    }

    /// The open came back: taken (nil), or why not. One that lands after
    /// the tablet was let go of — or after a newer open was started — is
    /// nobody's: the release that followed it down the same queue closes
    /// whatever it opened.
    mutating func landed(attempt: Int, refusal: Refusal?) {
        guard attempt == self.attempt, holding == .seizing else { return }
        holding = refusal == nil ? .captured : .nothing
        self.refusal = refusal
    }

    /// One report came off the held tablet: the pen's (`known`), or not.
    ///
    /// A SEIZED TABLET WHOSE REPORTS CANNOT BE READ IS A DEAD PEN — the
    /// driver hears nothing, and neither does the page. So a burst of
    /// reports at the pen's rate with not one of them the pen's, before the
    /// pen has been read once in this capture, gives the tablet back and
    /// says so; the page writes again from the driver's events. (The layout
    /// was taken from the Linux driver and never seen from this tablet
    /// before the first session — this is what a wrong layout costs.)
    mutating func reported(known: Bool, at time: TimeInterval) -> [Command] {
        guard holding == .captured, !penRead else { return [] }
        guard !known else {
            penRead = true
            return []
        }
        if let since = burstSince, time - since <= Self.unreadableWithin {
            burst += 1
        } else {
            burstSince = time
            burst = 1
        }
        guard burst >= Self.unreadableBurst else { return [] }
        holding = .nothing
        refusal = .unreadable
        return [.release]
    }

    private mutating func seize(_ productID: Int) -> [Command] {
        attempt += 1
        penRead = false
        burstSince = nil
        burst = 0
        holding = .seizing
        seizedProductID = productID
        return [.seize(productID: productID, attempt: attempt)]
    }

    private mutating func letGo() -> [Command] {
        let held = holding == .captured || holding == .seizing
        holding = .nothing
        return held ? [.release] : []
    }
}

/// The doors to macOS that capture goes through. `LiveTabletHID` is the
/// real one; a test's stand-in answers like macOS and opens nothing.
/// Everything is called from the main thread and answered there.
protocol TabletHID: AnyObject {
    /// Input Monitoring, READ. Never a prompt.
    func access() -> TabletCapture.Access
    /// ASK macOS for Input Monitoring — a prompt, the first time, and
    /// WriteMind listed in System Settings from then on.
    func requestAccess(done: @escaping (TabletCapture.Access) -> Void)
    /// Open every HID device of this tablet's, seizing it. `done` with nil
    /// once the pen is WriteMind's — its reports then come to `report`,
    /// each with the uptime it arrived at — or with why not, and then
    /// nothing is left open.
    func seize(vendorID: Int, productID: Int,
               report: @escaping ([UInt8], TimeInterval) -> Void,
               done: @escaping (TabletCapture.Refusal?) -> Void)
    /// Close whatever is open. `waiting` on the way out of the app, when
    /// there is no later to do it in.
    func release(waiting: Bool)
}

/// The real doors: IOKit's HID devices, on a queue of its own.
///
/// EVERY DOOR REFUSES UNDER `TestHost` ON ITS FIRST LINE — the test host is
/// the app, and from it an ask would put macOS's prompt in front of Sean and
/// an open would take his tablet out from under his hand. `check`, `ask`
/// and `find` are the three places IOKit is first touched, and they are
/// replaceable only so a test can stand spies there and prove the guard
/// holds (`LiveTabletHIDTests`).
///
/// The devices are the registry's IOHIDDevice entries with the tablet's
/// vendor and product — the matching IOHIDManager itself builds — each
/// opened on its own so that each says how its own open went (the manager's
/// open gives one answer for them all). The One by Wacom has two: the
/// pointer's (usage page 1, usage 2 — the one the driver and WindowServer
/// read, and the one that carries the pen) and a vendor-defined one beside
/// it that nobody reads.
///
/// Opening, the mode report and closing all run on `queue`, off the main
/// thread — a control request to a device that has stopped answering waits
/// out the USB stack's timeout, and that must not be the window's wait. The
/// reports themselves are scheduled on the MAIN run loop, in the common
/// modes, so they arrive where the funnel lives, in order, with a menu or a
/// drag under way or not.
final class LiveTabletHID: TabletHID {
    var check: () -> IOHIDAccessType = { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) }
    var ask: () -> Bool = { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    var find: (Int, Int) -> [IOHIDDevice] = LiveTabletHID.devices
    var log: (String) -> Void = { DebugLog.write($0) }

    private let queue = DispatchQueue(label: "com.seancheren.WriteMind.tablet-hid")

    /// One device held open. Touched only on `queue` — and let go of for
    /// the last time on the main thread (`close`).
    private final class Held {
        let device: IOHIDDevice
        let movesPointer: Bool
        let buffer: UnsafeMutablePointer<UInt8>
        let size: Int
        /// The mode the tablet was in before this took it, when that was
        /// not the pen's: put back on the way out.
        var modeBefore: UInt8?

        init(device: IOHIDDevice, movesPointer: Bool, size: Int) {
            self.device = device
            self.movesPointer = movesPointer
            self.size = size
            buffer = .allocate(capacity: size)
        }
    }
    private var held: [Held] = []
    /// Where the reports go. Main thread only.
    private var sink: (([UInt8], TimeInterval) -> Void)?

    func access() -> TabletCapture.Access {
        guard !TestHost.isActive else { return .undecided }
        switch check() {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undecided
        }
    }

    func requestAccess(done: @escaping (TabletCapture.Access) -> Void) {
        guard !TestHost.isActive else { done(.undecided); return }
        // Off the main thread, and off `queue`: macOS may hold this call
        // until its prompt is answered, and nothing else waits behind it.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let granted = ask()
            DispatchQueue.main.async { [self] in
                let access = granted ? .granted : access()
                log("tablet: Input Monitoring asked for — \(access)")
                done(access)
            }
        }
    }

    func seize(vendorID: Int, productID: Int,
               report: @escaping ([UInt8], TimeInterval) -> Void,
               done: @escaping (TabletCapture.Refusal?) -> Void) {
        guard !TestHost.isActive else { done(.underTest); return }
        sink = report
        queue.async { [self] in
            let refusal = open(vendorID: vendorID, productID: productID)
            DispatchQueue.main.async { done(refusal) }
        }
    }

    func release(waiting: Bool) {
        guard !TestHost.isActive else { return }
        sink = nil
        guard waiting else {
            queue.async { [self] in close() }
            return
        }
        // Quitting: closed before the process goes, so a mode this set is
        // put back — but never waited on for longer than a quit can spare.
        // (The kernel closes a dead process's devices by itself.)
        let closed = DispatchSemaphore(value: 0)
        queue.async { [self] in
            close()
            closed.signal()
        }
        _ = closed.wait(timeout: .now() + 0.5)
    }

    // MARK: - On the queue

    /// The feature report that says which mode the tablet is in, and the
    /// pen's mode. (Linux, wacom_sys.c: the Bamboo-pen class's
    /// `mode_report` and `mode_value` are both 2.)
    private static let modeReport: UInt8 = 2
    private static let penMode: UInt8 = 2

    private func open(vendorID: Int, productID: Int) -> TabletCapture.Refusal? {
        close()
        var opened: [TabletCapture.Opened] = []
        for device in find(vendorID, productID) {
            let one = TabletCapture.Opened(usagePage: Self.number(device, kIOHIDPrimaryUsagePageKey),
                                           usage: Self.number(device, kIOHIDPrimaryUsageKey),
                                           status: IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)))
            say("tablet: HID device usage page 0x\(String(one.usagePage, radix: 16)) usage "
                + "0x\(String(one.usage, radix: 16)) opened to seize — \(TabletCapture.hex(one.status))")
            opened.append(one)
            if one.status == kIOReturnSuccess {
                held.append(Held(device: device, movesPointer: one.movesPointer,
                                 size: max(Self.number(device, kIOHIDMaxInputReportSizeKey), 64)))
            } else if one.status == TabletCapture.exclusiveAccess {
                // A device somebody else has seized still counts as open
                // to IOKit — its reports dropped — and has to be closed.
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            }
        }
        if let refusal = TabletCapture.verdict(of: opened) {
            close()
            return refusal
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        for one in held {
            if one.movesPointer { enterPenMode(one) }
            IOHIDDeviceRegisterInputReportCallback(one.device, one.buffer, one.size, { context, _, _, _, _, report, length in
                guard let context, length > 0 else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                Unmanaged<LiveTabletHID>.fromOpaque(context).takeUnretainedValue()
                    .sink?(bytes, ProcessInfo.processInfo.systemUptime)
            }, me)
            IOHIDDeviceScheduleWithRunLoop(one.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        return nil
    }

    /// WITH NO DRIVER RUNNING the tablet enumerates as a plain relative
    /// mouse and sends no pen reports until it is told to; the driver, when
    /// there is one, has told it long since. So the mode is READ first and
    /// set only if it is not already the pen's — a tablet the driver has
    /// set up is sent nothing — and whatever it was is put back on closing,
    /// or a Mac with no driver would be left with a tablet that is no
    /// longer its mouse.
    private func enterPenMode(_ one: Held) {
        var now = [UInt8](repeating: 0, count: 2)
        var length = CFIndex(now.count)
        let read = IOHIDDeviceGetReport(one.device, kIOHIDReportTypeFeature, CFIndex(Self.modeReport), &now, &length)
        let was: UInt8? = read == kIOReturnSuccess && length >= 2 ? now[1] : nil
        guard was != Self.penMode else {
            say("tablet: mode report reads \(Self.penMode) — already the pen's, nothing sent")
            return
        }
        let wanted = [Self.modeReport, Self.penMode]
        let set = IOHIDDeviceSetReport(one.device, kIOHIDReportTypeFeature, CFIndex(Self.modeReport),
                                       wanted, wanted.count)
        say("tablet: mode report read \(TabletCapture.hex(read)) "
            + (was.map { "as \($0)" } ?? "with no mode in it")
            + " — set to \(Self.penMode): \(TabletCapture.hex(set))")
        if set == kIOReturnSuccess { one.modeBefore = was }
    }

    private func close() {
        for one in held {
            if let before = one.modeBefore {
                let back = [Self.modeReport, before]
                let set = IOHIDDeviceSetReport(one.device, kIOHIDReportTypeFeature, CFIndex(Self.modeReport),
                                               back, back.count)
                say("tablet: mode put back to \(before): \(TabletCapture.hex(set))")
            }
            let status = IOHIDDeviceClose(one.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            IOHIDDeviceUnscheduleFromRunLoop(one.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            say("tablet: HID device closed — \(TabletCapture.hex(status))")
        }
        // WHAT IS CLOSED DIES ON THE MAIN THREAD, AFTER ITS LAST REPORT.
        // Neither the close nor the unscheduling waits for a report already
        // on its way up the main run loop, and IOKit hands those up in a
        // loop that holds the device by a bare pointer and copies each one
        // into its buffer (IOHIDLib's `valueAvailableCallback`, into
        // IOKitUser's `__IOHIDDeviceInputReportCallback`) — at the pen's 133
        // a second there is usually one. So the buffer is freed THERE,
        // behind whatever was in flight, and the device's last reference
        // is not dropped before that has run: dropped here, the loop's
        // next turn was in freed memory.
        //
        // The callback is not taken off first, because it cannot be
        // counted on: IOKit keeps callbacks in a set hashed on callback
        // and context together and compared by context alone, so
        // "register nil" finds its entry only by the luck of the hash.
        // `sink` going nil on the main thread is what stops the reports
        // (`release`).
        let closed = held
        held = []
        DispatchQueue.main.async {
            for one in closed { one.buffer.deallocate() }
        }
    }

    /// The log is the main thread's; the queue's lines join it in order.
    private func say(_ line: String) {
        DispatchQueue.main.async { [self] in log(line) }
    }

    /// Every HID device the tablet has, the pointer's first. Reading the
    /// registry and making the device objects opens nothing and asks
    /// nothing.
    private static func devices(vendorID: Int, productID: Int) -> [IOHIDDevice] {
        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = vendorID
        matching[kIOHIDProductIDKey] = productID
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [IOHIDDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { found.append(device) }
        }
        return found.sorted { number($0, kIOHIDPrimaryUsagePageKey) < number($1, kIOHIDPrimaryUsagePageKey) }
    }

    private static func number(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
}
