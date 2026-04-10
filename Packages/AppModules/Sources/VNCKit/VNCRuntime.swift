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
    private var client: RFBClient?

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
        await disconnect()

        self.configuration = configuration
        surface = VNCSurfaceState(
            connectionTitle: configuration.connection.displayName,
            sessionState: .connecting,
            statusMessage: "Starting VNC handshake",
            frame: .placeholder(
                title: "Connecting to \(configuration.connection.displayName)",
                detail: "Negotiating RFB session and requesting framebuffer updates."
            ),
            remoteDesktopName: configuration.connection.displayName,
            qualityPreset: configuration.qualityPreset.rawValue,
            isTrackpadModeEnabled: configuration.isTrackpadModeEnabled,
            remotePointer: CursorState(x: 0.32, y: 0.40),
            recentEvents: ["Connect requested"]
        )
        await publish()

        let client = RFBClient(configuration: configuration) { [weak self] snapshot in
            guard let self else {
                return
            }

            await self.handleFramebuffer(snapshot)
        }
        self.client = client

        do {
            let snapshot = try await client.connect()
            surface.sessionState = .connected
            surface.statusMessage = "Connected to remote VNC desktop"
            surface.remoteDesktopName = snapshot.desktopName
            surface.qualityPreset = configuration.qualityPreset.rawValue
            surface.appendEvent("Framebuffer ready")
            apply(snapshot: snapshot)
            await publish()
            return true
        } catch {
            surface.sessionState = .failed
            surface.statusMessage = error.localizedDescription
            surface.appendEvent("Connection failed")
            surface.frame = .placeholder(
                title: "VNC connection failed",
                detail: error.localizedDescription
            )
            self.client = nil
            await publish()
            return false
        }
    }

    public func disconnect() async {
        if let client {
            await client.disconnect()
        }
        client = nil

        if surface.sessionState == .connected || surface.sessionState == .connecting {
            surface.sessionState = .failed
            surface.statusMessage = "VNC session closed"
            surface.appendEvent("Disconnected")
            await publish()
        }
    }

    public func movePointer(deltaX: Double, deltaY: Double) async {
        guard surface.sessionState == .connected else {
            return
        }

        surface.remotePointer = CursorState(
            x: max(0.0, min(1.0, surface.remotePointer.x + deltaX)),
            y: max(0.0, min(1.0, surface.remotePointer.y + deltaY))
        )

        do {
            try await client?.movePointer(
                normalizedX: surface.remotePointer.x,
                normalizedY: surface.remotePointer.y
            )
            surface.statusMessage = "Remote pointer moved"
            surface.appendEvent(pointerSummary(prefix: "Pointer"))
            await publish()
        } catch {
            await presentTransportFailure(error)
        }
    }

    public func click(button: PointerButton = .primary) async {
        guard surface.sessionState == .connected else {
            return
        }

        do {
            switch button {
            case .primary:
                try await client?.click(
                    normalizedX: surface.remotePointer.x,
                    normalizedY: surface.remotePointer.y
                )
            }
            surface.statusMessage = "\(button.rawValue.capitalized) click sent"
            surface.appendEvent("\(button.rawValue.capitalized) click at \(pointerCoordinatesSummary())")
            await publish()
        } catch {
            await presentTransportFailure(error)
        }
    }

    public func send(text: String) async {
        guard surface.sessionState == .connected else {
            return
        }

        do {
            try await client?.send(text: text)
            let normalized = text.replacingOccurrences(of: "\n", with: "\\n")
            surface.statusMessage = "Keyboard input delivered"
            surface.appendEvent("Typed \"\(String(normalized.prefix(24)))\"")
            await publish()
        } catch {
            await presentTransportFailure(error)
        }
    }

    public func cycleQualityPreset() async {
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

        if surface.sessionState == .connected {
            do {
                try await client?.updateQualityPreset(next)
            } catch {
                await presentTransportFailure(error)
                return
            }
        }

        await publish()
    }

    private func handleFramebuffer(_ snapshot: RFBFramebufferSnapshot) async {
        guard surface.sessionState == .connected else {
            return
        }

        apply(snapshot: snapshot)
        surface.statusMessage = "Framebuffer updated"
        await publish()
    }

    private func apply(snapshot: RFBFramebufferSnapshot) {
        surface.remoteDesktopName = snapshot.desktopName
        surface.frame = VNCFrameSnapshot(
            columns: 72,
            rows: 20,
            lines: makePreviewLines(from: snapshot),
            pixelWidth: snapshot.width,
            pixelHeight: snapshot.height,
            rgbaPixels: snapshot.pixels
        )
    }

    private func makePreviewLines(from snapshot: RFBFramebufferSnapshot) -> [String] {
        guard snapshot.width > 0, snapshot.height > 0, !snapshot.pixels.isEmpty else {
            return [
                "Remote desktop: \(snapshot.desktopName)",
                "Framebuffer is empty."
            ]
        }

        let previewColumns = 56
        let previewRows = 18
        let luminanceRamp = Array(" .:-=+*#%@")

        var lines: [String] = [
            "Remote desktop: \(snapshot.desktopName)",
            "Size: \(snapshot.width)x\(snapshot.height)  Quality: \(surface.qualityPreset)  Pointer: \(pointerCoordinatesSummary())",
            ""
        ]

        for row in 0..<previewRows {
            let sourceY = min(snapshot.height - 1, Int(Double(row) / Double(max(1, previewRows - 1)) * Double(snapshot.height - 1)))
            var output = ""

            for column in 0..<previewColumns {
                let sourceX = min(snapshot.width - 1, Int(Double(column) / Double(max(1, previewColumns - 1)) * Double(snapshot.width - 1)))
                let pixel = snapshot.pixels[sourceY * snapshot.width + sourceX]
                let red = Double((pixel >> 24) & 0xFF)
                let green = Double((pixel >> 16) & 0xFF)
                let blue = Double((pixel >> 8) & 0xFF)
                let luminance = (0.299 * red + 0.587 * green + 0.114 * blue) / 255.0
                let rampIndex = min(luminanceRamp.count - 1, Int(luminance * Double(luminanceRamp.count - 1)))
                output.append(luminanceRamp[rampIndex])
            }

            lines.append(output)
        }

        lines.append("")
        lines.append(contentsOf: surface.recentEvents.suffix(4).map { " - \($0)" })
        return lines
    }

    private func presentTransportFailure(_ error: Error) async {
        surface.sessionState = .failed
        surface.statusMessage = error.localizedDescription
        surface.appendEvent("Transport failure")
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
}
