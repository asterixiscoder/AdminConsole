import UIKit

enum ControlTerminalTypography {
    static let regularInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    static let compactInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

    static func targetInsets(isAlternateScreenActive: Bool) -> UIEdgeInsets {
        isAlternateScreenActive ? compactInsets : regularInsets
    }

    static func fittingPhoneMonospaceFontSize(
        bounds: CGSize,
        columns: Int,
        rows: Int,
        insets: UIEdgeInsets,
        baseFontSize: CGFloat,
        minimumFitFontSize: CGFloat
    ) -> CGFloat {
        guard bounds.width > 80, bounds.height > 120 else {
            return baseFontSize
        }

        let usableWidth = max(1, bounds.width - insets.left - insets.right)
        let usableHeight = max(1, bounds.height - insets.top - insets.bottom)
        var size = baseFontSize
        while size >= minimumFitFontSize {
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let glyphWidth = measuredMonospaceGlyphWidth(for: font)
            let requiredWidth = glyphWidth * CGFloat(columns)
            let requiredHeight = font.lineHeight * CGFloat(rows)
            if requiredWidth <= usableWidth && requiredHeight <= usableHeight {
                return size
            }
            size -= 0.5
        }
        return minimumFitFontSize
    }

    static func measuredMonospaceGlyphWidth(for font: UIFont) -> CGFloat {
        let sampleCount = 64
        let sample = String(repeating: "M", count: sampleCount)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        let perGlyph = sampleWidth / CGFloat(sampleCount)
        return perGlyph.isFinite ? perGlyph : 6.0
    }
}
