@testable import VNCKit
import XCTest

final class RFBClientTests: XCTestCase {
    private let pixelFormat = RFBPixelFormat.clientPreferred

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

    func testVNCPointerButtonMasksMatchRFBSpec() {
        XCTAssertEqual(VNCRuntime.PointerButton.primary.mask, 1)
        XCTAssertEqual(VNCRuntime.PointerButton.middle.mask, 2)
        XCTAssertEqual(VNCRuntime.PointerButton.secondary.mask, 4)
    }

    func testVNCScrollDirectionMasksMatchRFBSpec() {
        XCTAssertEqual(VNCRuntime.ScrollDirection.up.mask, 8)
        XCTAssertEqual(VNCRuntime.ScrollDirection.down.mask, 16)
    }

    func testHextileDecoderAppliesBackgroundAndColoredSubrectangles() throws {
        var payload = Data([0x1E])
        payload.append(pixelBytes(0x101010FF))
        payload.append(pixelBytes(0x202020FF))
        payload.append(1)
        payload.append(pixelBytes(0xAA3300FF))
        payload.append(0x11)
        payload.append(0x11)

        let pixels = try RFBHextileDecoder.decodePixelsForTesting(
            payload: payload,
            pixelFormat: pixelFormat,
            width: 4,
            height: 4
        )

        XCTAssertEqual(pixels[0], 0x101010FF)
        XCTAssertEqual(pixels[5], 0xAA3300FF)
        XCTAssertEqual(pixels[6], 0xAA3300FF)
        XCTAssertEqual(pixels[9], 0xAA3300FF)
        XCTAssertEqual(pixels[10], 0xAA3300FF)
        XCTAssertEqual(pixels[15], 0x101010FF)
    }

    func testZRLEDecoderAppliesRawTile() throws {
        var payload = Data([0])
        payload.append(pixelBytes(0x112233FF))
        payload.append(pixelBytes(0x445566FF))
        payload.append(pixelBytes(0x778899FF))
        payload.append(pixelBytes(0xAABBCCFF))

        let pixels = try RFBZRLEDecoder.decodePixelsForTesting(
            payload: payload,
            pixelFormat: pixelFormat,
            width: 2,
            height: 2
        )

        XCTAssertEqual(pixels, [
            0x112233FF, 0x445566FF,
            0x778899FF, 0xAABBCCFF
        ])
    }

    func testZRLEDecoderAppliesPaletteRLETile() throws {
        var payload = Data([0x82])
        payload.append(pixelBytes(0x000000FF))
        payload.append(pixelBytes(0xFFFFFFFF))
        payload.append(0x80)
        payload.append(0x02)
        payload.append(0x01)

        let pixels = try RFBZRLEDecoder.decodePixelsForTesting(
            payload: payload,
            pixelFormat: pixelFormat,
            width: 2,
            height: 2
        )

        XCTAssertEqual(pixels, [
            0x000000FF, 0x000000FF,
            0x000000FF, 0xFFFFFFFF
        ])
    }

    private func pixelBytes(_ pixel: UInt32) -> Data {
        Data([
            UInt8((pixel >> 8) & 0xFF),
            UInt8((pixel >> 16) & 0xFF),
            UInt8((pixel >> 24) & 0xFF),
            0
        ])
    }
}
