import DesktopDomain
import Foundation

public struct RuntimeHandle: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case terminal
        case files
        case browser
        case vnc
    }

    public let id: UUID
    public let windowID: WindowID
    public let kind: Kind

    public init(id: UUID = UUID(), windowID: WindowID, kind: Kind) {
        self.id = id
        self.windowID = windowID
        self.kind = kind
    }
}

public actor RuntimeRegistry {
    private var runtimes: [WindowID: RuntimeHandle] = [:]

    public init() {}

    public func register(kind: RuntimeHandle.Kind, for windowID: WindowID) -> RuntimeHandle {
        let handle = RuntimeHandle(windowID: windowID, kind: kind)
        runtimes[windowID] = handle
        return handle
    }

    public func handle(for windowID: WindowID) -> RuntimeHandle? {
        runtimes[windowID]
    }

    public func remove(windowID: WindowID) {
        runtimes.removeValue(forKey: windowID)
    }
}
