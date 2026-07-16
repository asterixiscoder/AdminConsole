import UIKit

struct ControlAlternateViewportRestorationPolicy {
    static func targetOffset(
        previousOffset: CGPoint,
        forceTopLeft: Bool,
        hadHorizontalOverflowBeforeRender: Bool,
        hadVerticalOverflowBeforeRender: Bool,
        wasNearRightBeforeRender: Bool,
        wasNearBottomBeforeRender: Bool,
        isUserPanning: Bool,
        stickToRight: Bool,
        stickToBottom: Bool,
        minX: CGFloat,
        minY: CGFloat,
        maxX: CGFloat,
        maxY: CGFloat
    ) -> CGPoint {
        var targetX = min(max(previousOffset.x, minX), maxX)
        var targetY = min(max(previousOffset.y, minY), maxY)

        if forceTopLeft {
            targetX = minX
            targetY = minY
        } else if !isUserPanning {
            if stickToRight || (hadHorizontalOverflowBeforeRender && wasNearRightBeforeRender) {
                targetX = maxX
            }
            if stickToBottom || (hadVerticalOverflowBeforeRender && wasNearBottomBeforeRender) {
                targetY = maxY
            }
        }

        return CGPoint(x: targetX, y: targetY)
    }
}
