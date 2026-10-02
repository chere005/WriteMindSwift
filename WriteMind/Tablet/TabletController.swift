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

/// The Wacom tablets on this Mac, which one (if any) is the input, and
/// whether WriteMind has taken its pen off the pointer.
///
/// THE TABLET IS CHOSEN THE WAY A CAMERA IS (Sean, 2026-10-02: "wacom
/// should basically just be chosen as if it were an input display").
/// Modelled on `CameraController`: found by itself (IOKit's own notices for
/// a USB device from Wacom — reading the registry opens nothing and asks
/// nothing), listed in the Input Devices menu, remembered once picked, and
/// A FIRST LAUNCH NEVER ASKS: nothing about the tablet's HID device is read
/// or opened until a tablet is the input, and macOS's Input Monitoring
/// question only ever goes up as the direct result of a pick. A launch that
/// finds the remembered tablet takes the pen again if it is already
/// allowed to, and says so in the pane if it is not.
///
/// WRITEMIND TAKES THE TABLET ITSELF (`TabletCapture`, which says why the
/// driver cannot be asked to let go): while a tablet is the input AND WHAT
/// IT WRITES ON IS ON SCREEN — its page, or in Notebook mode a note — AND
/// WRITEMIND IS THE ACTIVE APP, its HID device is held seized, the driver
/// hears nothing and the pointer stays where the trackpad left it. Any of
/// the three going gives it back: a pen held for a page nobody can see
/// writes nowhere, the notebook's own pen needs it as a pointer, and in
/// another app it is that app's pen. This class is the shell — it gathers
/// the three, hands them to `TabletCapture`, does what it says through
/// `TabletHID`, and turns the tablet's reports into the funnel's readings.
@MainActor
final class TabletController: ObservableObject {
    enum Status: Equatable {
        /// No tablet is the input.
        case off
        /// The tablet that was picked is not plugged in.
        case unplugged
        /// The input, plugged in, and nothing to say: not held at this
        /// moment — nothing to write on is up, WriteMind is not in front,
        /// or the open is on its way — and no reason it could not be.
        case standby
        /// WriteMind holds the tablet: the pen is the page's and not the
        /// pointer's. `driverStillPosts` when the driver's events kept
        /// coming all the same (`TabletInput.driverStillPosts`).
        case captured(driverStillPosts: Bool)
        /// WriteMind cannot hold it, and why. The page still takes the pen
        /// from what the driver posts; the pointer moves with it.
        case fallback(TabletCapture.Refusal)
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

    /// The funnel the pen comes through, by either route.
    let input: TabletInput

    private let defaults: UserDefaults
    private let hid: TabletHID
    /// When the tablet is held, decided (`TabletCapture`); this class only
    /// does what it says.
    private(set) var capture = TabletCapture()
    /// WriteMind is the active app — kept from the two notices, so that a
    /// launch (not yet active) and a test (never active) are both plain.
    private var appActive: Bool
    /// Input Monitoring as it last read: looked at on every change, and
    /// written to the log only when it is news.
    private var accessRead: TabletCapture.Access?
    private var byRegistryID: [UInt64: TabletDevice] = [:]
    /// Which tablet `input.extent` is the size of.
    private var extentTabletID: String?
    /// How many raw reports, and how many kinds of unknown one, this pick
    /// has written to the log; and whether its first reading has been.
    private var reportsLogged = 0
    private var unknownKinds: Set<String> = []
    private var firstReadingLogged = false
    private var notifyPort: IONotificationPortRef?
    private var arrivals: io_iterator_t = 0
    private var departures: io_iterator_t = 0
    private var observers: [NSObjectProtocol] = []
    var log: (String) -> Void = { line in if !TestHost.isActive { DebugLog.write(line) } }

    /// A just-plugged tablet's HID devices are not there straight away.
    nonisolated static let settle: TimeInterval = 1.5
    /// The first raw reports of a pick go to the log whole, and the first
    /// of each kind that is not the pen's after that.
    nonisolated static let reportsToLog = 12
    nonisolated static let unknownKindsToLog = 8

    private enum Keys {
        static let lastTablet = "lastTabletID"
        static let lastTabletName = "lastTabletName"
    }

    /// `live` is everything that reaches outside the process — the USB
    /// notices, the app's notifications, the remembered pick. None of it in
    /// the test host, which has no tablet and must never open one.
    init(defaults: UserDefaults = .standard, hid: TabletHID = LiveTabletHID(),
         input: TabletInput = .shared, live: Bool = !TestHost.isActive) {
        self.defaults = defaults
        self.hid = hid
        self.input = input
        appActive = live && (NSApp?.isActive ?? false)
        // The page and the notes come and go on the main thread, from their
        // panes; the target changes there too.
        input.targetShowingChanged = { [weak self] _ in
            MainActor.assumeIsolated { self?.targetChanged() }
        }
        input.driverStillPostsChanged = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        guard live else { return }
        restoreRemembered()
        watchUSB()
        observeLifecycle()
    }

    // MARK: - Picking

