import ConnectionKit
import DesktopDomain

public struct VNCSessionConfiguration: Sendable, Equatable {
    public var connection: ConnectionDescriptor
    public var isTrackpadModeEnabled: Bool

    public init(connection: ConnectionDescriptor, isTrackpadModeEnabled: Bool = true) {
        self.connection = connection
        self.isTrackpadModeEnabled = isTrackpadModeEnabled
    }
}

public enum VNCQualityPreset: String, Sendable {
    case low
    case balanced
    case high
}
