import ConnectionKit
import DesktopDomain
import XCTest
import VNCKit

final class VNCRuntimeTests: XCTestCase {
    func testConnectPublishesConnectedSurface() async throws {
        let runtime = VNCRuntime(windowID: WindowID()) { _ in }
        let configuration = VNCSessionConfiguration(
            connection: ConnectionDescriptor(kind: .vnc, host: "demo.local", port: 5900, displayName: "demo.local"),
            password: "secret",
            qualityPreset: .balanced,
            isTrackpadModeEnabled: true
        )

        let didConnect = await runtime.connect(using: configuration)
        let snapshot = await runtime.snapshot()

        XCTAssertTrue(didConnect)
        XCTAssertEqual(snapshot.sessionState, .connected)
        XCTAssertEqual(snapshot.connectionTitle, "demo.local")
        XCTAssertTrue(snapshot.frame.renderedText.contains("Mock Remote Desktop"))
    }

    func testPointerInputAndKeyboardUpdateRecentEvents() async throws {
        let runtime = VNCRuntime(windowID: WindowID()) { _ in }
        let configuration = VNCSessionConfiguration(
            connection: ConnectionDescriptor(kind: .vnc, host: "ops.local", port: 5901, displayName: "ops.local"),
            qualityPreset: .low,
            isTrackpadModeEnabled: true
        )

        _ = await runtime.connect(using: configuration)
        await runtime.movePointer(deltaX: 0.10, deltaY: -0.05)
        await runtime.click()
        await runtime.send(text: "ls -la")
        await runtime.cycleQualityPreset()

        let snapshot = await runtime.snapshot()

        XCTAssertGreaterThan(snapshot.remotePointer.x, 0.32)
        XCTAssertTrue(snapshot.recentEvents.contains { $0.contains("click") })
        XCTAssertTrue(snapshot.recentEvents.contains { $0.contains("Typed") })
        XCTAssertEqual(snapshot.qualityPreset, VNCQualityPreset.balanced.rawValue)
    }
}