    /// Sean picked `tablet` from a menu — Input Devices, or the pane's own.
    /// This is the ONE place macOS's Input Monitoring question may come
    /// from. Picking the tablet that is already the input asks again, which
    /// is how a remembered pick from before WriteMind took the tablet
    /// itself — or a question put away unanswered — gets asked.
    func pick(_ tablet: TabletDevice) {
        select(tablet, picked: true)
    }

    /// No tablet: the pane goes back to the camera's.
    func turnOff() {
        guard selectedTabletID != nil else { return }
        selectedTabletID = nil
        selectedName = nil
        defaults.removeObject(forKey: Keys.lastTablet)
        defaults.removeObject(forKey: Keys.lastTabletName)
        extentTabletID = nil
        evaluate()
        input.stop()
    }

    private func select(_ tablet: TabletDevice, picked: Bool) {
        if extentTabletID != tablet.id {
            // The raw sensor's size, from the table — and from then on
            // only what the pen is seen to reach (`TabletExtent.known`).
            input.extent = TabletExtent.known(productID: tablet.productID) ?? .fallback
            extentTabletID = tablet.id
        }
        selectedTabletID = tablet.id
        selectedName = tablet.name
        defaults.set(tablet.id, forKey: Keys.lastTablet)
        defaults.set(tablet.name, forKey: Keys.lastTabletName)
        reportsLogged = 0
        unknownKinds = []
        firstReadingLogged = false
        input.start()
        evaluate(picked: picked)
    }

    /// The pick from the last session, if there was one: the pane shows the
    /// tablet (as unplugged until it is found), and nothing is asked.
    func restoreRemembered() {
        guard selectedTabletID == nil, let id = defaults.string(forKey: Keys.lastTablet) else { return }
        selectedTabletID = id
        selectedName = defaults.string(forKey: Keys.lastTabletName)
        input.start()
        if let tablet = tablets.first(where: { $0.id == id }) {
            select(tablet, picked: false)
        } else {
            refresh()
        }
    }

    // MARK: - Holding the tablet

    /// THE ONE PLACE IT IS DECIDED: the three conditions as they stand, and
    /// Input Monitoring as it reads — read only while a tablet is the input
    /// and plugged in, so a Mac that has never picked one is never so much
    /// as looked up. `picked` only from `pick`.
    private func evaluate(picked: Bool = false) {
        let tablet = selectedTablet
        let conditions = TabletCapture.Conditions(productID: tablet?.productID,
                                                  targetShowing: input.targetIsShowing, active: appActive)
        var access = TabletCapture.Access.undecided
        if tablet != nil {
            access = hid.access()
            if access != accessRead {
                accessRead = access
                log("tablet: Input Monitoring reads \(access)")
            }
        }
        run(capture.changed(conditions, access: access, picked: picked))
    }

