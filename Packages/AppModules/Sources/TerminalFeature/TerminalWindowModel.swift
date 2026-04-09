import DesktopDomain

public struct TerminalWindowModel: Sendable, Equatable {
    public var window: DesktopWindow
    public var terminalState: TerminalSurfaceState

    public init(window: DesktopWindow, terminalState: TerminalSurfaceState? = nil) {
        self.window = window
        self.terminalState = terminalState ?? window.terminalState ?? .idle()
    }
}
