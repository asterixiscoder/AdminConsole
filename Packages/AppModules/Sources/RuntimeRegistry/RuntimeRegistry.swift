import DesktopDomain
import FilesFeature
import Foundation
import SSHKit
import VNCKit

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
    private var filesRuntimes: [WindowID: FilesWorkspaceRuntime] = [:]
    private var vncRuntimes: [WindowID: VNCRuntime] = [:]

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

    public func registerFiles(_ runtime: FilesWorkspaceRuntime, for windowID: WindowID) -> RuntimeHandle {
        let handle = RuntimeHandle(windowID: windowID, kind: .files)
        handles[windowID] = handle
        filesRuntimes[windowID] = runtime
        return handle
    }

    public func registerVNC(_ runtime: VNCRuntime, for windowID: WindowID) -> RuntimeHandle {
        let handle = RuntimeHandle(windowID: windowID, kind: .vnc)
        handles[windowID] = handle
        vncRuntimes[windowID] = runtime
        return handle
    }

    public func handle(for windowID: WindowID) -> RuntimeHandle? {
        handles[windowID]
    }

    public func terminalRuntime(for windowID: WindowID) -> SSHTerminalRuntime? {
        terminalRuntimes[windowID]
    }

    public func filesRuntime(for windowID: WindowID) -> FilesWorkspaceRuntime? {
        filesRuntimes[windowID]
    }

    public func vncRuntime(for windowID: WindowID) -> VNCRuntime? {
        vncRuntimes[windowID]
    }

    public func remove(windowID: WindowID) async {
        if let runtime = terminalRuntimes.removeValue(forKey: windowID) {
            await runtime.disconnect()
        }

        filesRuntimes.removeValue(forKey: windowID)
        if let runtime = vncRuntimes.removeValue(forKey: windowID) {
            await runtime.disconnect()
        }

        handles.removeValue(forKey: windowID)
    }

    public func suspendAllVNCRuntimes() async {
        for runtime in vncRuntimes.values {
            await runtime.suspendForBackground()
        }
    }

    public func resumeAllVNCRuntimes() async {
        for runtime in vncRuntimes.values {
            await runtime.resumeAfterForeground()
        }
    }
}
