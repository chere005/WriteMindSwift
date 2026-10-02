// The parts of Wacom's Driver Request Interface that WriteMind needs, ported
// to Swift from Wacom's own sample:
//
//     https://github.com/Wacom-Developer/wacom-device-kit-macos-api
//     WacomTabletDriver.m, NSAppleEventDescriptorHelperCategory.m and
//     TabletAEDictionary.h (2020 release)
//
// MIT License
//
// Copyright (c) 2020 Wacom
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import CoreServices

/// Talking to the Wacom driver, so that the pen is a pen on the page and not
/// a second mouse (Sean, 2026-10-02: "wacom should basically just be chosen
/// as if it were an input display").
///
/// The driver answers Apple Events sent to the application whose signature
/// is 'WaCM' (TabletDriver.app, `com.wacom.TabletDriver`). An application
/// asks it for a CONTEXT over one tablet — its own sandbox of settings,
/// which acts only while that application is frontmost and goes when it
/// quits — and a context whose `pContextMovesSystemCursor` ('Mvsc') is
/// false keeps the pen off the pointer: Wacom's words, "all tablet events
/// … be sent as pure tablet events".
///
/// A PORT, NOT A REIMAGINING: the descriptors below are the sample's,
/// field for field, and `WacomDriverTests` takes each one apart. Two rules
/// carried over from the sample's own comments: a property is only ever SET
/// through a context's routing — the raw tablet's routing is the GLOBAL
/// tablet, every application's — and a context is destroyed before the
/// application quits.
///
/// Building a descriptor sends nothing. Sending is `Wire`'s, and the wire
/// refuses outright under `TestHost`: the test host IS the app, and an
/// Apple Event from it would put up a macOS Automation prompt that is Sean's
/// to answer, from the app he chose to run, not from a test.
enum WacomDriver {
    /// The driver's Apple Event signature, and the bundle whose process
    /// carries it (read off its Info.plist, 2026-10-02).
    static let signature = fourCC("WaCM")
    static let bundleIdentifier = "com.wacom.TabletDriver"

    /// Long enough for a driver that is merely busy, short enough that a
    /// driver that is wedged costs a beat and not the session. The sample
    /// waits 6000 seconds (360000 ticks) for everything.
    static let timeout: TimeInterval = 2

    // MARK: - The dictionary (TabletAEDictionary.h)

    enum Class {
        static let driver = fourCC("Drvr")      // cWTDDriver
        static let tablet = fourCC("Tblt")      // cWTDTablet
        static let context = fourCC("CTxt")     // cContext
    }

    enum Property {
        static let name = fourCC("pnam")        // pName, typeUTF8Text r/o
        static let xDimension = fourCC("Xdim")  // pXDimension, typeSInt32 r/o
        static let yDimension = fourCC("Ydim")  // pYDimension, typeSInt32 r/o
        /// pContextMovesSystemCursor, typeBoolean.
        static let movesSystemCursor = fourCC("Mvsc")
    }

    /// AEContextType. Default takes the tablet over — output areas reset to
    /// full size, the transducers acquired, the control panel's mapping no
    /// longer applied — which is what a page that IS the tablet wants.
    enum ContextType {
        static let `default` = fourCC("Pos ")
        static let blank = fourCC("Blnk")
    }

    /// The keyword the sample puts the context type under.
    static let contextTypeKeyword = fourCC("for ")

    static func fourCC(_ code: String) -> FourCharCode {
        code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }

    // MARK: - Routing tables (pure)

    /// The driver itself, as an Apple Event target: its signature, by value.
    static func target() -> NSAppleEventDescriptor {
        var signature = Self.signature
        return NSAppleEventDescriptor(descriptorType: typeApplSignature, bytes: &signature,
                                      length: MemoryLayout<OSType>.size)!
    }

    /// `+descriptorForObjectOfType:withKey:ofForm:from:` — an object
    /// specifier, by CreateObjSpecifier exactly as the sample builds it.
    /// No container is the null descriptor ("no container").
    static func object(_ objectClass: DescType, key: NSAppleEventDescriptor, form: DescType,
                       from container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        let from = container ?? .null()
        return withExtendedLifetime((from, key)) {
            var containerDesc = from.aeDesc!.pointee
            var keyDesc = key.aeDesc!.pointee
            var result = AEDesc()
            let status = CreateObjSpecifier(objectClass, &containerDesc, form, &keyDesc, false, &result)
            precondition(status == noErr, "CreateObjSpecifier: \(status)")
            return NSAppleEventDescriptor(aeDescNoCopy: &result)
        }
    }

