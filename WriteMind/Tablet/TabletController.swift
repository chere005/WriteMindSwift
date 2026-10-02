import AppKit
import Combine
import IOKit

/// A Wacom tablet plugged into this Mac, as the Input Devices menu lists it.
struct TabletDevice: Identifiable, Hashable {
    /// Stable across unplugging and plugging back in, so the pick can be
    /// remembered: the product and the serial, never the USB port.
    let id: String
    /// What the menu says: "One by Wacom (CTL-472)".
    let name: String
    /// The USB product string: "CTL-472".
    let model: String
    let productID: Int
    let serial: String?

    static let wacomVendorID = 0x056A

    init(model: String?, productID: Int, serial: String?) {
        let model = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serial = serial?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.productID = productID
        self.serial = (serial?.isEmpty ?? true) ? nil : serial
        name = Self.friendlyName(model: model, productID: productID)
        id = "wacom-" + String(format: "%04x", productID) + "-" + (self.serial ?? "")
    }

    /// The family a model belongs to, by the product string it reports —
    /// the box says "One by Wacom", the USB descriptor says "CTL-472".
    private static let families = ["CTL-472": "One by Wacom", "CTL-672": "One by Wacom"]
    /// The same, for a tablet that reports no product string at all.
    private static let models = [0x037A: "CTL-472", 0x037B: "CTL-672"]

    static func friendlyName(model: String, productID: Int) -> String {
        let model = model.isEmpty ? (models[productID] ?? "") : model
        if let family = families[model] { return "\(family) (\(model))" }
        if model.isEmpty { return "Wacom Tablet" }
        return model.localizedCaseInsensitiveContains("wacom") ? model : "Wacom \(model)"
    }
}

/// How WriteMind talks to the driver. One protocol so the controller's
/// rules — who may ask, when a context is made, kept and let go — can be
/// tested against a stand-in that answers like a driver, while the live
/// one does the real thing off the main thread.
protocol TabletDriverLink: AnyObject {
    var driverIsRunning: Bool { get }
    /// `WacomDriver.takeThePen`, answered on the main actor.
    func takeThePen(existing: UInt32?, ask: Bool, done: @escaping @MainActor (WacomDriver.Outcome) -> Void)
    /// Let a context go: waited for (in the background) or, on the way
    /// out of the app, posted and not waited for.
    func letGo(_ context: UInt32, wait: Bool)
}

/// The real driver, one conversation at a time on a queue of its own: an
/// Apple Event waits for its reply, and the Automation prompt waits for
/// Sean, and neither is allowed to stop the window.
final class LiveDriverLink: TabletDriverLink {
    private let queue = DispatchQueue(label: "com.seancheren.WriteMind.wacom")

    var driverIsRunning: Bool { WacomDriver.isRunning }

    func takeThePen(existing: UInt32?, ask: Bool, done: @escaping @MainActor (WacomDriver.Outcome) -> Void) {
        queue.async {
            let outcome = WacomDriver.takeThePen(existing: existing, ask: ask)
            Task { @MainActor in done(outcome) }
        }
    }

    func letGo(_ context: UInt32, wait: Bool) {
        if wait {
            queue.async { WacomDriver.letGo(context) }
        } else {
            WacomDriver.letGo(context, wait: false)
        }
    }
}

