import UIKit

struct ControlScrollStateSyncPolicy {
    struct AlternateViewportSyncState {
        let offsetX: CGFloat
        let offsetY: CGFloat
        let stickToRight: Bool
        let stickToBottom: Bool
        let isUserPanning: Bool?
    }

    struct Result {
        let isFollowingTail: Bool
        let isInteractingWithTerminalScroll: Bool
        let alternateViewportState: AlternateViewportSyncState?
    }

    static func didScroll(
        previousIsFollowingTail: Bool,
        isInteractingWithTerminalScroll: Bool,
        scrollView: UIScrollView,
        isAlternateScreenActive: Bool
    ) -> Result {
        let isFollowingTail: Bool
        if !isInteractingWithTerminalScroll {
            isFollowingTail = !hasVerticalOverflow(scrollView) || isNearBottom(scrollView)
        } else if !isNearBottom(scrollView) {
            isFollowingTail = false
        } else {
            isFollowingTail = previousIsFollowingTail
        }

        let alternateViewportState: AlternateViewportSyncState?
        if isAlternateScreenActive {
            alternateViewportState = AlternateViewportSyncState(
                offsetX: scrollView.contentOffset.x,
                offsetY: scrollView.contentOffset.y,
                stickToRight: isNearRight(scrollView),
                stickToBottom: isNearBottom(scrollView),
                isUserPanning: nil
            )
        } else {
            alternateViewportState = nil
        }

        return Result(
            isFollowingTail: isFollowingTail,
            isInteractingWithTerminalScroll: isInteractingWithTerminalScroll,
            alternateViewportState: alternateViewportState
        )
    }

    static func didEndInteraction(scrollView: UIScrollView, isAlternateScreenActive: Bool) -> Result {
        let isFollowingTail = !hasVerticalOverflow(scrollView) || isNearBottom(scrollView)
        let alternateViewportState: AlternateViewportSyncState? = isAlternateScreenActive
            ? AlternateViewportSyncState(
                offsetX: scrollView.contentOffset.x,
                offsetY: scrollView.contentOffset.y,
                stickToRight: isNearRight(scrollView),
                stickToBottom: isNearBottom(scrollView),
                isUserPanning: false
            )
            : nil

        return Result(
            isFollowingTail: isFollowingTail,
            isInteractingWithTerminalScroll: false,
            alternateViewportState: alternateViewportState
        )
    }

    private static func hasVerticalOverflow(_ scrollView: UIScrollView, threshold: CGFloat = 1) -> Bool {
        scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom >
            scrollView.bounds.height + threshold
    }

    private static func isNearBottom(_ scrollView: UIScrollView, threshold: CGFloat = 16) -> Bool {
        let maxOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        return scrollView.contentOffset.y >= (maxOffsetY - threshold)
    }

    private static func isNearRight(_ scrollView: UIScrollView, threshold: CGFloat = 16) -> Bool {
        let maxOffsetX = max(
            -scrollView.adjustedContentInset.left,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        return scrollView.contentOffset.x >= (maxOffsetX - threshold)
    }
}
