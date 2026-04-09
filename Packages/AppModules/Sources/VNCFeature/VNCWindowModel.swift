import DesktopDomain
import VNCKit

public struct VNCWindowModel: Sendable, Equatable {
    public var window: DesktopWindow
    public var qualityPreset: VNCQualityPreset

    public init(window: DesktopWindow, qualityPreset: VNCQualityPreset = .balanced) {
        self.window = window
        self.qualityPreset = qualityPreset
    }
}
