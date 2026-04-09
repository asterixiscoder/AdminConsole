import DesktopDomain

public protocol WorkspacePersistence: Sendable {
    func loadSnapshot() async throws -> DesktopSnapshot
    func saveSnapshot(_ snapshot: DesktopSnapshot) async throws
}

public actor InMemoryWorkspacePersistence: WorkspacePersistence {
    private var snapshot: DesktopSnapshot

    public init(snapshot: DesktopSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func loadSnapshot() async throws -> DesktopSnapshot {
        snapshot
    }

    public func saveSnapshot(_ snapshot: DesktopSnapshot) async throws {
        self.snapshot = snapshot
    }
}
