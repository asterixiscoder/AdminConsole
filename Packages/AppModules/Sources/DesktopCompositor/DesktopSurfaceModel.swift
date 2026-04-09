import DesktopDomain
import WindowManager

public struct DesktopSurfaceModel: Sendable {
    public var scale: Double

    public init(scale: Double) {
        self.scale = scale
    }

    public func normalizedFrame(for window: DesktopWindow) -> NormalizedRect {
        WindowManager.fit(window.frame)
    }
}
