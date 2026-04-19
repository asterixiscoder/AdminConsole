import DesktopDomain
import InputKit
import XCTest

final class InputRouterTests: XCTestCase {
    func testRoutePointerMotionAutomaticModeForwardsToConnectedVNC() {
        let router = InputRouter()
        let focusedWindow = DesktopWindow(
            kind: .vnc,
            title: "VNC",
            isFocused: true,
            vncState: .idle(title: "VNC")
        )

        let routed = router.routePointerMotion(
            PointerMotionInput(
                translationX: 24,
                translationY: -12,
                surfaceWidth: 300,
                surfaceHeight: 200,
                source: .touchTrackpad
            ),
            focusedWindow: focusedWindowWithConnectedVNC(focusedWindow),
            captureMode: .automatic
        )

        XCTAssertTrue(routed.shouldForwardToVNC)
        XCTAssertNotEqual(routed.forwardedVNCDeltaX, 0)
        XCTAssertNotEqual(routed.forwardedVNCDeltaY, 0)
    }

    func testRoutePointerMotionTerminalModeDoesNotForwardToVNC() {
        let router = InputRouter()
        let focusedWindow = DesktopWindow(
            kind: .vnc,
            title: "VNC",
            isFocused: true,
            vncState: connectedVNCState()
        )

        let routed = router.routePointerMotion(
            PointerMotionInput(
                translationX: 18,
                translationY: 8,
                surfaceWidth: 320,
                surfaceHeight: 220,
                source: .touchTrackpad
            ),
            focusedWindow: focusedWindow,
            captureMode: .terminal
        )

        XCTAssertFalse(routed.shouldForwardToVNC)
        XCTAssertEqual(routed.forwardedVNCDeltaX, 0)
        XCTAssertEqual(routed.forwardedVNCDeltaY, 0)
        XCTAssertNotEqual(routed.cursorDeltaX, 0)
    }

    func testRouteKeyboardInputTargetsTerminalWhenCaptureIsTerminal() {
        let router = InputRouter()
        var terminalState = TerminalSurfaceState.idle(title: "SSH")
        terminalState.sessionState = TerminalConnectionState.connected

        let focusedWindow = DesktopWindow(
            kind: .terminal,
            title: "Terminal",
            isFocused: true,
            terminalState: terminalState
        )

        let routed = router.routeKeyboardInput(
            focusedWindow: focusedWindow,
            captureMode: .terminal
        )

        XCTAssertTrue(routed.routeToTerminal)
        XCTAssertFalse(routed.routeToVNC)
    }

    func testRouteKeyboardInputTargetsVNCWhenCaptureIsVNC() {
        let router = InputRouter()
        let focusedWindow = DesktopWindow(
            kind: .vnc,
            title: "VNC",
            isFocused: true,
            vncState: connectedVNCState()
        )

        let routed = router.routeKeyboardInput(
            focusedWindow: focusedWindow,
            captureMode: .vnc
        )

        XCTAssertFalse(routed.routeToTerminal)
        XCTAssertTrue(routed.routeToVNC)
    }

    private func focusedWindowWithConnectedVNC(_ window: DesktopWindow) -> DesktopWindow {
        var result = window
        result.vncState = connectedVNCState()
        return result
    }

    private func connectedVNCState() -> VNCSurfaceState {
        var state = VNCSurfaceState.idle(title: "VNC")
        state.sessionState = .connected
        state.statusMessage = "Connected"
        return state
    }
}
