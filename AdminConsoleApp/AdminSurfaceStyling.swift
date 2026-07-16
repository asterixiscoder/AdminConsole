import UIKit

@inline(__always)
func styleRoundedSurface(_ view: UIView, cornerRadius: CGFloat) {
    view.layer.cornerRadius = cornerRadius
}