/// The Wacom tablets on this Mac, which one (if any) is the input, and
/// whether the driver has taken the pen off the pointer for it.
///
/// THE TABLET IS CHOSEN THE WAY A CAMERA IS (Sean, 2026-10-02: "wacom
/// should basically just be chosen as if it were an input display").
/// Modelled on `CameraController`: found by itself (IOKit's own notices for
/// a USB device from Wacom — the HID device is never opened, so there is no
/// Input Monitoring prompt), listed in the Input Devices menu, remembered
/// once picked, and A FIRST LAUNCH NEVER ASKS: nothing talks to the driver
/// until the tablet has been picked from a menu at least once, and the
/// Automation prompt only ever goes up as the direct result of that pick.
/// A launch that finds the remembered tablet takes the pen again without
/// asking anything.
///
/// While a tablet is the input AND ITS PAGE IS ON SCREEN there is a driver
/// CONTEXT with Mvsc false — the pen writes on the page and the pointer
/// stays where the trackpad left it. Put the pane away and the context goes
/// with it: a pen kept off the pointer for a page nobody can see writes
/// nowhere, and the notebook's own pen needs it as a pointer. Contexts only
/// act while WriteMind is in front, so it is checked again every time
/// WriteMind comes back to the front (kept if the driver still has it, made
/// again if not) and whenever the driver restarts; and it is let go when
/// the page goes, the tablet is turned off or unplugged, or the app quits.
@MainActor
final class TabletController: ObservableObject {
    enum Status: Equatable {
        /// No tablet is the input.
        case off
        /// The tablet that was picked is not plugged in.
        case unplugged
        /// Asking the driver — or waiting for Sean to answer macOS.
        case connecting
        /// The context stands: the pen is the page's and not the pointer's.
        case ready
        /// No context, and why. The page still takes the pen from whatever
        /// reaches WriteMind; the pointer moves with it.
        case unavailable(WacomDriver.Failure)
    }

    static let shared = TabletController()

    @Published private(set) var tablets: [TabletDevice] = []
    /// The pick, plugged in or not.
    @Published private(set) var selectedTabletID: String?
    /// What the pick is called, for a pane showing a tablet that is
    /// unplugged and so not in `tablets`.
    @Published private(set) var selectedName: String?
    @Published private(set) var status: Status = .off {
        didSet { if status != oldValue { log("tablet: \(Self.describe(oldValue)) -> \(Self.describe(status))") } }
    }

    var selectedTablet: TabletDevice? { tablets.first { $0.id == selectedTabletID } }
    var isSelected: Bool { selectedTabletID != nil }

    /// The funnel the pen's events come through.
    let input: TabletInput

    private let defaults: UserDefaults
    private let link: TabletDriverLink
    private var contextID: UInt32?
    /// One conversation at a time; a call that arrives during one is run
    /// once more afterwards — asking, if any of the calls asked.
    private var inFlight = false
    private var pendingAsk: Bool?
    private var byRegistryID: [UInt64: TabletDevice] = [:]
    /// Which tablet `input.extent` is the size of.
    private var extentTabletID: String?
    private var notifyPort: IONotificationPortRef?
    private var arrivals: io_iterator_t = 0
    private var departures: io_iterator_t = 0
    private var observers: [NSObjectProtocol] = []
    private var runningApplications: NSKeyValueObservation?
    var log: (String) -> Void = { line in if !TestHost.isActive { DebugLog.write(line) } }

    /// A just-plugged tablet is not the driver's straight away; asking at
    /// once found nothing to make a context over.
    nonisolated static let settle: TimeInterval = 1.5

    private enum Keys {
        static let lastTablet = "lastTabletID"
        static let lastTabletName = "lastTabletName"
    }

    /// `live` is everything that reaches outside the process — the USB
    /// notices, the app and workspace notifications, the remembered pick.
    /// None of it in the test host, which has no tablet and must never
    /// talk to the driver.
    init(defaults: UserDefaults = .standard, link: TabletDriverLink = LiveDriverLink(),
         input: TabletInput = .shared, live: Bool = !TestHost.isActive) {
        self.defaults = defaults
        self.link = link
        self.input = input
        // The page comes and goes on the main thread, from the pane.
        input.pageShowingChanged = { [weak self] showing in
            MainActor.assumeIsolated { self?.pageShowing(showing) }
        }
        guard live else { return }
        restoreRemembered()
        watchUSB()
        observeLifecycle()
    }

    // MARK: - Picking

    /// Sean picked `tablet` from a menu — Input Devices, or the pane's own.
    /// This is the ONE place the Automation prompt may come from. Picking
    /// the tablet that is already the input asks again, which is how a
    /// pick whose prompt never got answered is finished.
    func pick(_ tablet: TabletDevice) {
        select(tablet, ask: true)
    }

