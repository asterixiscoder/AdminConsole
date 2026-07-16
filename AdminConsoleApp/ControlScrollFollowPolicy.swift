import UIKit

struct ControlScrollFollowPolicy {
    static func shouldStickToBottomDuringRender(
        previousOffsetY: CGFloat,
        isFollowingTail: Bool,
        isAlternateScreenActive: Bool,
        contentSizeHeight: CGFloat,
        boundsHeight: CGFloat,
        adjustedContentInsetTop: CGFloat,
        adjustedContentInsetBottom: CGFloat,
        threshold: CGFloat = 20
    ) -> Bool {
        if isAlternateScreenActive {
            return false
        }
        if isFollowingTail {
            return true
        }
        let maxOffsetY = max(
            -adjustedContentInsetTop,
            contentSizeHeight - boundsHeight + adjustedContentInsetBottom
        )
        return previousOffsetY >= (maxOffsetY - threshold)
    }
}
