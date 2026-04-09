import DesktopDomain
import Foundation
import SSHKit

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
    private var handles: [WindowID: RuntimeHandle] = [:]
    private var terminalRuntimes: [WindowID: SSHTerminalRuntime] = [:]

    public init() {}

    public func register(kind: RuntimeHandle.Kind, for windowID: WindowID) -> RuntimeHandle {
        let handle = RuntimeHandle(windowID: windowID, kind: kind)
        handles[windowID] = handle
        return handle
    }

    public func registerTerminal(_ runtime: SSHTerminalRuntime, for windowID: WindowID) -> RuntimeHandle {
        let handle = RuntimeHandle(windowID: windowID, kind: .terminal)
        handles[windowID] = handle
        terminalRuntimes[windowID] = runtime
        return handle
    }

    public func handle(for windowID: WindowID) -> RuntimeHandle? {
        handles[windowID]
    }

    public func terminalRuntime(for windowID: WindowID) -> SSHTerminalRuntime? {
        terminalRuntimes[windowID]
    }

    public func remove(windowID: WindowID) async {
        if let runtime = terminalRuntimes.removeValue(forKey: windowID) {
            await runtime.disconnect()
        }

        handles.removeValue(forKey: windowID)
    }
}