    /// No tablet: the pane goes back to the camera's.
    func turnOff() {
        guard selectedTabletID != nil else { return }
        selectedTabletID = nil
        selectedName = nil
        defaults.removeObject(forKey: Keys.lastTablet)
        defaults.removeObject(forKey: Keys.lastTabletName)
        pendingAsk = nil
        extentTabletID = nil
        letGoOfContext(wait: true)
        input.stop()
        status = .off
    }

    private func select(_ tablet: TabletDevice, ask: Bool) {
        if extentTabletID != tablet.id {
            // The table's size until the driver says otherwise.
            input.extent = TabletExtent.known(productID: tablet.productID) ?? .fallback
            extentTabletID = tablet.id
        }
        selectedTabletID = tablet.id
        selectedName = tablet.name
        defaults.set(tablet.id, forKey: Keys.lastTablet)
        defaults.set(tablet.name, forKey: Keys.lastTabletName)
        input.start()
        guard tablets.contains(tablet) else { status = .unplugged; return }
        connect(ask: ask)
    }

    /// The pick from the last session, if there was one: the pane shows the
    /// tablet (as unplugged until it is found), and nothing is asked.
    func restoreRemembered() {
        guard selectedTabletID == nil, let id = defaults.string(forKey: Keys.lastTablet) else { return }
        selectedTabletID = id
        selectedName = defaults.string(forKey: Keys.lastTabletName)
        input.start()
        if let tablet = tablets.first(where: { $0.id == id }) {
            select(tablet, ask: false)
        } else {
            status = .unplugged
        }
    }

    // MARK: - The driver

    /// Get (or keep) the context. `ask` only from `pick`.
    func connect(ask: Bool) {
        guard isSelected, selectedTablet != nil else { return }
        guard link.driverIsRunning else {
            contextID = nil
            status = .unavailable(.noDriver)
            return
        }
        // Said only when it is news: the app coming back to the front
        // re-checks a context that is almost always still there, and a
        // pane that blinked "connecting" every time would be noise. And
        // said BEFORE anything waits — a pick or a replug landing while an
        // earlier conversation is still out (the Automation prompt waits
        // for Sean) left the pane saying "No tablet selected", or
        // "unplugged", under a menu that ticked a tablet plugged in.
        switch status {
        case .off, .unplugged: status = .connecting
        case .unavailable where ask: status = .connecting
        default: break
        }
        // Only a page on screen wants the pen off the pointer. A pick puts
        // its question whether or not its page is up yet — the pane comes
        // up a moment after the menu, and the question is the pick's — and
        // what it makes waits for the page (`landed`).
        guard ask || input.pageIsShowing else { return }
        if inFlight {
            pendingAsk = (pendingAsk ?? false) || ask
            return
        }
        inFlight = true
        link.takeThePen(existing: contextID, ask: ask) { [weak self] outcome in
            self?.landed(outcome)
        }
    }

    private func landed(_ outcome: WacomDriver.Outcome) {
        inFlight = false
        // Turned off or unplugged while the driver was answering: a context
        // made for it is nobody's.
        guard isSelected, selectedTablet != nil else {
            if let made = outcome.context, made != contextID { link.letGo(made, wait: true) }
            return
        }
        if let old = contextID, let now = outcome.context, old != now { link.letGo(old, wait: true) }
        contextID = outcome.context
        if let made = outcome.context, outcome.created {
            log("tablet: context \(made) made on \(selectedName ?? "the tablet") — Mvsc false, the pen is off the pointer")
        }
        if let extent = outcome.extent {
            log("tablet: the driver measures \(outcome.name ?? "the tablet") at \(Int(extent.width)) x \(Int(extent.height))")
            // In counts; the table says how big that is in millimetres,
            // which is what the paper is ruled by.
            input.extent = extent.resolved(from: selectedTablet.flatMap { TabletExtent.known(productID: $0.productID) })
        }
        if let failure = outcome.failure {
            // Once per change: a refusal re-read every time the app comes
            // to the front is not news.
            if status != .unavailable(failure) {
                log("tablet: no context — \(failure)" + (failure.status.map { " (OSStatus \($0))" } ?? ""))
            }
            status = .unavailable(failure)
        } else {
            status = .ready
        }
        // The page went while the driver was answering, or a pick asked
        // before its page was up: the pen stays a pointer until it is.
        if !input.pageIsShowing { letGoOfContext(wait: true) }
        if let ask = pendingAsk {
            pendingAsk = nil
            connect(ask: ask)
        }
    }

