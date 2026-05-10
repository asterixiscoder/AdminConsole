import Foundation

public enum TerminalDisplayRole: Sendable, Equatable {
    case phoneStandalone
    case externalPrimary
    case phoneCompanion
}

public struct TerminalRenderProfile: Sendable, Equatable {
    public var role: TerminalDisplayRole
    public var columns: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        role: TerminalDisplayRole,
        columns: Int,
        rows: Int,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.role = role
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct TerminalRenderProfileResolver {
    public struct SurfaceBounds: Sendable, Equatable {
        public var widthPoints: Double
        public var heightPoints: Double
        public var scale: Double

        public init(widthPoints: Double, heightPoints: Double, scale: Double) {
            self.widthPoints = widthPoints
            self.heightPoints = heightPoints
            self.scale = scale
        }

        public var pixelWidth: Int {
            max(1, Int((max(1, widthPoints) * max(0.5, scale)).rounded()))
        }

        public var pixelHeight: Int {
            max(1, Int((max(1, heightPoints) * max(0.5, scale)).rounded()))
        }
    }

    public static let fallbackExternalPixels = (width: 1920, height: 1080)

    public init() {}

    public static func resolveRenderProfile(
        phoneBounds: SurfaceBounds,
        externalBounds: SurfaceBounds?,
        isAlternateScreen: Bool
    ) -> TerminalRenderProfile {
        if let externalBounds {
            let external = externalProfile(from: externalBounds, isAlternateScreen: isAlternateScreen)
            return external
        }

        return phoneStandaloneProfile(from: phoneBounds, isAlternateScreen: isAlternateScreen)
    }

    public static func resolvePhoneCompanionProfile(
        phoneBounds: SurfaceBounds,
        canonicalExternalProfile: TerminalRenderProfile
    ) -> TerminalRenderProfile {
        TerminalRenderProfile(
            role: .phoneCompanion,
            columns: canonicalExternalProfile.columns,
            rows: canonicalExternalProfile.rows,
            pixelWidth: phoneBounds.pixelWidth,
            pixelHeight: phoneBounds.pixelHeight
        )
    }

    public static func externalProfile(
        from bounds: SurfaceBounds?,
        isAlternateScreen: Bool
    ) -> TerminalRenderProfile {
        let pixelWidth: Int
        let pixelHeight: Int

        if let bounds {
            pixelWidth = bounds.pixelWidth
            pixelHeight = bounds.pixelHeight
        } else {
            pixelWidth = fallbackExternalPixels.width
            pixelHeight = fallbackExternalPixels.height
        }

        let minColumns = isAlternateScreen ? 80 : 40
        let minRows = isAlternateScreen ? 24 : 18
        let maxColumns = isAlternateScreen ? 320 : 160
        let maxRows = isAlternateScreen ? 160 : 120

        let cols = min(maxColumns, max(minColumns, Int(floor(Double(pixelWidth) / 8.0))))
        let rows = min(maxRows, max(minRows, Int(floor(Double(pixelHeight) / 16.0))))

        return TerminalRenderProfile(
            role: .externalPrimary,
            columns: cols,
            rows: rows,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private static func phoneStandaloneProfile(
        from bounds: SurfaceBounds,
        isAlternateScreen: Bool
    ) -> TerminalRenderProfile {
        let minColumns = isAlternateScreen ? 80 : 40
        let minRows = isAlternateScreen ? 24 : 18
        let maxColumns = isAlternateScreen ? 160 : 160
        let maxRows = isAlternateScreen ? 120 : 120

        let columns = min(maxColumns, max(minColumns, Int(floor(max(1, bounds.widthPoints) / 7.2))))
        let rows = min(maxRows, max(minRows, Int(floor(max(1, bounds.heightPoints) / 16.0))))

        return TerminalRenderProfile(
            role: .phoneStandalone,
            columns: columns,
            rows: rows,
            pixelWidth: bounds.pixelWidth,
            pixelHeight: bounds.pixelHeight
        )
    }
}
