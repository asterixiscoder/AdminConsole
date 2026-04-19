import DesktopDomain

public enum WindowManager {
    public static func fit(_ frame: NormalizedRect) -> NormalizedRect {
        NormalizedRect(
            x: clamp(frame.x, lower: 0.0, upper: 0.95),
            y: clamp(frame.y, lower: 0.0, upper: 0.95),
            width: clamp(frame.width, lower: 0.20, upper: 1.0),
            height: clamp(frame.height, lower: 0.20, upper: 1.0)
        )
    }

    public static func defaultFrame(
        for kind: DesktopWindowKind,
        index: Int
    ) -> NormalizedRect {
        let base: NormalizedRect

        switch kind {
        case .terminal:
            base = NormalizedRect(x: 0.05, y: 0.14, width: 0.42, height: 0.36)
        case .files:
            base = NormalizedRect(x: 0.51, y: 0.18, width: 0.32, height: 0.34)
        case .browser:
            base = NormalizedRect(x: 0.18, y: 0.56, width: 0.48, height: 0.30)
        case .vnc:
            base = NormalizedRect(x: 0.35, y: 0.16, width: 0.50, height: 0.48)
        }

        let offset = Double(index % 4) * 0.03
        return fit(
            NormalizedRect(
                x: base.x + offset,
                y: base.y + offset,
                width: base.width,
                height: base.height
            )
        )
    }

    public static func maximizedFrame() -> NormalizedRect {
        NormalizedRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
    }

    public static func fit(_ cursor: CursorState) -> CursorState {
        CursorState(
            x: clamp(cursor.x, lower: 0.0, upper: 1.0),
            y: clamp(cursor.y, lower: 0.0, upper: 1.0)
        )
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
