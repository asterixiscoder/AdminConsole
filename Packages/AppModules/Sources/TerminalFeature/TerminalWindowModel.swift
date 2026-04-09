import DesktopDomain
import SSHKit

public struct TerminalWindowModel: Sendable, Equatable {
    public var window: DesktopWindow
    public var sessionState: SSHSessionState

    public init(window: DesktopWindow, sessionState: SSHSessionState = .idle) {
        self.window = window
        self.sessionState = sessionState
    }
}
