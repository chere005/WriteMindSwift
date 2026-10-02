import AppKit
import CoreServices
import XCTest
@testable import WriteMind

/// The Apple Events WriteMind sends the Wacom driver, taken apart field by
/// field against Wacom's own sample (WacomTabletDriver.m) — and the rule
/// that nothing is ever SENT from here: the test host is the app, and an
/// Apple Event from it would put an Automation prompt in front of Sean.
final class WacomDriverTests: XCTestCase {
    private func fourCC(_ code: String) -> FourCharCode { WacomDriver.fourCC(code) }

    private func param(_ event: NSAppleEventDescriptor, _ keyword: String) -> NSAppleEventDescriptor? {
        event.paramDescriptor(forKeyword: fourCC(keyword))
    }

    /// One level of an object specifier: what class, by which form, keyed
    /// by what, inside what.
    private func assertSpecifier(_ specifier: NSAppleEventDescriptor?, wants objectClass: String,
                                 form: String, file: StaticString = #filePath, line: UInt = #line)
        -> (key: NSAppleEventDescriptor?, container: NSAppleEventDescriptor?) {
        guard let specifier else {
            XCTFail("no specifier", file: file, line: line)
            return (nil, nil)
        }
        XCTAssertEqual(specifier.descriptorType, typeObjectSpecifier, file: file, line: line)
        XCTAssertEqual(specifier.forKeyword(fourCC("want"))?.typeCodeValue, fourCC(objectClass),
                       "the class", file: file, line: line)
        XCTAssertEqual(specifier.forKeyword(fourCC("form"))?.enumCodeValue, fourCC(form),
                       "the key form", file: file, line: line)
        return (specifier.forKeyword(fourCC("seld")), specifier.forKeyword(fourCC("from")))
    }

    private func uint32(_ descriptor: NSAppleEventDescriptor?) -> UInt32? {
        guard let descriptor, descriptor.descriptorType == typeUInt32, descriptor.data.count == 4 else { return nil }
        return descriptor.data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    // MARK: - The target and the routing tables

    func testTheTargetIsTheDriversSignature() {
        XCTAssertEqual(WacomDriver.signature, 0x5761_434D, "'WaCM'")
        let target = WacomDriver.target()
        XCTAssertEqual(target.descriptorType, typeApplSignature)
        let signature = target.data.withUnsafeBytes { $0.load(as: OSType.self) }
        XCTAssertEqual(signature, fourCC("WaCM"), "the sample hands &tdSig over in the Mac's own byte order")
    }

    func testTheDriverIsTheFirstAndOnlyOne() {
        let (key, container) = assertSpecifier(WacomDriver.driver(), wants: "Drvr", form: "indx")
        XCTAssertEqual(uint32(key), 1)
        XCTAssertEqual(container?.descriptorType, typeNull, "no container")
    }

    func testATabletIsByPositionAndOneBased() {
        let (key, container) = assertSpecifier(WacomDriver.tablet(1), wants: "Tblt", form: "indx")
        XCTAssertEqual(uint32(key), 1, "tablet 1 is the first — the sample's indices are 1-based")
        XCTAssertEqual(container?.descriptorType, typeNull)
    }

    /// The context the driver handed back is addressed by its UNIQUE ID
    /// ('ID  '), as the sample's `routingTableForContext:` does — by
    /// position it would be some other context, or none.
    func testAContextIsByItsUniqueID() {
        let (key, container) = assertSpecifier(WacomDriver.context(0xDEAD_BEEF), wants: "CTxt", form: "ID  ")
        XCTAssertEqual(uint32(key), 0xDEAD_BEEF, "all 32 bits, unsigned")
        XCTAssertEqual(container?.descriptorType, typeNull)
    }

    // MARK: - The events

    private func assertEvent(_ event: NSAppleEventDescriptor, _ eventClass: String, _ eventID: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.descriptorType, typeAppleEvent, file: file, line: line)
        XCTAssertEqual(event.eventClass, fourCC(eventClass), file: file, line: line)
        XCTAssertEqual(event.eventID, fourCC(eventID), file: file, line: line)
        let address = event.attributeDescriptor(forKeyword: keyAddressAttr)
        XCTAssertEqual(address?.descriptorType, typeApplSignature, "sent to the driver", file: file, line: line)
        XCTAssertEqual(address?.data.withUnsafeBytes { $0.load(as: OSType.self) }, fourCC("WaCM"),
                       file: file, line: line)
    }

    func testCountingTheTabletsAsksTheDriver() {
        let event = WacomDriver.countTablets()
        assertEvent(event, "core", "cnte")
        XCTAssertEqual(param(event, "kocl")?.typeCodeValue, fourCC("Tblt"))
        let (key, _) = assertSpecifier(param(event, "----"), wants: "Drvr", form: "indx")
        XCTAssertEqual(uint32(key), 1)
    }

    func testTheTabletsSizeIsReadOffTheTabletItself() {
        let event = WacomDriver.getData(WacomDriver.Property.xDimension, as: typeSInt32, of: WacomDriver.tablet(1))
        assertEvent(event, "core", "getd")
        XCTAssertEqual(param(event, "rtyp")?.typeCodeValue, typeSInt32)
        let (property, tablet) = assertSpecifier(param(event, "----"), wants: "prop", form: "prop")
        XCTAssertEqual(property?.typeCodeValue, fourCC("Xdim"))
        let (index, _) = assertSpecifier(tablet, wants: "Tblt", form: "indx")
        XCTAssertEqual(uint32(index), 1)
        XCTAssertEqual(WacomDriver.Property.yDimension, fourCC("Ydim"))
        XCTAssertEqual(WacomDriver.Property.name, fourCC("pnam"), "pName")
    }

    func testAContextIsMadeOverTabletOneAsTheDefaultKind() {
        let event = WacomDriver.createContext(forTablet: 1)
        assertEvent(event, "core", "crel")
        XCTAssertEqual(param(event, "kocl")?.typeCodeValue, fourCC("CTxt"))
        let (index, _) = assertSpecifier(param(event, "insh"), wants: "Tblt", form: "indx")
        XCTAssertEqual(uint32(index), 1)
        XCTAssertEqual(param(event, "for ")?.typeCodeValue, fourCC("Pos "),
                       "the default context takes the tablet over; a blank one only customises buttons")
    }

    /// THE ONE PROPERTY WRITTEN, AND ONLY THROUGH THE CONTEXT. Written through
    /// the tablet's own routing it would change the tablet for every app on
    /// the Mac — the sample's comment, in capitals.
    func testMvscIsSetFalseThroughTheContextAndNeverTheTablet() {
        let event = WacomDriver.setMovesSystemCursor(false, context: 42)
        assertEvent(event, "core", "setd")
        let (property, owner) = assertSpecifier(param(event, "----"), wants: "prop", form: "prop")
        XCTAssertEqual(property?.typeCodeValue, fourCC("Mvsc"))
        let (id, _) = assertSpecifier(owner, wants: "CTxt", form: "ID  ")
        XCTAssertEqual(uint32(id), 42)
        XCTAssertEqual(param(event, "rtyp")?.typeCodeValue, typeBoolean)
        let data = param(event, "data")
        XCTAssertEqual(data?.descriptorType, typeBoolean)
        XCTAssertEqual(data?.booleanValue, false)
        XCTAssertEqual(WacomDriver.setMovesSystemCursor(true, context: 42)
            .paramDescriptor(forKeyword: fourCC("data"))?.booleanValue, true)
    }

    func testAContextIsLetGoByItsID() {
        let event = WacomDriver.deleteContext(42)
        assertEvent(event, "core", "delo")
        let (id, _) = assertSpecifier(param(event, "----"), wants: "CTxt", form: "ID  ")
        XCTAssertEqual(uint32(id), 42)
    }

    // MARK: - What comes back

    func testEveryFailureHasAName() {
        XCTAssertEqual(WacomDriver.Failure(status: -1743), .automationDenied)
        XCTAssertEqual(WacomDriver.Failure(status: -1744), .needsConsent)
        XCTAssertEqual(WacomDriver.Failure(status: -1712), .timedOut)
        XCTAssertEqual(WacomDriver.Failure(status: -600), .noDriver, "procNotFound")
        XCTAssertEqual(WacomDriver.Failure(status: -609), .noDriver, "connectionInvalid: it went away mid-sentence")
        XCTAssertEqual(WacomDriver.Failure(status: -1728), .other(-1728))
        XCTAssertEqual(WacomDriver.Failure.automationDenied.status, -1743)
        XCTAssertEqual(WacomDriver.Failure.other(-50).status, -50)
        XCTAssertNil(WacomDriver.Failure.noTablet.status)
    }

    /// AESend's noErr only means DELIVERED; a handler that failed says so
    /// in the reply's 'errn'.
    func testAnErrorInsideTheReplyIsAFailure() {
        let reply = NSAppleEventDescriptor(eventClass: fourCC("aevt"), eventID: fourCC("ansr"),
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        reply.setParam(NSAppleEventDescriptor(int32: 7), forKeyword: keyDirectObject)
        XCTAssertEqual(try WacomDriver.answer(of: reply).get()?.int32Value, 7)
        reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: keyErrorNumber)
        XCTAssertEqual(WacomDriver.answer(of: reply).failure, .other(-1728))
        reply.setParam(NSAppleEventDescriptor(int32: 0), forKeyword: keyErrorNumber)
        XCTAssertEqual(try WacomDriver.answer(of: reply).get()?.int32Value, 7, "errn 0 is no error")
    }

    func testAThrownErrorIsAFailure() {
        XCTAssertEqual(WacomDriver.failure(of: NSError(domain: NSOSStatusErrorDomain, code: -1743)),
                       .automationDenied)
        XCTAssertEqual(WacomDriver.failure(of: NSError(domain: NSOSStatusErrorDomain, code: -1712)), .timedOut)
    }

    // MARK: - Nothing is sent from here

    /// THE GUARD IS THE FIRST LINE OF BOTH DOORS. The spies stand where the
    /// real send and the real permission check would be — so if the guard
    /// ever went, this fails on a spy, not on Sean's screen.
    func testTheTestHostSendsNothingAndAsksNothing() {
        XCTAssertTrue(TestHost.isActive)
        var delivered = 0
        var determined = 0
        var wire = WacomDriver.Wire()
        wire.deliver = { event, _, _ in delivered += 1; return event }
        wire.determine = { _, _ in determined += 1; return noErr }

        XCTAssertEqual(wire.permission(ask: false).failure, .refusedUnderTest)
        XCTAssertEqual(wire.permission(ask: true).failure, .refusedUnderTest)
        XCTAssertEqual(wire.send(WacomDriver.countTablets()).failure, .refusedUnderTest)
        XCTAssertEqual(wire.send(WacomDriver.deleteContext(3), reply: false).failure, .refusedUnderTest)
        XCTAssertEqual(WacomDriver.takeThePen(existing: nil, ask: true, over: wire).failure, .refusedUnderTest)
        XCTAssertEqual(WacomDriver.letGo(3, over: wire).failure, .refusedUnderTest)
        XCTAssertEqual(delivered, 0, "an Apple Event left the test host")
        XCTAssertEqual(determined, 0, "the test host asked macOS about Automation")
    }

    // MARK: - The conversation, against a stand-in driver

    /// Answers the way the driver would, and keeps a list of what it was
    /// asked. Sends nothing anywhere.
    private final class StandIn: DriverWire {
        var permitted: Result<Void, WacomDriver.Failure> = .success(())
        var permittedOnAsking: Result<Void, WacomDriver.Failure> = .success(())
        var tablets: Int32 = 1
        var newContext: Int32 = 501
        /// Contexts the driver no longer has.
        var gone: Set<UInt32> = []
        var mvscFails: WacomDriver.Failure?
        private(set) var asked: [Bool] = []
        private(set) var said: [String] = []

        func permission(ask: Bool) -> Result<Void, WacomDriver.Failure> {
            asked.append(ask)
            return ask ? permittedOnAsking : permitted
        }

        func send(_ event: NSAppleEventDescriptor, reply: Bool,
                  timeout: TimeInterval) -> Result<NSAppleEventDescriptor?, WacomDriver.Failure> {
            let id = event.eventID
            func code(_ value: FourCharCode) -> String {
                String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, encoding: .macOSRoman) ?? "?"
            }
            switch code(id) {
            case "cnte":
                said.append("count")
                return .success(NSAppleEventDescriptor(int32: tablets))
            case "getd":
                let property = event.paramDescriptor(forKeyword: keyDirectObject)?
                    .forKeyword(WacomDriver.fourCC("seld"))?.typeCodeValue ?? 0
                said.append("get \(code(property))")
                switch code(property) {
                case "Xdim": return .success(NSAppleEventDescriptor(int32: 15200))
                case "Ydim": return .success(NSAppleEventDescriptor(int32: 9500))
                default: return .success(NSAppleEventDescriptor(string: "One by Wacom S"))
                }
            case "crel":
                said.append("create")
                return .success(NSAppleEventDescriptor(int32: newContext))
            case "setd":
                let context = event.paramDescriptor(forKeyword: keyDirectObject)?
                    .forKeyword(WacomDriver.fourCC("from"))?.forKeyword(WacomDriver.fourCC("seld"))
                let id = context?.data.withUnsafeBytes { $0.load(as: UInt32.self) } ?? 0
                said.append("mvsc \(id)")
                if gone.contains(id) { return .failure(.other(-1728)) }
                if let mvscFails { return .failure(mvscFails) }
                return .success(nil)
            case "delo":
                said.append(reply ? "delete" : "delete, not waiting")
                return .success(nil)
            default:
                said.append(code(id))
                return .success(nil)
            }
        }
    }

