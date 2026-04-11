import ConnectionKit
import DesktopDomain
import Foundation

public actor VNCRuntime {
    public enum PointerButton: String, Sendable {
        case primary
        case middle
        case secondary

        var mask: UInt8 {
            switch self {
            case .primary:
                return 1 << 0
            case .middle:
                return 1 << 1
            case .secondary:
                return 1 << 2
            }
        }

        var displayName: String {
            rawValue.capitalized
        }
    }

    public enum ScrollDirection: String, Sendable {
        case up
        case down

        var mask: UInt8 {
            switch self {
            case .up:
                return 1 << 3
            case .down:
                return 1 << 4
            }
        }
    }

    private let windowID: WindowID
    private let onSurfaceUpdate: @Sendable (VNCSurfaceState) async -> Void
    private var surface: VNCSurfaceState
    private var configuration: VNCSessionConfiguration?
    private var client: RFBClient?
    private var pressedButtons: Set<PointerButton> = []
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt: Int = 0
    private var shouldMaintainConnection = false
    private var isLifecycleSuspended = false

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
        shouldMaintainConnection = true
        isLifecycleSuspended = false
        self.configuration = configuration
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        await disconnectTransport()
        pressedButtons.removeAll()
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
            recentEvents: ["Connect requested"],
            reconnectAttempt: nil,
            reconnectSecondsRemaining: nil
        )
        await publish()

        return await connectTransport(using: configuration)
    }

    public func reconnect() async {
        guard let configuration else {
            return
        }

        shouldMaintainConnection = true
        isLifecycleSuspended = false
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        await disconnectTransport()
        pressedButtons.removeAll()
        syncPressedButtonsIntoSurface()
        surface.reconnectAttempt = nil
        surface.reconnectSecondsRemaining = nil
        surface.sessionState = .connecting
        surface.statusMessage = "Reconnect requested"
        surface.appendEvent("Manual reconnect")
        await publish()

        _ = await connectTransport(using: configuration)
    }

    public func disconnect() async {
        shouldMaintainConnection = false
        isLifecycleSuspended = false
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        await disconnectTransport()
        pressedButtons.removeAll()
        surface.activePointerButtons = []
        surface.reconnectAttempt = nil
        surface.reconnectSecondsRemaining = nil

        if surface.sessionState != .idle {
            surface.sessionState = .idle
            surface.statusMessage = "VNC session closed"
            surface.appendEvent("Disconnected")
            await publish()
        }
    }

    public func suspendForBackground() async {
        isLifecycleSuspended = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await disconnectTransport()
        pressedButtons.removeAll()
        surface.activePointerButtons = []
        surface.reconnectAttempt = nil
        surface.reconnectSecondsRemaining = nil

        if shouldMaintainConnection {
            surface.sessionState = .idle
            surface.statusMessage = "Session paused while app is in background"
            surface.appendEvent("Paused for background")
            await publish()
        }
    }

    public func resumeAfterForeground() async {
        guard isLifecycleSuspended else {
            return
        }

        isLifecycleSuspended = false
        guard shouldMaintainConnection, let configuration else {
            return
        }

        surface.sessionState = .connecting
        surface.statusMessage = "Resuming VNC session"
        surface.appendEvent("Resume after foreground")
        await publish()
        _ = await connectTransport(using: configuration)
    }

    private func connectTransport(using configuration: VNCSessionConfiguration) async -> Bool {
        let client = RFBClient(configuration: configuration) { [weak self] (snapshot: RFBFramebufferSnapshot) in
            guard let self else {
                return
            }

            await self.handleFramebuffer(snapshot)
        } onServerCutText: { [weak self] (text: String) in
            guard let self else {
                return
            }

            await self.handleServerClipboard(text)
        } onBell: { [weak self] in
            guard let self else {
                return
            }

            await self.handleBell()
        } onDisconnect: { [weak self] error in
            guard let self else {
                return
            }

            await self.handleTransportDisconnect(error)
        }
        self.client = client

        do {
            let snapshot = try await client.connect()
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
            surface.sessionState = .connected
            surface.statusMessage = "Connected to remote VNC desktop"
            surface.reconnectAttempt = nil
            surface.reconnectSecondsRemaining = nil
            surface.remoteDesktopName = snapshot.desktopName
            surface.qualityPreset = configuration.qualityPreset.rawValue
            surface.appendEvent("Framebuffer ready")
            apply(snapshot: snapshot)
            await publish()
            return true
        } catch {
            surface.sessionState = .failed
            surface.statusMessage = VNCReconnectPolicy.userFacingStatus(for: error)
            surface.reconnectAttempt = nil
            surface.reconnectSecondsRemaining = nil
            surface.appendEvent("Connection failed")
            surface.frame = .placeholder(
                title: "VNC connection failed",
                detail: error.localizedDescription
            )
            self.client = nil
            await publish()
            await scheduleReconnectIfNeeded(after: error)
            return false
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
                normalizedY: surface.remotePointer.y,
                buttonMask: currentButtonMask
            )
            surface.statusMessage = "Remote pointer moved"
            surface.appendEvent(pointerSummary(prefix: "Pointer"))
            syncPressedButtonsIntoSurface()
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
            try await client?.click(
                normalizedX: surface.remotePointer.x,
                normalizedY: surface.remotePointer.y,
                buttonMask: button.mask
            )
            surface.statusMessage = "\(button.displayName) click sent"
            surface.appendEvent("\(button.displayName) click at \(pointerCoordinatesSummary())")
            await publish()
        } catch {
            await presentTransportFailure(error)
        }
    }

    public func press(button: PointerButton) async {
        guard surface.sessionState == .connected else {
            return
        }

        pressedButtons.insert(button)

        do {
            try await client?.pressPointer(
                normalizedX: surface.remotePointer.x,
                normalizedY: surface.remotePointer.y,
                buttonMask: currentButtonMask
            )
            syncPressedButtonsIntoSurface()
            surface.statusMessage = "\(button.displayName) button held"
            surface.appendEvent("\(button.displayName) down at \(pointerCoordinatesSummary())")
            await publish()
        } catch {
            pressedButtons.remove(button)
            await presentTransportFailure(error)
        }
    }

    public func release(button: PointerButton) async {
        guard surface.sessionState == .connected else {
            return
        }

        pressedButtons.remove(button)

        do {
            try await client?.releasePointer(
                normalizedX: surface.remotePointer.x,
                normalizedY: surface.remotePointer.y,
                buttonMask: currentButtonMask
            )
            syncPressedButtonsIntoSurface()
            surface.statusMessage = "\(button.displayName) button released"
            surface.appendEvent("\(button.displayName) up at \(pointerCoordinatesSummary())")
            await publish()
        } catch {
            pressedButtons.insert(button)
            await presentTransportFailure(error)
        }
    }

    public func toggleDrag(button: PointerButton = .primary) async {
        if pressedButtons.contains(button) {
            await release(button: button)
        } else {
            await press(button: button)
        }
    }

    public func scroll(_ direction: ScrollDirection, steps: Int = 1) async {
        guard surface.sessionState == .connected else {
            return
        }

        do {
            try await client?.scroll(
                normalizedX: surface.remotePointer.x,
                normalizedY: surface.remotePointer.y,
                buttonMask: direction.mask,
                steps: steps
            )
            surface.statusMessage = "Wheel \(direction.rawValue) sent"
            surface.appendEvent("Wheel \(direction.rawValue) at \(pointerCoordinatesSummary())")
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

    public func sendClipboard(text: String) async {
        guard surface.sessionState == .connected else {
            return
        }

        do {
            try await client?.sendClipboardText(text)
            surface.statusMessage = "Clipboard sent to remote desktop"
            surface.appendEvent("Clipboard -> remote (\(min(text.count, 32)) chars)")
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

    private func handleServerClipboard(_ text: String) async {
        surface.remoteClipboardText = text
        surface.statusMessage = "Remote clipboard updated"
        surface.appendEvent("Clipboard <- remote (\(min(text.count, 32)) chars)")
        await publish()
    }

    private func handleBell() async {
        surface.bellCount += 1
        surface.statusMessage = "Remote bell received"
        surface.appendEvent("Bell #\(surface.bellCount)")
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

    private var currentButtonMask: UInt8 {
        pressedButtons.reduce(0) { $0 | $1.mask }
    }

    private func syncPressedButtonsIntoSurface() {
        surface.activePointerButtons = pressedButtons
            .map(\.rawValue)
            .sorted()
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
        if let remoteClipboardText = surface.remoteClipboardText,
           !remoteClipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Clipboard: \(String(remoteClipboardText.prefix(48)))")
        }
        return lines
    }

    private func presentTransportFailure(_ error: Error) async {
        pressedButtons.removeAll()
        syncPressedButtonsIntoSurface()
        await handleTransportDisconnect(error)
    }

    private func handleTransportDisconnect(_ error: Error) async {
        guard shouldMaintainConnection, !isLifecycleSuspended else {
            return
        }

        await disconnectTransport()
        surface.sessionState = .failed
        surface.statusMessage = VNCReconnectPolicy.userFacingStatus(for: error)
        surface.reconnectAttempt = nil
        surface.reconnectSecondsRemaining = nil
        let category = VNCReconnectPolicy.classify(error).title
        surface.appendEvent("\(category) transport failure")
        await publish()
        await scheduleReconnectIfNeeded(after: error)
    }

    private func scheduleReconnectIfNeeded(after error: Error) async {
        guard shouldMaintainConnection, !isLifecycleSuspended, let configuration else {
            return
        }

        guard VNCReconnectPolicy.shouldRetry(error) else {
            return
        }

        reconnectAttempt += 1
        let delaySeconds = VNCReconnectPolicy.delaySeconds(forAttempt: reconnectAttempt)
        let attempt = reconnectAttempt

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var remaining = delaySeconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                remaining -= 1
                await self?.updateReconnectCountdown(remaining: remaining, attempt: attempt)
            }

            await self?.executeReconnectAttempt(number: attempt, configuration: configuration)
        }

        surface.sessionState = .connecting
        surface.statusMessage = "Network issue, reconnect in \(delaySeconds)s (attempt #\(attempt))"
        surface.reconnectAttempt = attempt
        surface.reconnectSecondsRemaining = delaySeconds
        surface.appendEvent("Reconnect scheduled #\(attempt) in \(delaySeconds)s")
        await publish()
    }

    private func executeReconnectAttempt(number: Int, configuration: VNCSessionConfiguration) async {
        guard shouldMaintainConnection, !isLifecycleSuspended, reconnectAttempt == number else {
            return
        }

        _ = await connectTransport(using: configuration)
    }

    private func disconnectTransport() async {
        if let client {
            await client.disconnect()
        }
        client = nil
    }

    private func updateReconnectCountdown(remaining: Int, attempt: Int) async {
        guard reconnectAttempt == attempt else {
            return
        }

        surface.sessionState = .connecting
        surface.reconnectAttempt = attempt
        surface.reconnectSecondsRemaining = max(0, remaining)
        surface.statusMessage = "Network issue, reconnect in \(max(0, remaining))s (attempt #\(attempt))"
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
