import CoreGraphics
import DesktopDomain

public struct TerminalViewportInsets: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = TerminalViewportInsets()
}

public struct TerminalSelectionGeometry: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var viewportSize: CGSize
    public var insets: TerminalViewportInsets

    public init(
        columns: Int,
        rows: Int,
        viewportSize: CGSize,
        insets: TerminalViewportInsets = .zero
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.viewportSize = viewportSize
        self.insets = insets
    }

    public func gridPoint(for point: CGPoint) -> TerminalGridPoint {
        let contentWidth = max(1, viewportSize.width - insets.left - insets.right)
        let contentHeight = max(1, viewportSize.height - insets.top - insets.bottom)
        let columnWidth = max(1, contentWidth / CGFloat(columns))
        let rowHeight = max(1, contentHeight / CGFloat(rows))

        let normalizedX = min(max(point.x - insets.left, 0), contentWidth - 1)
        let normalizedY = min(max(point.y - insets.top, 0), contentHeight - 1)

        return TerminalGridPoint(
            row: min(rows - 1, max(0, Int(floor(normalizedY / rowHeight)))),
            column: min(columns - 1, max(0, Int(floor(normalizedX / columnWidth))))
        )
    }

    public func selection(from startPoint: CGPoint, to endPoint: CGPoint) -> TerminalSelection {
        TerminalSelection(
            anchor: gridPoint(for: startPoint),
            focus: gridPoint(for: endPoint)
        )
    }
}
