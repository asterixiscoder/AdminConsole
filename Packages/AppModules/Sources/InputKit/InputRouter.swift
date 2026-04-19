import CoreGraphics
import DesktopDomain

public enum InputEvent: Sendable, Equatable {
    case key(String)
    case pointerMove(deltaX: Double, deltaY: Double)
    case pointerClick
    case scroll(deltaX: Double, deltaY: Double)
}

public enum PointerInputSource: String, Sendable, Equatable {
    case touchTrackpad
    case hardwarePointer
    case keyboard
}

public struct PointerMotionInput: Sendable, Equatable {
    public var translationX: Double
    public var translationY: Double
    public var surfaceWidth: Double
    public var surfaceHeight: Double
    public var source: PointerInputSource

    public init(
        translationX: Double,
        translationY: Double,
        surfaceWidth: Double,
        surfaceHeight: Double,
        source: PointerInputSource
    ) {
        self.translationX = translationX
        self.translationY = translationY
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
        self.source = source
    }
}

public struct RoutedPointerMotion: Sendable, Equatable {
    public var cursorDeltaX: Double
    public var cursorDeltaY: Double
    public var shouldForwardToVNC: Bool
    public var forwardedVNCDeltaX: Double
    public var forwardedVNCDeltaY: Double

    public init(
        cursorDeltaX: Double,
        cursorDeltaY: Double,
        shouldForwardToVNC: Bool,
        forwardedVNCDeltaX: Double,
        forwardedVNCDeltaY: Double
    ) {
        self.cursorDeltaX = cursorDeltaX
        self.cursorDeltaY = cursorDeltaY
        self.shouldForwardToVNC = shouldForwardToVNC
        self.forwardedVNCDeltaX = forwardedVNCDeltaX
        self.forwardedVNCDeltaY = forwardedVNCDeltaY
    }
}

public struct RoutedKeyboardInput: Sendable, Equatable {
    public var routeToTerminal: Bool
    public var routeToVNC: Bool

    public init(routeToTerminal: Bool, routeToVNC: Bool) {
        self.routeToTerminal = routeToTerminal
        self.routeToVNC = routeToVNC
    }
}

public struct InputRouter: Sendable {
    public init() {}

    public func route(_ event: InputEvent, focusedWindowID: WindowID?) -> WindowID? {
        focusedWindowID
    }

    public func routePointerMotion(
        _ input: PointerMotionInput,
        focusedWindow: DesktopWindow?,
        captureMode: DesktopInputCaptureMode
    ) -> RoutedPointerMotion {
        let width = max(1.0, input.surfaceWidth)
        let height = max(1.0, input.surfaceHeight)

        let normalizedX = input.translationX / width
        let normalizedY = input.translationY / height

        let pointsDistance = hypot(input.translationX, input.translationY)
        let acceleration = accelerationMultiplier(for: pointsDistance)
        let sourceGain = gain(for: input.source)

        let cursorDeltaX = clamp(normalizedX * acceleration * sourceGain, lower: -0.18, upper: 0.18)
        let cursorDeltaY = clamp(normalizedY * acceleration * sourceGain, lower: -0.18, upper: 0.18)

        let isFocusedVNCConnected = focusedWindow?.kind == .vnc && focusedWindow?.vncState?.sessionState == .connected
        let shouldForward: Bool
        switch captureMode {
        case .automatic:
            shouldForward = isFocusedVNCConnected
        case .terminal:
            shouldForward = false
        case .vnc:
            shouldForward = true
        }

        // VNC pointer motion should be slightly more sensitive than local cursor to feel direct.
        let vncGain = 1.28
        let forwardedX = shouldForward ? cursorDeltaX * vncGain : 0
        let forwardedY = shouldForward ? cursorDeltaY * vncGain : 0

        return RoutedPointerMotion(
            cursorDeltaX: cursorDeltaX,
            cursorDeltaY: cursorDeltaY,
            shouldForwardToVNC: shouldForward,
            forwardedVNCDeltaX: forwardedX,
            forwardedVNCDeltaY: forwardedY
        )
    }

    public func routeKeyboardInput(
        focusedWindow: DesktopWindow?,
        captureMode: DesktopInputCaptureMode
    ) -> RoutedKeyboardInput {
        let kind: DesktopWindowKind?
        switch captureMode {
        case .automatic:
            kind = focusedWindow?.kind
        case .terminal:
            kind = .terminal
        case .vnc:
            kind = .vnc
        }

        return RoutedKeyboardInput(
            routeToTerminal: kind == .terminal && focusedWindow?.terminalState?.sessionState == .connected,
            routeToVNC: kind == .vnc && focusedWindow?.vncState?.sessionState == .connected
        )
    }

    private func gain(for source: PointerInputSource) -> Double {
        switch source {
        case .touchTrackpad:
            return 1.18
        case .hardwarePointer:
            return 0.95
        case .keyboard:
            return 0.72
        }
    }

    private func accelerationMultiplier(for pointsDistance: Double) -> Double {
        guard pointsDistance > 0 else {
            return 1.0
        }

        let normalized = min(1.0, pointsDistance / 38.0)
        return 1.0 + pow(normalized, 1.35) * 1.55
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
