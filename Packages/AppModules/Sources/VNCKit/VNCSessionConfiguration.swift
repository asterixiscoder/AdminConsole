import ConnectionKit
import DesktopDomain

public struct VNCSessionConfiguration: Sendable, Equatable {
    public var connection: ConnectionDescriptor
    public var password: String
    public var qualityPreset: VNCQualityPreset
    public var isTrackpadModeEnabled: Bool

    public init(
        connection: ConnectionDescriptor,
        password: String = "",
        qualityPreset: VNCQualityPreset = .balanced,
        isTrackpadModeEnabled: Bool = true
    ) {
        self.connection = connection
        self.password = password
        self.qualityPreset = qualityPreset
        self.isTrackpadModeEnabled = isTrackpadModeEnabled
    }
}

public enum VNCQualityPreset: String, Sendable {
    case low
    case balanced
    case high
}