    /// `+descriptorWithUInt32:`.
    static func uint32(_ value: UInt32) -> NSAppleEventDescriptor {
        var value = value
        return NSAppleEventDescriptor(descriptorType: typeUInt32, bytes: &value,
                                      length: MemoryLayout<UInt32>.size)!
    }

    /// `+routingTableForDriver` — the first and only driver.
    static func driver() -> NSAppleEventDescriptor {
        object(Class.driver, key: uint32(1), form: DescType(formAbsolutePosition))
    }

    /// `+routingTableForTablet:` — 1-based. For READING only: setting a
    /// property through this changes the tablet for every application.
    static func tablet(_ index: UInt32) -> NSAppleEventDescriptor {
        object(Class.tablet, key: uint32(index), form: DescType(formAbsolutePosition))
    }

    /// `+routingTableForContext:` — by the id the driver handed back, in
    /// the UNIQUE-ID form (not by position, whatever a summary says).
    static func context(_ id: UInt32) -> NSAppleEventDescriptor {
        object(Class.context, key: uint32(id), form: DescType(formUniqueID))
    }

    /// A property of whatever `container` routes to.
    static func property(_ code: DescType, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(DescType(formPropertyID), key: NSAppleEventDescriptor(typeCode: code),
               form: DescType(formPropertyID), from: container)
    }

    // MARK: - Events (pure)