    private func run(_ commands: [TabletCapture.Command], quitting: Bool = false) {
        for command in commands {
            switch command {
            case .ask:
                log("tablet: asking macOS for Input Monitoring — the pick's question")
                hid.requestAccess { [weak self] access in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.run(self.capture.answered(access))
                    }
                }
            case .seize(let productID, let attempt):
                log("tablet: capture start — seizing product 0x\(String(productID, radix: 16)) (attempt \(attempt))")
                hid.seize(vendorID: TabletDevice.wacomVendorID, productID: productID, report: { [weak self] bytes, time in
                    MainActor.assumeIsolated { self?.report(bytes, at: time, attempt: attempt) }
                }, done: { [weak self] refusal in
                    MainActor.assumeIsolated { self?.landed(attempt: attempt, refusal: refusal) }
                })
            case .release:
                log("tablet: capture stop — the tablet is let go")
                hid.release(waiting: quitting)
                input.rawEnded(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        refresh()
    }

    private func landed(attempt: Int, refusal: TabletCapture.Refusal?) {
        capture.landed(attempt: attempt, refusal: refusal)
        refresh()
    }

    /// One raw report off the held tablet. Dropped unless it is this
    /// capture's and the capture stands: one that was on its way when the
    /// tablet was let go is nobody's.
    private func report(_ bytes: [UInt8], at time: TimeInterval, attempt: Int) {
        guard capture.isCaptured, attempt == capture.attempt else { return }
        let packet = WacomPenPacket(bytes)
        note(bytes, known: packet != nil)
        let giveUp = capture.reported(known: packet != nil, at: time)
        if !giveUp.isEmpty {
            log("tablet: \(TabletCapture.unreadableBurst) reports in a row and none of them a pen report — "
                + "the tablet cannot be read, and is given back")
            run(giveUp)
        }
        guard let packet else { return }
        let reading = packet.reading(at: time)
        if !firstReadingLogged {
            firstReadingLogged = true
            log("tablet: first raw reading — \(packet) taken as \(reading.kind)")
        }
        input.raw(reading)
    }

    /// NOT ONE LINE PER SAMPLE: the first few reports of a pick, whole, and
    /// after that the first of each kind that is not a pen report — what a
    /// tablet nobody has read before sends is the only evidence of what it
    /// means, and nothing here guesses.
    private func note(_ bytes: [UInt8], known: Bool) {
        if reportsLogged < Self.reportsToLog {
            reportsLogged += 1
            log("tablet: raw report \(reportsLogged) (\(bytes.count) bytes\(known ? "" : ", not a pen report")): "
                + WacomPenPacket.hex(bytes))
        } else if !known, unknownKinds.count < Self.unknownKindsToLog {
            let kind = "\(bytes.first ?? 0)/\(bytes.count)"
            guard unknownKinds.insert(kind).inserted else { return }
            log("tablet: raw report of an unknown kind (id \(bytes.first ?? 0), \(bytes.count) bytes): "
                + WacomPenPacket.hex(Array(bytes.prefix(16))))
        }
    }

    /// What the pane says, from where things stand.
    private func refresh() {
        let now: Status
        if !isSelected {
            now = .off
        } else if selectedTablet == nil {
            now = .unplugged
        } else if capture.isCaptured {
            now = .captured(driverStillPosts: input.driverStillPosts)
        } else if let refusal = capture.refusal {
            now = .fallback(refusal)
        } else {
            now = .standby
        }
        // Only when it is news: an assignment publishes, changed or not.
        if now != status { status = now }
    }

    // MARK: - What happens around it

    /// THE TABLET FOLLOWS THE TARGET. The page — or in Notebook mode a note
    /// — coming on screen takes the pen off the pointer, asking nothing;
    /// the last one going gives it back — ⌘Y, the pane's switch, a camera
    /// picked, the notes put away, Esc sending the pen back to a page that
    /// is put away. Held on, it kept the pen off the pointer while
    /// WriteMind was in front with nothing to write on: the notebook's own
    /// pen, the only other use of the pen here, was dead, and the line that
    /// would have said why was hidden with the pane. From one target to the
    /// other with both on screen is no change.
    func targetChanged() {
        evaluate()
    }

    /// And it follows the app: taken as WriteMind comes to the front — which
    /// is also when a permission given in System Settings is first seen —
    /// and given back as it leaves, so the pen is a pen in whatever app is
    /// in front.
    func appBecameActive() {
        appActive = true
        evaluate()
    }

    func appResignedActive() {
        appActive = false
        evaluate()
    }

    /// On the way out the tablet is closed before the process goes — and
    /// waited for, briefly, because there is no later.
    func appWillQuit() {
        run(capture.changed(TabletCapture.Conditions(), access: .undecided), quitting: true)
    }

    /// A Wacom arrived on the USB bus.
    func plugged(_ tablet: TabletDevice, registryID: UInt64, settle: TimeInterval = TabletController.settle) {
        byRegistryID[registryID] = tablet
        list()
        guard tablet.id == selectedTabletID, status == .unplugged else { return }
        // The pick is back: take the pen again, asking nothing.
        after(settle) { [weak self] in
            guard let self, self.selectedTabletID == tablet.id, self.tablets.contains(tablet) else { return }
            self.select(tablet, picked: false)
        }
    }

    /// A Wacom left the USB bus.
    func unplugged(registryID: UInt64) {
        guard let gone = byRegistryID.removeValue(forKey: registryID) else { return }
        list()
        guard gone.id == selectedTabletID, !tablets.contains(where: { $0.id == gone.id }) else { return }
        evaluate()
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
        case .standby: return "standby"
        case .captured(let driverStillPosts):
            return driverStillPosts ? "captured (the driver still posts)" : "captured"
        case .fallback(let refusal):
            return "fallback(\(refusal))" + (refusal.code.map { " \(TabletCapture.hex($0))" } ?? "")
        }
    }

    // MARK: - Live wiring

    private func observeLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appResignedActive() }
        })
        // Synchronously, on the way out: a Task would run after the app had
        // gone.
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillQuit() }
        })
    }

    /// IOKit's notices for USB devices from Wacom, first-match and
    /// terminated. Matching on the USB DEVICE and opening nothing: reading
    /// a registry entry's properties needs no permission at all.
    private func watchUSB() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            log("tablet: no IOKit notification port")
            return
        }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let me = Unmanaged.passUnretained(self).toOpaque()

        func matching() -> CFDictionary { Self.usbMatching() as CFDictionary }

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(), { refcon, iterator in
            guard let refcon else { return }
            let controller = Unmanaged<TabletController>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { controller.drainArrivals(iterator, settle: TabletController.settle) }
        }, me, &arrivals)
        // Draining arms the notice, and lists what is already plugged in —
        // at launch, long since settled, there is nothing to wait for.
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

    /// Every USB device from Wacom, by a PROPERTY match. `idVendor` put
    /// straight into the matching dictionary is read by the USB family's
    /// own matching rules, which want a vendor AND a product (or a class)
    /// and match nothing on a vendor alone — so the tablet was never found
    /// and never listed (Sean, 2026-10-02: "i don't see the wacom page").
    /// `IOPropertyMatch` compares the registry property itself.
    nonisolated static func usbMatching(vendor: Int = TabletDevice.wacomVendorID) -> NSDictionary {
        let dictionary = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        dictionary[kIOPropertyMatchKey] = ["idVendor": vendor]
        return dictionary
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
