import ConnectionKit
import DesktopDomain
import Foundation

public actor VNCRuntime {
    public enum PointerButton: String, Sendable {
        case primary
    }

    private let windowID: WindowID
    private let onSurfaceUpdate: @Sendable (VNCSurfaceState) async -> Void
    private var surface: VNCSurfaceState
    private var configuration: VNCSessionConfiguration?

    public init(
        windowID: WindowID,
        onSurfaceUpdate: @escaping @Sendable (VNCSurfaceState) async -> Void
    ) {
        self.windowID = windowID
        self.onSurfaceUpdate = onSurfaceUpdate
        self.surface = .idle()
    }

    public func snapshot() -> VNCSurfaceState {
        surface
    }

    @discardableResult
    public func connect(using configuration: VNCSessionConfiguration) async -> Bool {
        self.configuration = configuration
        surface = VNCSurfaceState(
            connectionTitle: configuration.connection.displayName,
            sessionState: .connecting,
            statusMessage: "Starting VNC handshake",
            frame: .placeholder(
                title: "Connecting to \(configuration.connection.displayName)",
                detail: "Preparing framebuffer and input channel for the spike runtime."
            ),
            remoteDesktopName: configuration.connection.displayName,
            qualityPreset: configuration.qualityPreset.rawValue,
            isTrackpadModeEnabled: configuration.isTrackpadModeEnabled,
            remotePointer: CursorState(x: 0.32, y: 0.40),
            recentEvents: ["Connect requested"]
        )
        await publish()

        try? await Task.sleep(nanoseconds: 250_000_000)

        surface.sessionState = .connected
        surface.statusMessage = "Connected to mock VNC desktop"
        surface.frame = makeFrame()
        surface.appendEvent("Framebuffer ready")
        await publish()
        return true
    }

    public func disconnect() async {
        surface.sessionState = .failed
        surface.statusMessage = "VNC session closed"
        surface.appendEvent("Disconnected")
        surface.frame = makeFrame()
        await publish()
    }

    public func movePointer(deltaX: Double, deltaY: Double) async {
        guard surface.sessionState == .connected else {
            return
        }

        surface.remotePointer = CursorState(
            x: max(0.0, min(1.0, surface.remotePointer.x + deltaX)),
            y: max(0.0, min(1.0, surface.remotePointer.y + deltaY))
        )
        surface.statusMessage = "Remote pointer moved"
        surface.appendEvent(pointerSummary(prefix: "Pointer"))
        surface.frame = makeFrame()
        await publish()
    }

    public func click(button: PointerButton = .primary) async {
        guard surface.sessionState == .connected else {
            return
        }

        surface.statusMessage = "\(button.rawValue.capitalized) click sent"
        surface.appendEvent("\(button.rawValue.capitalized) click at \(pointerCoordinatesSummary())")
        surface.frame = makeFrame()
        await publish()
    }

    public func send(text: String) async {
        guard surface.sessionState == .connected else {
            return
        }

        let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
        let preview = String(normalized.prefix(24))
        surface.statusMessage = "Keyboard input delivered"
        surface.appendEvent("Typed \"\(preview)\"")
        surface.frame = makeFrame(lastTypedText: preview)
        await publish()
    }

    public func cycleQualityPreset() async {
        guard surface.sessionState == .connected else {
            return
        }

        let next: VNCQualityPreset
        switch configuration?.qualityPreset ?? .balanced {
        case .low:
            next = .balanced
        case .balanced:
            next = .high
        case .high:
            next = .low
        }

        configuration?.qualityPreset = next
        surface.qualityPreset = next.rawValue
        surface.statusMessage = "Quality preset changed to \(next.rawValue)"
        surface.appendEvent("Quality -> \(next.rawValue)")
        surface.frame = makeFrame()
        await publish()
    }

    private func publish() async {
        await onSurfaceUpdate(surface)
    }

    private func pointerCoordinatesSummary() -> String {
        let x = Int(surface.remotePointer.x * 100)
        let y = Int(surface.remotePointer.y * 100)
        return "\(x),\(y)"
    }

    private func pointerSummary(prefix: String) -> String {
        "\(prefix) -> \(pointerCoordinatesSummary())"
    }

    private func makeFrame(lastTypedText: String? = nil) -> VNCFrameSnapshot {
        let columns = 72
        let rows = 20
        let connectionName = configuration?.connection.displayName ?? surface.connectionTitle
        let quality = (configuration?.qualityPreset ?? .balanced).rawValue
        let host = configuration?.connection.host ?? "localhost"
        let pointerX = Int(surface.remotePointer.x * 100)
        let pointerY = Int(surface.remotePointer.y * 100)
        let typed = lastTypedText ?? "-"
        let events = surface.recentEvents.suffix(5)

        var lines: [String] = [
            "Remote desktop: \(connectionName)",
            "Host: \(host)    Quality: \(quality)    Trackpad: \(surface.isTrackpadModeEnabled ? "on" : "off")",
            "Pointer: \(pointerX),\(pointerY)    Window: \(windowID.rawValue.uuidString.prefix(8))",
            "",
            "+---------------- Mock Remote Desktop ----------------+",
            "| Terminal  | Browser  | Files                         |",
            "|------------------------------------------------------|",
            "| This VNC spike simulates a remote framebuffer.       |",
            "| Input arrives through the shared coordinator path.   |",
            "| Selection, focus and display sync are already real.  |",
            "|                                                      |",
            "| Last typed: \(typed)",
            "|                                                      |",
            "+------------------------------------------------------+",
            "",
            "Recent remote events:"
        ]

        lines.append(contentsOf: events.map { " - \($0)" })
        return VNCFrameSnapshot(columns: columns, rows: rows, lines: lines)
    }
}
