import ConnectionKit
import DesktopDomain

public struct TerminalSize: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        columns: Int = 120,
        rows: Int = 32,
        pixelWidth: Int = 1440,
        pixelHeight: Int = 900
    ) {
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct SSHConnectionConfiguration: Sendable, Equatable {
    public var connection: ConnectionDescriptor
    public var username: String
    public var password: String
    public var terminalType: String
    public var terminalSize: TerminalSize

    public init(
        connection: ConnectionDescriptor,
        username: String,
        password: String,
        terminalType: String = "xterm-256color",
        terminalSize: TerminalSize = TerminalSize()
    ) {
        self.connection = connection
        self.username = username
        self.password = password
        self.terminalType = terminalType
        self.terminalSize = terminalSize
    }

    public var connectionSummary: String {
        "\(username)@\(connection.host):\(connection.port)"
    }
}

public enum SSHSessionState: String, Sendable, Equatable {
    case idle
    case connecting
    case connected
    case failed
}