    func testANewContextIsMadeOverTabletOneAndToldToLeaveThePointerAlone() {
        let driver = StandIn()
        let outcome = WacomDriver.takeThePen(existing: nil, ask: false, over: driver)
        XCTAssertEqual(driver.said, ["count", "get Xdim", "get Ydim", "get pnam", "create", "mvsc 501"])
        XCTAssertEqual(outcome.context, 501)
        XCTAssertTrue(outcome.created)
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.extent, TabletExtent(width: 15200, height: 9500))
        XCTAssertEqual(outcome.name, "One by Wacom S")
        XCTAssertEqual(driver.asked, [false], "permission is READ, without a prompt")
    }

    /// A FIRST LAUNCH NEVER ASKS: with nobody asked yet and no pick behind
    /// the call, it stops at the question and sends nothing.
    func testWithoutAPickNobodyIsAskedAndNothingIsSent() {
        let driver = StandIn()
        driver.permitted = .failure(.needsConsent)
        let outcome = WacomDriver.takeThePen(existing: nil, ask: false, over: driver)
        XCTAssertEqual(outcome.failure, .needsConsent)
        XCTAssertEqual(driver.asked, [false])
        XCTAssertEqual(driver.said, [], "an event sent here would put the prompt up")
    }

    func testAPickAsksOnceAndCarriesOn() {
        let driver = StandIn()
        driver.permitted = .failure(.needsConsent)
        let outcome = WacomDriver.takeThePen(existing: nil, ask: true, over: driver)
        XCTAssertEqual(driver.asked, [false, true])
        XCTAssertEqual(outcome.context, 501)
    }

    func testARefusalIsSaidAndNothingIsSent() {
        let driver = StandIn()
        driver.permitted = .failure(.automationDenied)
        XCTAssertEqual(WacomDriver.takeThePen(existing: nil, ask: true, over: driver).failure, .automationDenied)
        XCTAssertEqual(driver.asked, [false], "a refusal is Sean's answer; it is not asked again")
        XCTAssertEqual(driver.said, [])
    }

    func testAPickThatIsRefusedAtThePromptIsSaid() {
        let driver = StandIn()
        driver.permitted = .failure(.needsConsent)
        driver.permittedOnAsking = .failure(.automationDenied)
        XCTAssertEqual(WacomDriver.takeThePen(existing: nil, ask: true, over: driver).failure, .automationDenied)
        XCTAssertEqual(driver.said, [])
    }

    /// Back to the front: the context still standing is KEPT — one event,
    /// not a new context every time the app is clicked.
    func testAContextStillStandingIsKept() {
        let driver = StandIn()
        let outcome = WacomDriver.takeThePen(existing: 77, ask: false, over: driver)
        XCTAssertEqual(driver.said, ["mvsc 77"])
        XCTAssertEqual(outcome.context, 77)
        XCTAssertFalse(outcome.created)
    }

    func testAContextTheDriverNoLongerHasIsMadeAgain() {
        let driver = StandIn()
        driver.gone = [77]
        let outcome = WacomDriver.takeThePen(existing: 77, ask: false, over: driver)
        XCTAssertEqual(driver.said, ["mvsc 77", "count", "get Xdim", "get Ydim", "get pnam", "create", "mvsc 501"])
        XCTAssertEqual(outcome.context, 501)
        XCTAssertTrue(outcome.created)
    }

    /// A context that would not do the one thing it was made for is let go
    /// at once, not left applying in the driver.
    func testAContextThatWillNotTakeThePenIsLetGo() {
        let driver = StandIn()
        driver.mvscFails = .timedOut
        let outcome = WacomDriver.takeThePen(existing: nil, ask: false, over: driver)
        XCTAssertEqual(driver.said.suffix(2), ["mvsc 501", "delete, not waiting"])
        XCTAssertNil(outcome.context)
        XCTAssertEqual(outcome.failure, .timedOut)
    }

    func testADriverWithNoTabletMakesNoContext() {
        let driver = StandIn()
        driver.tablets = 0
        let outcome = WacomDriver.takeThePen(existing: nil, ask: false, over: driver)
        XCTAssertEqual(outcome.failure, .noTablet)
        XCTAssertEqual(driver.said, ["count"])
    }

    func testAContextIdOfZeroIsNoContext() {
        let driver = StandIn()
        driver.newContext = 0
        XCTAssertEqual(WacomDriver.takeThePen(existing: nil, ask: false, over: driver).failure, .noReply)
        XCTAssertFalse(driver.said.contains { $0.hasPrefix("mvsc") })
    }

    func testLettingGoCanBeWaitedForOrNot() {
        let driver = StandIn()
        _ = WacomDriver.letGo(9, over: driver)
        _ = WacomDriver.letGo(9, wait: false, over: driver)
        XCTAssertEqual(driver.said, ["delete", "delete, not waiting"])
    }

    /// The usage string macOS shows in the Automation prompt — without one
    /// the prompt never comes and the send just fails.
    func testTheAppSaysWhyItWantsTheDriver() throws {
        let reason = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String)
        XCTAssertTrue(reason.contains("Wacom"), reason)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
