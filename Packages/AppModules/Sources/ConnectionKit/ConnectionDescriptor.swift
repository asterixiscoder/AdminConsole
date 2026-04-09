import DesktopDomain
import Foundation

public struct ConnectionID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }
}

public enum ConnectionKind: String, Codable, Sendable {
    case ssh
    case vnc
}

public struct ConnectionDescriptor: Codable, Equatable, Sendable {
    public var id: ConnectionID
    public var kind: ConnectionKind
    public var host: String
    public var port: Int
    public var displayName: String

    public init(
        id: ConnectionID = ConnectionID(),
        kind: ConnectionKind,
        host: String,
        port: Int,
        displayName: String
    ) {
        self.id = id
        self.kind = kind
        self.host = host
        self.port = port
        self.displayName = displayName
    }
}
