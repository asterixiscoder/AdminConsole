import DesktopDomain
import Foundation
import WindowManager

public enum DesktopAction: Equatable, Sendable {
    case bootstrapPhaseZero
    case openWindow(DesktopWindowKind)
    case focusWindow(WindowID)
    case closeWindow(WindowID)
    case toggleWindowMaximized(WindowID)
    case updateWindowFrame(windowID: WindowID, frame: NormalizedRect)
    case updateTerminalSurface(windowID: WindowID, surface: TerminalSurfaceState)
    case updateFilesSurface(windowID: WindowID, surface: FilesSurfaceState)
    case updateBrowserSurface(windowID: WindowID, surface: BrowserSurfaceState)
    case updateVNCSurface(windowID: WindowID, surface: VNCSurfaceState)
    case updateDisplayProfile(DisplayProfile)
    case setExternalDisplayConnected(Bool)
    case setInputCaptureMode(DesktopInputCaptureMode)
    case setActiveWorkMode(DesktopWorkMode)
    case setMirrorMode(DesktopMirrorMode)
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
                makeWindow(
                    kind: kind,
                    index: index,
                    isFocused: index == seededKinds.count - 1
                )
            }
            next.focusedWindowID = next.windows.last?.id
        case let .openWindow(kind):
            let index = next.windows.count
            let window = makeWindow(kind: kind, index: index)
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
        case let .toggleWindowMaximized(windowID):
            next.windows = next.windows.map { item in
                guard item.id == windowID else {
                    return item
                }

                var updated = item
                if updated.isMaximized {
                    updated.frame = WindowManager.fit(updated.restoredFrame ?? WindowManager.defaultFrame(for: updated.kind, index: 0))
                    updated.restoredFrame = nil
                    updated.isMaximized = false
                } else {
                    updated.restoredFrame = WindowManager.fit(updated.frame)
                    updated.frame = WindowManager.maximizedFrame()
                    updated.isMaximized = true
                }
                return updated
            }
        case let .updateWindowFrame(windowID, frame):
            next.windows = next.windows.map { item in
                guard item.id == windowID else {
                    return item
                }

                var updated = item
                updated.frame = WindowManager.fit(frame)
                updated.isMaximized = false
                updated.restoredFrame = nil
                return updated
            }
        case let .updateTerminalSurface(windowID, surface):
            next.windows = next.windows.map { item in
                guard item.id == windowID, item.kind == .terminal else {
                    return item
                }

                var updated = item
                updated.terminalState = surface
                updated.title = surface.displayTitle
                return updated
            }
        case let .updateFilesSurface(windowID, surface):
            next.windows = next.windows.map { item in
                guard item.id == windowID, item.kind == .files else {
                    return item
                }

                var updated = item
                updated.filesState = surface
                updated.title = surface.displayTitle
                return updated
            }
        case let .updateVNCSurface(windowID, surface):
            next.windows = next.windows.map { item in
                guard item.id == windowID, item.kind == .vnc else {
                    return item
                }

                var updated = item
                updated.vncState = surface
                updated.title = surface.displayTitle
                return updated
            }
        case let .updateBrowserSurface(windowID, surface):
            next.windows = next.windows.map { item in
                guard item.id == windowID, item.kind == .browser else {
                    return item
                }

                var updated = item
                updated.browserState = surface
                updated.title = surface.displayTitle
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
        case let .setInputCaptureMode(mode):
            next.inputCaptureMode = mode
        case let .setActiveWorkMode(mode):
            next.activeWorkMode = mode

            if let target = next.windows.last(where: { $0.kind == mode.windowKind }) {
                next.focusedWindowID = target.id
                next.windows = next.windows.map { item in
                    var updated = item
                    updated.isFocused = updated.id == target.id
                    return updated
                }
            }
        case let .setMirrorMode(mode):
            next.mirrorMode = mode
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

        guard next != snapshot else {
            return snapshot
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

    private func makeWindow(
        kind: DesktopWindowKind,
        index: Int,
        isFocused: Bool = false
    ) -> DesktopWindow {
        DesktopWindow(
            kind: kind,
            title: defaultTitle(for: kind),
            frame: WindowManager.defaultFrame(for: kind, index: index),
            isFocused: isFocused,
            terminalState: kind == .terminal ? .idle(title: defaultTitle(for: kind)) : nil,
            filesState: kind == .files ? .idle(workspaceName: defaultTitle(for: kind)) : nil,
            browserState: kind == .browser ? .idle() : nil,
            vncState: kind == .vnc ? .idle(title: defaultTitle(for: kind)) : nil
        )
    }

    private func defaultTitle(for kind: DesktopWindowKind) -> String {
        switch kind {
        case .terminal:
            return "Terminal"
        case .files:
            return "Files"
        case .browser:
            return "Browser"
        case .vnc:
            return "VNC"
        }
    }
}
