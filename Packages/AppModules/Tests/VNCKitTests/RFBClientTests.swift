@testable import VNCKit
import XCTest

final class RFBClientTests: XCTestCase {
    func testKeySymbolTranslatorMapsSpecialSequences() {
        XCTAssertEqual(RFBKeySymbolTranslator.keySymbols(for: "\u{001B}[A"), [0xFF52])
        XCTAssertEqual(RFBKeySymbolTranslator.keySymbols(for: "\n"), [0xFF0D])
        XCTAssertEqual(RFBKeySymbolTranslator.keySymbols(for: "\t"), [0xFF09])
        XCTAssertEqual(RFBKeySymbolTranslator.keySymbols(for: "\u{7F}"), [0xFF08])
        XCTAssertEqual(RFBKeySymbolTranslator.keySymbols(for: "A"), [65])
    }

    func testPixelFormatDecodesLittleEndianTrueColor() {
        let format = RFBPixelFormat(
            bitsPerPixel: 32,
            depth: 24,
            isBigEndian: false,
            isTrueColor: true,
            redMax: 255,
            greenMax: 255,
            blueMax: 255,
            redShift: 16,
            greenShift: 8,
            blueShift: 0
        )

        let bytes: [UInt8] = [0x33, 0x22, 0x11, 0x00]
        let pixel = bytes.withUnsafeBufferPointer { buffer in
            format.decodePixel(bytes: buffer)
        }

        XCTAssertEqual(pixel, 0x112233FF)
    }

    func testVNCAuthenticationBuildsBitReversedDESKey() {
        let key = VNCAuthentication.makeDESKey(from: "COW")

        XCTAssertEqual(Array(key), [0xC2, 0xF2, 0xEA, 0, 0, 0, 0, 0])
    }
}
