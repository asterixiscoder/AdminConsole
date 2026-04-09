import DesktopDomain
import Foundation
import WindowManager

public enum DesktopAction: Equatable, Sendable {
    case bootstrapPhaseZero
    case openWindow(DesktopWindowKind)
    case focusWindow(WindowID)
    case closeWindow(WindowID)
    case updateDisplayProfile(DisplayProfile)
    case setExternalDisplayConnected(Bool)
    case moveCursor(deltaX: Double, deltaY: Double)
    case noteInput(String)
}

public actor DesktopStore {
    private var snapshot: DesktopSnapshot
    private var subscriptions: [UUID: AsyncStream<DesktopSnapshot>.Continuation] = [:]

    public init(snapshot: DesktopSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func currentSnapshot() -> DesktopSnapshot {
        snapshot
    }

    public func snapshots() -> AsyncStream<DesktopSnapshot> {
        let identifier = UUID()

        return AsyncStream { continuation in
            subscriptions[identifier] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { _ in
                Task {
                    await self.removeSubscription(identifier)
                }
            }
        }
    }

    @discardableResult
    public func dispatch(_ action: DesktopAction) -> DesktopSnapshot {
        var next = snapshot

        switch action {
        case .bootstrapPhaseZero:
            guard next.windows.isEmpty else {
                return snapshot
            }

            let seededKinds: [DesktopWindowKind] = [.terminal, .files, .browser]
            next.windows = seededKinds.enumerated().map { index, kind in
                DesktopWindow(
                    kind: kind,
                    title: kind.rawValue.capitalized,
                    frame: WindowManager.defaultFrame(for: kind, index: index),
                    isFocused: index == seededKinds.count - 1
                )
            }
            next.focusedWindowID = next.windows.last?.id
        case let .openWindow(kind):
            let index = next.windows.count
            let window = DesktopWindow(
                kind: kind,
                title: kind.rawValue.capitalized,
                frame: WindowManager.defaultFrame(for: kind, index: index)
            )
            next.windows.append(window)
            next.focusedWindowID = window.id
            next.windows = next.windows.map { item in
                var updated = item
                updated.isFocused = updated.id == window.id
                return updated
            }
        case let .focusWindow(windowID):
            next.focusedWindowID = windowID
            next.windows = next.windows.map { item in
                var updated = item
                updated.isFocused = updated.id == windowID
                return updated
            }
        case let .closeWindow(windowID):
            next.windows.removeAll { $0.id == windowID }
            if next.focusedWindowID == windowID {
                next.focusedWindowID = next.windows.last?.id
            }
            next.windows = next.windows.map { item in
                var updated = item
                updated.isFocused = updated.id == next.focusedWindowID
                return updated
            }
        case let .updateDisplayProfile(profile):
            next.displayProfile = profile
            next.windows = next.windows.map { item in
                var updated = item
                updated.frame = WindowManager.fit(item.frame)
                return updated
            }
        case let .setExternalDisplayConnected(isConnected):
            next.isExternalDisplayConnected = isConnected
        case let .moveCursor(deltaX, deltaY):
            next.cursor = WindowManager.fit(
                CursorState(
                    x: next.cursor.x + deltaX,
                    y: next.cursor.y + deltaY
                )
            )
        case let .noteInput(description):
            next.lastInputDescription = description
        }

        next.revision += 1
        snapshot = next
        publish(snapshot)
        return next
    }

    private func publish(_ snapshot: DesktopSnapshot) {
        for continuation in subscriptions.values {
            continuation.yield(snapshot)
        }
    }

    private func removeSubscription(_ identifier: UUID) {
        subscriptions.removeValue(forKey: identifier)
    }
}
