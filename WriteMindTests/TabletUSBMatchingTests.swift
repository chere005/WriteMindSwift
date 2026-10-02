import IOKit
import XCTest
@testable import WriteMind

/// The dictionary the tablet is looked for with must FIND a USB device by
/// its vendor alone. The first one put `idVendor` straight in, which the USB
/// family reads by its own rules (a vendor AND a product, or a class) and
/// matches nothing on — so the One by Wacom plugged into Sean's Mac was
/// never listed in Input Devices (Sean, 2026-10-02: "i don't see the wacom
/// page"). The registry is read, never opened, so this asks for nothing.
final class TabletUSBMatchingTests: XCTestCase {
    private func matches(_ dictionary: NSDictionary) -> Int {
        var iterator: io_iterator_t = 0
        // IOServiceGetMatchingServices consumes one reference to the
        // dictionary; hand it a copy so the caller's stays whole.
        guard IOServiceGetMatchingServices(kIOMainPortDefault, dictionary.copy() as! CFDictionary,
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            count += 1
            IOObjectRelease(service)
        }
        return count
    }

    /// Whatever USB devices this Mac has, each one's vendor finds it.
    func testEveryUSBDeviceIsFoundByItsVendorAlone() throws {
        var iterator: io_iterator_t = 0
        XCTAssertEqual(IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"),
                                                    &iterator), KERN_SUCCESS)
        defer { IOObjectRelease(iterator) }
        var vendors = Set<Int>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let vendor = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString,
                                                            kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                vendors.insert(vendor.intValue)
            }
            IOObjectRelease(service)
        }
        guard !vendors.isEmpty else { throw XCTSkip("no USB devices on this Mac to match against") }
        for vendor in vendors {
            XCTAssertGreaterThan(matches(TabletController.usbMatching(vendor: vendor)), 0,
                                 "vendor 0x\(String(vendor, radix: 16)) is plugged in and was not found")
        }
    }

    func testTheVendorIsAPropertyMatchOnTheUSBDevice() {
        let dictionary = TabletController.usbMatching()
        XCTAssertEqual(dictionary[kIOProviderClassKey] as? String, "IOUSBHostDevice")
        XCTAssertNil(dictionary["idVendor"], "a bare idVendor is the USB family's rule, and finds nothing alone")
        let property = dictionary[kIOPropertyMatchKey] as? [String: Int]
        XCTAssertEqual(property?["idVendor"], 0x056A)
    }
}
