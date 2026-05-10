import XCTest
import DesktopDomain

final class RenderProfileResolverTests: XCTestCase {
    func testResolvePhoneOnlyProfileUsesPhoneRole() {
        let phone = TerminalRenderProfileResolver.SurfaceBounds(widthPoints: 393, heightPoints: 852, scale: 3)

        let profile = TerminalRenderProfileResolver.resolveRenderProfile(
            phoneBounds: phone,
            externalBounds: nil,
            isAlternateScreen: true
        )

        XCTAssertEqual(profile.role, .phoneStandalone)
        XCTAssertGreaterThanOrEqual(profile.columns, 80)
        XCTAssertGreaterThanOrEqual(profile.rows, 24)
    }

    func testPhoneOnlyAlternateGridStaysPhoneBounded() {
        let phone = TerminalRenderProfileResolver.SurfaceBounds(widthPoints: 393, heightPoints: 560, scale: 3)

        let profile = TerminalRenderProfileResolver.resolveRenderProfile(
            phoneBounds: phone,
            externalBounds: nil,
            isAlternateScreen: true
        )

        XCTAssertEqual(profile.role, .phoneStandalone)
        XCTAssertLessThanOrEqual(profile.columns, 160)
        XCTAssertLessThanOrEqual(profile.rows, 120)
        XCTAssertEqual(profile.pixelWidth, 1179)
        XCTAssertEqual(profile.pixelHeight, 1680)
    }

    func testResolveExternalProfileWinsWhenConnected() {
        let phone = TerminalRenderProfileResolver.SurfaceBounds(widthPoints: 393, heightPoints: 852, scale: 3)
        let external = TerminalRenderProfileResolver.SurfaceBounds(widthPoints: 960, heightPoints: 540, scale: 2)

        let profile = TerminalRenderProfileResolver.resolveRenderProfile(
            phoneBounds: phone,
            externalBounds: external,
            isAlternateScreen: true
        )

        XCTAssertEqual(profile.role, .externalPrimary)
        XCTAssertEqual(profile.pixelWidth, 1920)
        XCTAssertEqual(profile.pixelHeight, 1080)
        XCTAssertGreaterThanOrEqual(profile.columns, 80)
        XCTAssertGreaterThanOrEqual(profile.rows, 24)
    }

    func testResolveExternalFallbackUsesFullHDWhenBoundsMissing() {
        let profile = TerminalRenderProfileResolver.externalProfile(from: nil, isAlternateScreen: true)

        XCTAssertEqual(profile.role, .externalPrimary)
        XCTAssertEqual(profile.pixelWidth, 1920)
        XCTAssertEqual(profile.pixelHeight, 1080)
        XCTAssertEqual(profile.columns, 240)
        XCTAssertEqual(profile.rows, 67)
    }

    func testPhoneCompanionInheritsCanonicalGrid() {
        let phone = TerminalRenderProfileResolver.SurfaceBounds(widthPoints: 393, heightPoints: 852, scale: 3)
        let externalCanonical = TerminalRenderProfile(
            role: .externalPrimary,
            columns: 220,
            rows: 60,
            pixelWidth: 1760,
            pixelHeight: 960
        )

        let companion = TerminalRenderProfileResolver.resolvePhoneCompanionProfile(
            phoneBounds: phone,
            canonicalExternalProfile: externalCanonical
        )

        XCTAssertEqual(companion.role, .phoneCompanion)
        XCTAssertEqual(companion.columns, 220)
        XCTAssertEqual(companion.rows, 60)
        XCTAssertEqual(companion.pixelWidth, phone.pixelWidth)
        XCTAssertEqual(companion.pixelHeight, phone.pixelHeight)
    }
}