    private func letGoOfContext(wait: Bool) {
        guard let id = contextID else { return }
        contextID = nil
        link.letGo(id, wait: wait)
        log("tablet: context \(id) let go")
    }

    /// The context's id, for the tests.
    var currentContext: UInt32? { contextID }

    // MARK: - What happens around it

    /// THE CONTEXT FOLLOWS THE PAGE. The first page on screen takes the pen
    /// off the pointer, asking nothing; the last one going gives it back —
    /// ⌘Y, the pane's switch, a camera picked. Left standing, it kept the
    /// pen off the pointer while WriteMind was in front with no page to
    /// write on: the notebook's own pen, the only other use of the pen
    /// here, was dead, and the line that would have said why was hidden
    /// with the pane.
    func pageShowing(_ showing: Bool) {
        if showing { connect(ask: false) } else { letGoOfContext(wait: true) }
    }

    /// Contexts only act while WriteMind is in front — check it is still
    /// there (the driver can drop one, or restart) each time it comes back.
    func appBecameActive() {
        guard isSelected, selectedTablet != nil else { return }
        connect(ask: false)
    }

    /// On the way out the context goes with us — Wacom's rule. Posted, not
    /// waited for: there is no time left to wait.
    func appWillQuit() {
        letGoOfContext(wait: false)
    }

    /// The driver came (back) up: its contexts died with the old one.
    func driverLaunched(settle: TimeInterval = TabletController.settle) {
        contextID = nil
        guard isSelected, selectedTablet != nil else { return }
        // Whether or not WriteMind is in front: a context only acts while
        // it is, and the next time it is, this one is already there.
        after(settle) { [weak self] in self?.connect(ask: false) }
    }

    /// The running list changed: did the driver come, or go? An insertion
    /// or a removal carries only what changed; a `.setting` carries both
    /// lists whole. Bundle ids, so a test can say them.
    func runningApplicationsChanged(kind: NSKeyValueChange, old: [String?], new: [String?],
                                    settle: TimeInterval = TabletController.settle) {
        let driver = WacomDriver.bundleIdentifier
        let was = old.contains(driver), now = new.contains(driver)
        let launched: Bool
        switch kind {
        case .insertion:
            guard now else { return }
            launched = true
        case .removal:
            guard was else { return }
            launched = false
        default:
            guard was != now else { return }
            launched = now
        }
        log("tablet: the Wacom driver \(launched ? "started" : "quit")")
        if launched { driverLaunched(settle: settle) } else { driverQuit() }
    }

    func driverQuit() {
        contextID = nil
        guard isSelected, selectedTablet != nil else { return }
        status = .unavailable(.noDriver)
    }

    /// A Wacom arrived on the USB bus.
    func plugged(_ tablet: TabletDevice, registryID: UInt64, settle: TimeInterval = TabletController.settle) {
        byRegistryID[registryID] = tablet
        list()
        guard tablet.id == selectedTabletID, status == .unplugged || status == .off else { return }
        // The pick is back: take the pen again, asking nothing.
        after(settle) { [weak self] in
            guard let self, self.selectedTabletID == tablet.id, self.tablets.contains(tablet) else { return }
            self.select(tablet, ask: false)
        }
    }

    /// A Wacom left the USB bus.
    func unplugged(registryID: UInt64) {
        guard let gone = byRegistryID.removeValue(forKey: registryID) else { return }
        list()
        guard gone.id == selectedTabletID, !tablets.contains(where: { $0.id == gone.id }) else { return }
        letGoOfContext(wait: true)
        status = .unplugged
    }

