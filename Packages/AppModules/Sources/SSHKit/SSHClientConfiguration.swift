import ConnectionKit
import DesktopDomain

public struct SSHClientConfiguration: Sendable, Equatable {
    public var connection: ConnectionDescriptor
    public var username: String

    public init(connection: ConnectionDescriptor, username: String) {
        self.connection = connection
        self.username = username
    }
}

public enum SSHSessionState: String, Sendable {
    case idle
    case connecting
    case connected
    case failed
}
