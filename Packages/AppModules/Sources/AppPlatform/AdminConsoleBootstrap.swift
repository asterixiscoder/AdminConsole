import DesktopCompositor
import DesktopDomain
import DesktopStore
import Foundation
import InputKit
import PersistenceKit
import RuntimeRegistry
import SecurityKit
import TelemetryKit
import WindowManager
import CoreGraphics

public struct AdminConsoleBootstrap: Sendable {
    public let store: DesktopStore
    public let runtimes: RuntimeRegistry
    public let persistence: WorkspacePersistence
    public let inputRouter: InputRouter
    public let compositor: DesktopSurfaceModel
    public let logger: Logger

    public init(
        store: DesktopStore = DesktopStore(),
        runtimes: RuntimeRegistry = RuntimeRegistry(),
        persistence: WorkspacePersistence = InMemoryWorkspacePersistence(),
        inputRouter: InputRouter = InputRouter(),
        compositor: DesktopSurfaceModel = .init(scale: 1.0),
        logger: Logger = Logger(subsystem: "AppPlatform")
    ) {
        self.store = store
        self.runtimes = runtimes
        self.persistence = persistence
        self.inputRouter = inputRouter
        self.compositor = compositor
        self.logger = logger
    }
}

public typealias PhaseZeroSnapshot = DesktopSnapshot
public typealias PhaseZeroWindow = DesktopWindow
public typealias PhaseZeroWindowID = WindowID
public typealias PhaseZeroWindowKind = DesktopWindowKind
public typealias PhaseZeroRect = NormalizedRect

public actor PhaseZeroCoordinator {
    private let bootstrap: AdminConsoleBootstrap
    private var didStart = false

    public init(bootstrap: AdminConsoleBootstrap = AdminConsoleBootstrap()) {
        self.bootstrap = bootstrap
    }

    public func startIfNeeded() async {
        guard !didStart else {
            return
        }

        didStart = true
        _ = await bootstrap.store.dispatch(.bootstrapPhaseZero)
        bootstrap.logger.log("Phase 0 bootstrap started")
    }

    public func snapshots() async -> AsyncStream<PhaseZeroSnapshot> {
        await bootstrap.store.snapshots()
    }

    public func currentSnapshot() async -> PhaseZeroSnapshot {
        await bootstrap.store.currentSnapshot()
    }

    public func openWindow(_ kind: PhaseZeroWindowKind) async {
        let previous = await bootstrap.store.currentSnapshot()
        let next = await bootstrap.store.dispatch(.openWindow(kind))

        if next.windows.count > previous.windows.count, let window = next.windows.last {
            _ = await bootstrap.runtimes.register(kind: runtimeKind(for: kind), for: window.id)
        }
    }

    public func focusWindow(_ id: PhaseZeroWindowID) async {
        _ = await bootstrap.store.dispatch(.focusWindow(id))
    }

    public func moveCursor(deltaX: Double, deltaY: Double) async {
        _ = await bootstrap.store.dispatch(.moveCursor(deltaX: deltaX, deltaY: deltaY))
    }

    public func noteInput(_ description: String) async {
        _ = await bootstrap.store.dispatch(.noteInput(description))
    }

    public func setExternalDisplayConnected(
        _ isConnected: Bool,
        size: CGSize? = nil,
        scale: Double? = nil
    ) async {
        if let size {
            let profile = DisplayProfile(
                width: size.width,
                height: size.height,
                scale: scale ?? 1.0
            )
            _ = await bootstrap.store.dispatch(.updateDisplayProfile(profile))
        }

        _ = await bootstrap.store.dispatch(.setExternalDisplayConnected(isConnected))
        bootstrap.logger.log("External display connected: \(isConnected)")
    }

    public func registerControlInput(_ description: String) async {
        _ = await bootstrap.store.dispatch(.noteInput(description))
    }

    private func runtimeKind(for kind: PhaseZeroWindowKind) -> RuntimeHandle.Kind {
        switch kind {
        case .terminal:
            return .terminal
        case .files:
            return .files
        case .browser:
            return .browser
        case .vnc:
            return .vnc
        }
    }
}