    private func list() {
        var seen = Set<String>()
        tablets = byRegistryID.values
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        guard delay > 0 else { work(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }

    private static func describe(_ status: Status) -> String {
        switch status {
        case .off: return "off"
        case .unplugged: return "unplugged"
        case .connecting: return "connecting"
        case .ready: return "ready"
        case .unavailable(let failure): return "unavailable(\(failure))"
        }
    }

    // MARK: - Live wiring

    private func observeLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        })
        // Synchronously, on the way out: a Task would run after the app had
        // gone.
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillQuit() }
        })
        // THE DRIVER IS A BACKGROUND APP — LSBackgroundOnly and LSUIElement
        // in its Info.plist — and NSWorkspace posts no didLaunch or
        // didTerminate for one: its documentation says so, and a probe
        // bundle with those two keys, launched and quit, raised neither
        // notice while the running list changed both times. Watched by the
        // notices, a driver restart was never seen — the dead context's id
        // kept, the pane still "ready", the pen moving the pointer. So it
        // is the running list that is watched.
        runningApplications = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let kind = change.kind
            let old = (change.oldValue ?? []).map(\.bundleIdentifier)
            let new = (change.newValue ?? []).map(\.bundleIdentifier)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.runningApplicationsChanged(kind: kind, old: old, new: new) }
            }
        }
    }

    /// IOKit's notices for USB devices from Wacom, first-match and
    /// terminated. Matching on the USB DEVICE, not the HID interface, and
    /// opening nothing: reading a registry entry's properties needs no
    /// permission at all.
    private func watchUSB() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            log("tablet: no IOKit notification port")
            return
        }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let me = Unmanaged.passUnretained(self).toOpaque()

        func matching() -> CFDictionary {
            let dictionary = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            dictionary["idVendor"] = TabletDevice.wacomVendorID
            return dictionary as CFDictionary
        }

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(), { refcon, iterator in
            guard let refcon else { return }
            let controller = Unmanaged<TabletController>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { controller.drainArrivals(iterator, settle: TabletController.settle) }
        }, me, &arrivals)
        // Draining arms the notice, and lists what is already plugged in —
        // at launch, with the driver long since up, there is nothing to
        // wait for.
        drainArrivals(arrivals, settle: 0)

        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(), { refcon, iterator in
            guard let refcon else { return }
            let controller = Unmanaged<TabletController>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { controller.drainDepartures(iterator) }
        }, me, &departures)
        drainDepartures(departures)
    }

    private func drainArrivals(_ iterator: io_iterator_t, settle: TimeInterval) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            let tablet = TabletDevice(
                model: Self.property(service, "USB Product Name") ?? Self.property(service, "kUSBProductString"),
                productID: (Self.property(service, "idProduct") as NSNumber?)?.intValue ?? 0,
                serial: Self.property(service, "USB Serial Number") ?? Self.property(service, "kUSBSerialNumberString"))
            log("tablet: plugged in — \(tablet.name), product 0x\(String(tablet.productID, radix: 16))")
            plugged(tablet, registryID: registryID, settle: settle)
        }
    }

    private func drainDepartures(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            if let gone = byRegistryID[registryID] { log("tablet: unplugged — \(gone.name)") }
            unplugged(registryID: registryID)
        }
    }

    private static func property<T>(_ service: io_service_t, _ key: String) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? T
    }
}

/// Picking an input is one gesture for both kinds — the menu bar's Input
/// Devices, and the picker in the pane — so it is said once, here.
@MainActor
enum InputDevices {
    /// The tablet: the camera goes off and the pane becomes the page.
    static func pick(_ tablet: TabletDevice, cameras: CameraController, tablets: TabletController) {
        cameras.turnOff()
        tablets.pick(tablet)
    }

    /// A camera: the pane goes back to video.
    static func pick(cameraID: String, cameras: CameraController, tablets: TabletController) {
        tablets.turnOff()
        cameras.select(deviceID: cameraID)
    }
}
