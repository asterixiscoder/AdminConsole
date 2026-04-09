import DesktopDomain

public enum InputEvent: Sendable, Equatable {
    case key(String)
    case pointerMove(deltaX: Double, deltaY: Double)
    case pointerClick
    case scroll(deltaX: Double, deltaY: Double)
}

public struct InputRouter: Sendable {
    public init() {}

    public func route(_ event: InputEvent, focusedWindowID: WindowID?) -> WindowID? {
        focusedWindowID
    }
}