    private static func event(_ eventClass: AEEventClass, _ eventID: AEEventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: target(),
                               returnID: AEReturnID(kAutoGenerateReturnID),
                               transactionID: AETransactionID(kAnyTransactionID))
    }

    /// `+tabletCount`.
    static func countTablets() -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAECountElements)
        event.setDescriptor(NSAppleEventDescriptor(typeCode: Class.tablet), forKeyword: keyAEObjectClass)
        event.setDescriptor(driver(), forKeyword: keyDirectObject)
        return event
    }

    /// `+dataForAttribute:ofType:routingTable:`.
    static func getData(_ property: DescType, as type: DescType,
                        of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAEGetData)
        event.setDescriptor(self.property(property, of: container), forKeyword: keyDirectObject)
        event.setDescriptor(NSAppleEventDescriptor(typeCode: type), forKeyword: keyAERequestedType)
        return event
    }

    /// `+createContextForTablet:type:`.
    static func createContext(forTablet index: UInt32, type: DescType = ContextType.default) -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAECreateElement)
        event.setDescriptor(NSAppleEventDescriptor(typeCode: Class.context), forKeyword: keyAEObjectClass)
        event.setDescriptor(tablet(index), forKeyword: keyAEInsertHere)
        event.setDescriptor(NSAppleEventDescriptor(typeCode: type), forKeyword: contextTypeKeyword)
        return event
    }

    /// `+setBytes:ofSize:ofType:forAttribute:routingTable:` for the one
    /// property this app sets, through the CONTEXT's routing.
    static func setMovesSystemCursor(_ moves: Bool, context id: UInt32) -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAESetData)
        event.setDescriptor(property(Property.movesSystemCursor, of: context(id)), forKeyword: keyDirectObject)
        event.setDescriptor(NSAppleEventDescriptor(typeCode: typeBoolean), forKeyword: keyAERequestedType)
        var byte: UInt8 = moves ? 1 : 0
        let data = NSAppleEventDescriptor(descriptorType: typeBoolean, bytes: &byte, length: 1)!
        event.setDescriptor(data, forKeyword: keyAEData)
        return event
    }

    /// `+destroyContext:`.
    static func deleteContext(_ id: UInt32) -> NSAppleEventDescriptor {
        let event = event(kAECoreSuite, kAEDelete)
        event.setDescriptor(context(id), forKeyword: keyDirectObject)
        return event
    }

    // MARK: - What went wrong

    /// Every way a conversation with the driver can end short, as a value:
    /// nothing here throws past the controller and nothing crashes.
    enum Failure: Error, Equatable {
        /// The driver is not running — or it went away mid-sentence.
        case noDriver
        /// The Automation switch for WriteMind → the Wacom driver is OFF
        /// (errAEEventNotPermitted, -1743).
        case automationDenied
        /// Nobody has been asked yet (errAEEventWouldRequireUserConsent,
        /// -1744). Asking is a prompt, and the prompt is only ever put up
        /// because Sean picked the tablet.
        case needsConsent
        /// The driver did not answer in `timeout` (errAETimeout, -1712).
        case timedOut
        /// The driver answered without the thing asked for — a context id
        /// of 0, say.
        case noReply
        /// The driver is up but has no tablet to make a context over.
        case noTablet
        /// This process is the test host or the smoke, which never talk to
        /// another application.
        case refusedUnderTest
        /// Anything else, as the OSStatus it came back as.
        case other(OSStatus)

        init(status: OSStatus) {
            switch Int(status) {
            case procNotFound, connectionInvalid: self = .noDriver
            case errAEEventNotPermitted: self = .automationDenied
            case errAEEventWouldRequireUserConsent: self = .needsConsent
            case errAETimeout: self = .timedOut
            default: self = .other(status)
            }
        }

        /// For the log line: what macOS actually said.
        var status: OSStatus? {
            switch self {
            case .noDriver: return OSStatus(procNotFound)
            case .automationDenied: return OSStatus(errAEEventNotPermitted)
            case .needsConsent: return OSStatus(errAEEventWouldRequireUserConsent)
            case .timedOut: return OSStatus(errAETimeout)
            case .other(let status): return status
            case .noReply, .noTablet, .refusedUnderTest: return nil
            }
        }
    }

    /// What a reply says: its direct object, or the error the driver put in
    /// it. AESend returning noErr only means the event was DELIVERED — a
    /// handler that failed says so in the reply's 'errn'.
    static func answer(of reply: NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, Failure> {
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != noErr {
            return .failure(Failure(status: error.int32Value))
        }
        return .success(reply.paramDescriptor(forKeyword: keyDirectObject))
    }

    /// An error thrown by a send, as a Failure.
    static func failure(of error: Error) -> Failure {
        let error = error as NSError
        guard error.domain == NSOSStatusErrorDomain else { return .other(OSStatus(truncatingIfNeeded: error.code)) }
        return Failure(status: OSStatus(truncatingIfNeeded: error.code))
    }

    // MARK: - The wire

    /// Where the events actually go. The live one REFUSES UNDER TEST
    /// before it does anything at all — the guard is the first line of both
    /// doors, the way `CellRunner`'s is on the spawn — and `deliver` and
    /// `determine` are only replaceable so a test can prove the guard holds
    /// without anything reaching the real driver if it did not. The
    /// conversations below are written against `DriverWire`, so a test can
    /// hold one with a stand-in that answers the way the driver would.
    struct Wire: DriverWire {
        var deliver: (NSAppleEventDescriptor, NSAppleEventDescriptor.SendOptions, TimeInterval) throws -> NSAppleEventDescriptor = {
            try $0.sendEvent(options: $1, timeout: $2)
        }
        var determine: (NSAppleEventDescriptor, Bool) -> OSStatus = { target, ask in
            AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                  AEEventID(typeWildCard), ask)
        }

        /// May WriteMind send the driver Apple Events? With `ask` false this
        /// only READS the answer — no prompt, ever. With `ask` true it may
        /// put macOS's Automation prompt up and BLOCKS until it is answered,
        /// which is why the controller never calls it on the main thread.
        func permission(ask: Bool) -> Result<Void, Failure> {
            guard !TestHost.isActive else { return .failure(.refusedUnderTest) }
            let status = determine(WacomDriver.target(), ask)
            return status == noErr ? .success(()) : .failure(Failure(status: status))
        }

        /// Send `event` and wait (at most `timeout`) for what it says.
        /// Without `reply` the event is posted and nothing is waited for —
        /// the sample's `sendWithPriority:andTimeout:`, used to let a context
        /// go on the way out.
        func send(_ event: NSAppleEventDescriptor, reply: Bool,
                  timeout: TimeInterval) -> Result<NSAppleEventDescriptor?, Failure> {
            guard !TestHost.isActive else { return .failure(.refusedUnderTest) }
            do {
                let answer = try deliver(event, reply ? [.waitForReply, .neverInteract] : [.noReply, .neverInteract],
                                         timeout)
                return reply ? WacomDriver.answer(of: answer) : .success(nil)
            } catch {
                return .failure(WacomDriver.failure(of: error))
            }
        }
    }

    // MARK: - Conversations (each a few sends, run off the main thread)

    /// What one go at taking the pen off the pointer came back with.
    struct Outcome: Equatable {
        /// The context now standing, if there is one.
        var context: UInt32?
        /// True when `context` was made this time rather than kept.
        var created = false
        /// Why there is no context.
        var failure: Failure?
        /// The tablet's own size in counts, when the driver said.
        var extent: TabletExtent?
        /// The driver's name for the tablet, when it said.
        var name: String?
    }

    /// Take the pen off the pointer: be allowed to ask, then either keep the
    /// context already standing (setting Mvsc false on it again proves it
    /// still is) or make a new one over tablet 1 and set it there.
    ///
    /// `ask` is true ONLY when Sean has just picked the tablet from a menu:
    /// that is the one thing allowed to put the Automation prompt up. Every
    /// other caller — a launch reconnecting a remembered tablet, the app
    /// coming back to the front, the driver restarting, the tablet plugged
    /// back in — reads the answer and stops at `needsConsent`.
    ///
    /// The tablet's size is read once, as the context is made, off the RAW
    /// tablet (reading is what the sample says the raw routing is for); a
    /// tablet the driver will not measure falls back to the table.
    static func takeThePen(existing: UInt32?, ask: Bool, over wire: DriverWire = Wire()) -> Outcome {
        switch wire.permission(ask: false) {
        case .success:
            break
        case .failure(.needsConsent) where ask:
            if case .failure(let failure) = wire.permission(ask: true) { return Outcome(failure: failure) }
        case .failure(let failure):
            return Outcome(failure: failure)
        }

        if let existing {
            switch wire.send(setMovesSystemCursor(false, context: existing)) {
            case .success:
                return Outcome(context: existing)
            case .failure(.noDriver):
                // The driver went, and its contexts with it.
                return Outcome(failure: .noDriver)
            case .failure(let failure) where [.automationDenied, .timedOut, .refusedUnderTest].contains(failure):
                // Nothing a new context would get past — and the old one
                // may well still be standing, so it is kept to be let go.
                return Outcome(context: existing, failure: failure)
            case .failure:
                // Gone — the driver dropped it, or restarted underneath us.
                // Make another.
                break
            }
        }

        var outcome = Outcome()
        switch wire.send(countTablets()) {
        case .success(let count?) where count.int32Value >= 1:
            break
        case .success:
            outcome.failure = .noTablet
            return outcome
        case .failure(let failure):
            outcome.failure = failure
            return outcome
        }

        if case .success(let width?) = wire.send(getData(Property.xDimension, as: typeSInt32, of: tablet(1))),
           case .success(let height?) = wire.send(getData(Property.yDimension, as: typeSInt32, of: tablet(1))),
           width.int32Value > 0, height.int32Value > 0 {
            outcome.extent = TabletExtent(width: Double(width.int32Value), height: Double(height.int32Value))
        }
        if case .success(let name?) = wire.send(getData(Property.name, as: typeUTF8Text, of: tablet(1))) {
            outcome.name = name.stringValue
        }

        let id: UInt32
        switch wire.send(createContext(forTablet: 1)) {
        case .success(let reply?) where reply.int32Value != 0:
            id = UInt32(bitPattern: reply.int32Value)
        case .success:
            outcome.failure = .noReply
            return outcome
        case .failure(let failure):
            outcome.failure = failure
            return outcome
        }

        switch wire.send(setMovesSystemCursor(false, context: id)) {
        case .success:
            outcome.context = id
            outcome.created = true
        case .failure(let failure):
            // A context that does not do the one thing it was made for is
            // a context the driver applies for nothing. Let it go.
            _ = wire.send(deleteContext(id), reply: false)
            outcome.failure = failure
        }
        return outcome
    }

    /// Let a context go. `wait` false posts the delete and returns at once —
    /// on the way out of the app there is no time to wait for a reply, and
    /// the sample never waits for this one either.
    @discardableResult
    static func letGo(_ id: UInt32, wait: Bool = true, over wire: DriverWire = Wire()) -> Result<Void, Failure> {
        wire.send(deleteContext(id), reply: wait).map { _ in () }
    }

    /// Whether the driver's process is up at all — asked of the process
    /// list, which is no Apple Event and no prompt.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// The two doors to the driver: may we, and say this. `WacomDriver.Wire` is
/// the real one; a test's stand-in answers like the driver and sends
/// nothing anywhere.
protocol DriverWire {
    func permission(ask: Bool) -> Result<Void, WacomDriver.Failure>
    /// The reply's direct object (nil without one, and always nil when no
    /// reply was waited for).
    func send(_ event: NSAppleEventDescriptor, reply: Bool,
              timeout: TimeInterval) -> Result<NSAppleEventDescriptor?, WacomDriver.Failure>
}

extension DriverWire {
    func send(_ event: NSAppleEventDescriptor, reply: Bool = true) -> Result<NSAppleEventDescriptor?, WacomDriver.Failure> {
        send(event, reply: reply, timeout: WacomDriver.timeout)
    }
}
