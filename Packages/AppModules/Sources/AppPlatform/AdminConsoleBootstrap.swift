import ConnectionKit
import CoreGraphics
import DesktopCompositor
import DesktopDomain
import DesktopStore
import FilesFeature
import Foundation
import InputKit
import PersistenceKit
import RuntimeRegistry
import SecurityKit
import SSHKit
import TelemetryKit
import VNCKit
import WindowManager

public struct AdminConsoleBootstrap: Sendable {
    public let store: DesktopStore
    public let runtimes: RuntimeRegistry
    public let persistence: WorkspacePersistence
    public let inputRouter: InputRouter
    public let compositor: DesktopSurfaceModel
    public let sshCredentialStore: SSHCredentialStore
    public let sshHostKeyTrustStore: SSHHostKeyTrustStore
    public let logger: Logger

    public init(
        store: DesktopStore = DesktopStore(),
        runtimes: RuntimeRegistry = RuntimeRegistry(),
        persistence: WorkspacePersistence = InMemoryWorkspacePersistence(),
        inputRouter: InputRouter = InputRouter(),
        compositor: DesktopSurfaceModel = .init(scale: 1.0),
        sshCredentialStore: SSHCredentialStore = SSHCredentialStore(),
        sshHostKeyTrustStore: SSHHostKeyTrustStore = SSHHostKeyTrustStore(),
        logger: Logger = Logger(subsystem: "AppPlatform")
    ) {
        self.store = store
        self.runtimes = runtimes
        self.persistence = persistence
        self.inputRouter = inputRouter
        self.compositor = compositor
        self.sshCredentialStore = sshCredentialStore
        self.sshHostKeyTrustStore = sshHostKeyTrustStore
        self.logger = logger
    }
}

public typealias PhaseZeroSnapshot = DesktopSnapshot
public typealias PhaseZeroWindow = DesktopWindow
public typealias PhaseZeroWindowID = WindowID
public typealias PhaseZeroWindowKind = DesktopWindowKind
public typealias PhaseZeroRect = NormalizedRect
public typealias PhaseZeroTerminalState = TerminalSurfaceState
public typealias PhaseZeroTerminalColor = TerminalColor
public typealias PhaseZeroTerminalTextStyle = TerminalTextStyle
public typealias PhaseZeroTerminalGridPoint = TerminalGridPoint
public typealias PhaseZeroTerminalSelection = TerminalSelection
public typealias PhaseZeroFilesState = FilesSurfaceState
public typealias PhaseZeroFilesEntry = FilesEntry
public typealias PhaseZeroBrowserState = BrowserSurfaceState
public typealias PhaseZeroVNCState = VNCSurfaceState
public typealias PhaseZeroVNCQualityPreset = VNCQualityPreset
public typealias PhaseZeroVNCPointerButton = VNCRuntime.PointerButton
public typealias PhaseZeroVNCScrollDirection = VNCRuntime.ScrollDirection
public typealias PhaseZeroInputCaptureMode = DesktopInputCaptureMode
public typealias PhaseZeroWorkMode = DesktopWorkMode

public struct PhaseZeroSSHConnectionRequest: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    public var terminalType: String
    public var columns: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        host: String,
        port: Int = 22,
        username: String,
        password: String,
        terminalType: String = "xterm-256color",
        columns: Int = 120,
        rows: Int = 32,
        pixelWidth: Int = 1440,
        pixelHeight: Int = 900
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.terminalType = terminalType
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var connectionSummary: String {
        "\(username)@\(host):\(port)"
    }

    public var credentialIdentity: SSHCredentialIdentity {
        SSHCredentialIdentity(host: host, port: port, username: username)
    }

    public func runtimeConfiguration(password: String) -> SSHConnectionConfiguration {
        SSHConnectionConfiguration(
            connection: ConnectionDescriptor(
                kind: .ssh,
                host: host,
                port: port,
                displayName: "\(username)@\(host)"
            ),
            username: username,
            password: password,
            terminalType: terminalType,
            terminalSize: TerminalSize(
                columns: columns,
                rows: rows,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        )
    }
}

public struct PhaseZeroVNCConnectionRequest: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var password: String
    public var qualityPreset: VNCQualityPreset
    public var isTrackpadModeEnabled: Bool

    public init(
        host: String,
        port: Int = 5900,
        password: String = "",
        qualityPreset: VNCQualityPreset = .balanced,
        isTrackpadModeEnabled: Bool = true
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.qualityPreset = qualityPreset
        self.isTrackpadModeEnabled = isTrackpadModeEnabled
    }

    public var connectionSummary: String {
        "vnc://\(host):\(port)"
    }

    public func runtimeConfiguration() -> VNCSessionConfiguration {
        VNCSessionConfiguration(
            connection: ConnectionDescriptor(
                kind: .vnc,
                host: host,
                port: port,
                displayName: host
            ),
            password: password,
            qualityPreset: qualityPreset,
            isTrackpadModeEnabled: isTrackpadModeEnabled
        )
    }
}

public actor PhaseZeroCoordinator {
    private let bootstrap: AdminConsoleBootstrap
    private var didStart = false
    private var latestExternalSceneProfile: DisplayProfile?
    private var isManualDisplayOverrideEnabled = false

    public init(bootstrap: AdminConsoleBootstrap = AdminConsoleBootstrap()) {
        self.bootstrap = bootstrap
    }

    public func startIfNeeded() async {
        guard !didStart else {
            return
        }

        didStart = true
        let snapshot = await bootstrap.store.dispatch(.bootstrapPhaseZero)
        await ensureRuntimes(for: snapshot)
        bootstrap.logger.log("Phase 0 bootstrap started")
    }

    public func applicationDidEnterBackground() async {
        await bootstrap.runtimes.suspendAllVNCRuntimes()
        await registerControlInput("App entered background: VNC sessions paused")
    }

    public func applicationWillEnterForeground() async {
        await bootstrap.runtimes.resumeAllVNCRuntimes()
        await registerControlInput("App entered foreground: VNC sessions resumed")
    }

    public func snapshots() async -> AsyncStream<PhaseZeroSnapshot> {
        await bootstrap.store.snapshots()
    }

    public func currentSnapshot() async -> PhaseZeroSnapshot {
        await bootstrap.store.currentSnapshot()
    }

    @discardableResult
    public func openWindow(_ kind: PhaseZeroWindowKind) async -> PhaseZeroWindowID? {
        let next = await bootstrap.store.dispatch(.openWindow(kind))
        await ensureRuntimes(for: next)
        return next.windows.last?.id
    }

    public func focusWindow(_ id: PhaseZeroWindowID) async {
        _ = await bootstrap.store.dispatch(.focusWindow(id))
    }

    public func closeWindow(_ id: PhaseZeroWindowID) async {
        _ = await bootstrap.store.dispatch(.closeWindow(id))
        await bootstrap.runtimes.remove(windowID: id)
        await registerControlInput("Window closed")
    }

    public func updateWindowFrame(_ id: PhaseZeroWindowID, frame: PhaseZeroRect) async {
        _ = await bootstrap.store.dispatch(.updateWindowFrame(windowID: id, frame: frame))
    }

    public func toggleWindowMaximized(_ id: PhaseZeroWindowID) async {
        _ = await bootstrap.store.dispatch(.toggleWindowMaximized(id))

        let snapshot = await bootstrap.store.currentSnapshot()
        if let window = snapshot.windows.first(where: { $0.id == id }) {
            await registerControlInput(
                window.isMaximized
                    ? "Window maximized: \(window.title)"
                    : "Window restored: \(window.title)"
            )
        } else {
            await registerControlInput("Window maximize toggled")
        }
    }

    public func toggleMaximizeFocusedWindow() async {
        guard let windowID = await targetFocusableWindowID() else {
            await registerControlInput("Maximize skipped: no window available")
            return
        }

        await toggleWindowMaximized(windowID)
    }

    public func moveCursor(deltaX: Double, deltaY: Double) async {
        _ = await bootstrap.store.dispatch(.moveCursor(deltaX: deltaX, deltaY: deltaY))
    }

    public func routeKeyboardInputTargets() async -> RoutedKeyboardInput {
        let snapshot = await bootstrap.store.currentSnapshot()
        let targetWindow = inputCaptureWindow(in: snapshot)
        return bootstrap.inputRouter.routeKeyboardInput(
            focusedWindow: targetWindow,
            captureMode: snapshot.inputCaptureMode
        )
    }

    public func handlePointerPan(
        translation: CGPoint,
        surfaceSize: CGSize,
        source: PointerInputSource = .touchTrackpad
    ) async {
        let snapshot = await bootstrap.store.currentSnapshot()
        let targetWindow = inputCaptureWindow(in: snapshot)
        let routed = bootstrap.inputRouter.routePointerMotion(
            PointerMotionInput(
                translationX: translation.x,
                translationY: translation.y,
                surfaceWidth: surfaceSize.width,
                surfaceHeight: surfaceSize.height,
                source: source
            ),
            focusedWindow: targetWindow,
            captureMode: snapshot.inputCaptureMode
        )

        guard routed.cursorDeltaX != 0 || routed.cursorDeltaY != 0 else {
            return
        }

        _ = await bootstrap.store.dispatch(
            .moveCursor(deltaX: routed.cursorDeltaX, deltaY: routed.cursorDeltaY)
        )

        if routed.shouldForwardToVNC,
           let windowID = targetVNCPointerWindowID(in: snapshot)?.id,
           let runtime = await vncRuntime(for: windowID) {
            await runtime.movePointer(
                deltaX: routed.forwardedVNCDeltaX,
                deltaY: routed.forwardedVNCDeltaY
            )
        }
    }

    public func setInputCaptureMode(_ mode: PhaseZeroInputCaptureMode) async {
        _ = await bootstrap.store.dispatch(.setInputCaptureMode(mode))

        let summary: String
        switch mode {
        case .automatic:
            summary = "Input capture: Automatic"
        case .terminal:
            summary = "Input capture: Terminal"
        case .vnc:
            summary = "Input capture: VNC"
        }
        await registerControlInput(summary)
    }

    public func setActiveWorkMode(_ mode: PhaseZeroWorkMode) async {
        var snapshot = await bootstrap.store.currentSnapshot()
        if snapshot.windows.last(where: { $0.kind == mode.windowKind }) == nil {
            _ = await openWindow(mode.windowKind)
            snapshot = await bootstrap.store.currentSnapshot()
        }

        _ = await bootstrap.store.dispatch(.setActiveWorkMode(mode))
        let preferredCaptureMode: PhaseZeroInputCaptureMode
        switch mode {
        case .ssh:
            preferredCaptureMode = .terminal
        case .vnc:
            preferredCaptureMode = .vnc
        case .browser:
            preferredCaptureMode = .automatic
        }
        _ = await bootstrap.store.dispatch(.setInputCaptureMode(preferredCaptureMode))
        await ensureRuntimes(for: snapshot)
        await registerControlInput(
            "Active mode: \(mode.rawValue.uppercased()) • Capture: \(preferredCaptureMode.rawValue.capitalized)"
        )
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
            latestExternalSceneProfile = profile

            if !isManualDisplayOverrideEnabled {
                _ = await bootstrap.store.dispatch(.updateDisplayProfile(profile))
            }
        }

        _ = await bootstrap.store.dispatch(.setExternalDisplayConnected(isConnected))
        bootstrap.logger.log("External display connected: \(isConnected)")
    }

    public func overrideDisplayProfile(
        width: Double,
        height: Double,
        scale: Double
    ) async {
        isManualDisplayOverrideEnabled = true
        let profile = DisplayProfile(
            width: max(320, width),
            height: max(240, height),
            scale: max(0.5, min(4.0, scale))
        )
        _ = await bootstrap.store.dispatch(.updateDisplayProfile(profile))
        await registerControlInput(
            "Display profile override: \(Int(profile.width))x\(Int(profile.height)) @ \(String(format: "%.2f", profile.scale))x"
        )
    }

    public func fitDisplayProfileToExternalScene() async {
        guard let profile = latestExternalSceneProfile else {
            await registerControlInput("Fit skipped: external scene metrics unavailable")
            return
        }

        isManualDisplayOverrideEnabled = false
        _ = await bootstrap.store.dispatch(.updateDisplayProfile(profile))
        await registerControlInput(
            "Display profile fitted to external scene: \(Int(profile.width))x\(Int(profile.height)) @ \(String(format: "%.2f", profile.scale))x"
        )
    }

    public func registerControlInput(_ description: String) async {
        _ = await bootstrap.store.dispatch(.noteInput(description))
    }

    @discardableResult
    public func connectFocusedTerminal(using request: PhaseZeroSSHConnectionRequest) async -> Bool {
        guard !request.host.isEmpty, !request.username.isEmpty else {
            await registerControlInput("SSH connect skipped: host or username missing")
            return false
        }

        let windowID: WindowID

        if let focusedTerminal = await targetTerminalWindowID() {
            windowID = focusedTerminal
        } else if let opened = await openWindow(.terminal) {
            windowID = opened
        } else {
            await registerControlInput("SSH connect failed: unable to create terminal window")
            return false
        }

        guard let runtime = await terminalRuntime(for: windowID) else {
            await registerControlInput("SSH connect failed: runtime unavailable")
            return false
        }

        do {
            let password = try await resolvePassword(for: request)
            _ = await bootstrap.store.dispatch(.setActiveWorkMode(.ssh))
            await focusWindow(windowID)
            await registerControlInput("SSH connect: \(request.connectionSummary)")
            let didConnect = await runtime.connect(using: request.runtimeConfiguration(password: password))

            if didConnect, !request.password.isEmpty {
                _ = try await bootstrap.sshCredentialStore.savePassword(
                    request.password,
                    for: request.credentialIdentity
                )
            }

            return didConnect
        } catch {
            await runtime.presentLocalFailure(
                connectionTitle: request.connectionSummary,
                message: error.localizedDescription
            )
            await registerControlInput("SSH connect failed: \(error.localizedDescription)")
            return false
        }
    }

    public func sendInputToFocusedTerminal(_ text: String) async {
        guard let windowID = await targetTerminalWindowID(),
              let runtime = await terminalRuntime(for: windowID) else {
            await registerControlInput("Terminal input skipped: no focused terminal")
            return
        }

        do {
            try await runtime.send(text: text)
            let summary = text.replacingOccurrences(of: "\n", with: "\\n")
            await registerControlInput("Terminal input: \(summary.prefix(24))")
        } catch {
            await registerControlInput("Terminal input failed: \(error.localizedDescription)")
        }
    }

    public func resizeFocusedTerminal(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) async {
        guard let windowID = await targetTerminalWindowID(),
              let runtime = await terminalRuntime(for: windowID) else {
            return
        }

        await runtime.resize(
            to: TerminalSize(
                columns: columns,
                rows: rows,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        )
    }

    public func updateFocusedTerminalSelection(_ selection: PhaseZeroTerminalSelection?) async {
        guard let windowID = await targetTerminalWindowID(),
              let runtime = await terminalRuntime(for: windowID) else {
            return
        }

        await runtime.updateSelection(selection)
    }

    public func clearFocusedTerminalSelection() async {
        await updateFocusedTerminalSelection(nil)
    }

    public func selectedTextForFocusedTerminal() async -> String? {
        guard let windowID = await targetTerminalWindowID(),
              let runtime = await terminalRuntime(for: windowID) else {
            return nil
        }

        return await runtime.selectedText()
    }

    public func selectFocusedFilesEntry(id: String) async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files selection skipped: no focused files window")
            return
        }

        await runtime.selectEntry(id: id)
    }

    public func openSelectedFilesEntry() async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files open skipped: no focused files window")
            return
        }

        await runtime.openSelectedEntry()
    }

    public func navigateUpInFocusedFiles() async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files up skipped: no focused files window")
            return
        }

        await runtime.navigateUp()
    }

    public func refreshFocusedFiles() async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files refresh skipped: no focused files window")
            return
        }

        await runtime.refresh()
    }

    public func createFolderInFocusedFiles(named name: String) async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files create folder skipped: no focused files window")
            return
        }

        await runtime.createFolder(named: name)
    }

    public func renameSelectedFilesEntry(to name: String) async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files rename skipped: no focused files window")
            return
        }

        await runtime.renameSelectedEntry(to: name)
    }

    public func deleteSelectedFilesEntry() async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files delete skipped: no focused files window")
            return
        }

        await runtime.deleteSelectedEntry()
    }

    public func importIntoFocusedFiles(from urls: [URL]) async {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files import skipped: no focused files window")
            return
        }

        await runtime.importItems(from: urls)
    }

    public func exportURLForSelectedFilesEntry() async -> URL? {
        guard let windowID = await targetFilesWindowID(),
              let runtime = await filesRuntime(for: windowID) else {
            await registerControlInput("Files export skipped: no focused files window")
            return nil
        }

        return await runtime.exportSelectedEntryURL()
    }

    public func navigateFocusedBrowser(to address: String) async {
        let windowID: WindowID
        if let focusedBrowser = await targetBrowserWindowID() {
            windowID = focusedBrowser
        } else if let opened = await openWindow(.browser) {
            windowID = opened
        } else {
            await registerControlInput("Browser navigate failed: unable to create browser window")
            return
        }

        guard let runtime = await browserRuntime(for: windowID) else {
            await registerControlInput("Browser navigate failed: runtime unavailable")
            return
        }

        _ = await bootstrap.store.dispatch(.setActiveWorkMode(.browser))
        await focusWindow(windowID)
        await runtime.navigate(to: address)
        await registerControlInput("Browser navigate")
    }

    public func reloadFocusedBrowser() async {
        guard let windowID = await targetBrowserWindowID(),
              let runtime = await browserRuntime(for: windowID) else {
            await registerControlInput("Browser reload skipped: no focused browser window")
            return
        }

        await runtime.reload()
        await registerControlInput("Browser reload")
    }

    public func goBackInFocusedBrowser() async {
        guard let windowID = await targetBrowserWindowID(),
              let runtime = await browserRuntime(for: windowID) else {
            await registerControlInput("Browser back skipped: no focused browser window")
            return
        }

        await runtime.goBack()
        await registerControlInput("Browser back")
    }

    public func goForwardInFocusedBrowser() async {
        guard let windowID = await targetBrowserWindowID(),
              let runtime = await browserRuntime(for: windowID) else {
            await registerControlInput("Browser forward skipped: no focused browser window")
            return
        }

        await runtime.goForward()
        await registerControlInput("Browser forward")
    }

    public func syncBrowserHostState(
        windowID: PhaseZeroWindowID,
        urlString: String?,
        title: String?,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool
    ) async {
        guard let runtime = await browserRuntime(for: windowID) else {
            return
        }

        await runtime.syncWebViewState(
            urlString: urlString,
            title: title,
            isLoading: isLoading,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
    }

    public func reportBrowserNavigationFailure(
        windowID: PhaseZeroWindowID,
        message: String
    ) async {
        guard let runtime = await browserRuntime(for: windowID) else {
            return
        }

        await runtime.noteNavigationFailure(message: message)
        await registerControlInput("Browser load failed: \(message)")
    }

    public func reportBrowserNavigationBlocked(
        windowID: PhaseZeroWindowID,
        urlString: String?,
        reason: String
    ) async {
        guard let runtime = await browserRuntime(for: windowID) else {
            return
        }

        await runtime.noteBlockedNavigation(urlString: urlString, reason: reason)
        let urlSummary = urlString ?? "unknown URL"
        await registerControlInput("Browser blocked navigation: \(urlSummary)")
    }

    public func acknowledgeBrowserNavigationCommand(
        windowID: PhaseZeroWindowID,
        commandID: Int
    ) async {
        guard let runtime = await browserRuntime(for: windowID) else {
            return
        }

        await runtime.acknowledgeNavigationCommand(id: commandID)
    }

    public func connectFocusedVNC(using request: PhaseZeroVNCConnectionRequest) async {
        guard !request.host.isEmpty else {
            await registerControlInput("VNC connect skipped: host missing")
            return
        }

        let windowID: WindowID

        if let focusedVNC = await targetVNCWindowID() {
            windowID = focusedVNC
        } else if let opened = await openWindow(.vnc) {
            windowID = opened
        } else {
            await registerControlInput("VNC connect failed: unable to create VNC window")
            return
        }

        guard let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC connect failed: runtime unavailable")
            return
        }

        _ = await bootstrap.store.dispatch(.setActiveWorkMode(.vnc))
        await focusWindow(windowID)
        await registerControlInput("VNC connect: \(request.connectionSummary)")
        _ = await runtime.connect(using: request.runtimeConfiguration())
    }

    public func reconnectFocusedVNC() async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC reconnect skipped: no focused VNC window")
            return
        }

        await runtime.reconnect()
        await registerControlInput("VNC reconnect requested")
    }

    public func disconnectFocusedVNC() async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC disconnect skipped: no focused VNC window")
            return
        }

        await runtime.disconnect()
        await registerControlInput("VNC disconnected")
    }

    public func movePointerInFocusedVNC(deltaX: Double, deltaY: Double) async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            return
        }

        await runtime.movePointer(deltaX: deltaX, deltaY: deltaY)
    }

    public func clickFocusedVNC() async {
        await clickFocusedVNC(button: .primary)
    }

    public func clickFocusedVNC(button: PhaseZeroVNCPointerButton) async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC \(button.rawValue) click skipped: no focused VNC window")
            return
        }

        await runtime.click(button: button)
    }

    public func togglePrimaryDragInFocusedVNC() async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC drag skipped: no focused VNC window")
            return
        }

        await runtime.toggleDrag(button: .primary)
    }

    public func scrollFocusedVNC(_ direction: PhaseZeroVNCScrollDirection, steps: Int = 1) async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC wheel skipped: no focused VNC window")
            return
        }

        await runtime.scroll(direction, steps: steps)
    }

    public func sendInputToFocusedVNC(_ text: String) async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC input skipped: no focused VNC window")
            return
        }

        await runtime.send(text: text)
        let summary = text.replacingOccurrences(of: "\n", with: "\\n")
        await registerControlInput("VNC input: \(summary.prefix(24))")
    }

    public func sendClipboardToFocusedVNC(_ text: String) async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC clipboard skipped: no focused VNC window")
            return
        }

        await runtime.sendClipboard(text: text)
        await registerControlInput("VNC clipboard -> remote")
    }

    public func remoteClipboardTextForFocusedVNC() async -> String? {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            return nil
        }

        return await runtime.snapshot().remoteClipboardText
    }

    public func cycleQualityPresetForFocusedVNC() async {
        guard let windowID = await targetVNCWindowID(),
              let runtime = await vncRuntime(for: windowID) else {
            await registerControlInput("VNC quality skipped: no focused VNC window")
            return
        }

        await runtime.cycleQualityPreset()
        await registerControlInput("VNC quality preset changed")
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

    private func ensureRuntimes(for snapshot: PhaseZeroSnapshot) async {
        for window in snapshot.windows {
            switch window.kind {
            case .terminal:
                if await bootstrap.runtimes.terminalRuntime(for: window.id) == nil {
                    let runtime = makeTerminalRuntime(windowID: window.id)
                    _ = await bootstrap.runtimes.registerTerminal(runtime, for: window.id)
                    _ = await bootstrap.store.dispatch(
                        .updateTerminalSurface(
                            windowID: window.id,
                            surface: await runtime.snapshot()
                        )
                    )
                }
            case .files:
                if await bootstrap.runtimes.filesRuntime(for: window.id) == nil {
                    let runtime = makeFilesRuntime(windowID: window.id)
                    _ = await bootstrap.runtimes.registerFiles(runtime, for: window.id)
                    await runtime.start()
                }
            case .vnc:
                if await bootstrap.runtimes.vncRuntime(for: window.id) == nil {
                    let runtime = makeVNCRuntime(windowID: window.id)
                    _ = await bootstrap.runtimes.registerVNC(runtime, for: window.id)
                    _ = await bootstrap.store.dispatch(
                        .updateVNCSurface(
                            windowID: window.id,
                            surface: await runtime.snapshot()
                        )
                    )
                }
            case .browser:
                if await bootstrap.runtimes.browserRuntime(for: window.id) == nil {
                    let runtime = makeBrowserRuntime(windowID: window.id)
                    _ = await bootstrap.runtimes.registerBrowser(runtime, for: window.id)
                    await runtime.start()
                    _ = await bootstrap.store.dispatch(
                        .updateBrowserSurface(
                            windowID: window.id,
                            surface: await runtime.snapshot()
                        )
                    )
                }
            }
        }
    }

    private func targetFocusableWindowID() async -> WindowID? {
        let snapshot = await bootstrap.store.currentSnapshot()
        if let activeWindow = activeWorkWindow(in: snapshot) {
            return activeWindow.id
        }

        if let focusedWindowID = snapshot.focusedWindowID {
            return focusedWindowID
        }

        return snapshot.windows.last?.id
    }

    private func focusedWindow(in snapshot: PhaseZeroSnapshot) -> DesktopWindow? {
        if let activeWindow = activeWorkWindow(in: snapshot) {
            return activeWindow
        }

        if let focusedWindowID = snapshot.focusedWindowID {
            return snapshot.windows.first(where: { $0.id == focusedWindowID })
        }

        return snapshot.windows.last
    }

    private func windowForKind(
        _ kind: DesktopWindowKind,
        in snapshot: PhaseZeroSnapshot
    ) -> DesktopWindow? {
        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID && $0.kind == kind }) {
            return focusedWindow
        }

        return snapshot.windows.last(where: { $0.kind == kind })
    }

    private func activeWorkWindow(in snapshot: PhaseZeroSnapshot) -> DesktopWindow? {
        windowForKind(snapshot.activeWorkMode.windowKind, in: snapshot)
    }

    private func inputCaptureWindow(in snapshot: PhaseZeroSnapshot) -> DesktopWindow? {
        switch snapshot.inputCaptureMode {
        case .automatic:
            return focusedWindow(in: snapshot)
        case .terminal:
            return windowForKind(.terminal, in: snapshot)
        case .vnc:
            return windowForKind(.vnc, in: snapshot)
        }
    }

    private func targetVNCPointerWindowID(in snapshot: PhaseZeroSnapshot) -> DesktopWindow? {
        switch snapshot.inputCaptureMode {
        case .automatic:
            return focusedWindow(in: snapshot)?.kind == .vnc
                ? focusedWindow(in: snapshot)
                : nil
        case .terminal:
            return nil
        case .vnc:
            return windowForKind(.vnc, in: snapshot)
        }
    }

    private func targetTerminalWindowID() async -> WindowID? {
        let snapshot = await bootstrap.store.currentSnapshot()
        if snapshot.activeWorkMode == .ssh,
           let activeWindow = activeWorkWindow(in: snapshot),
           activeWindow.kind == .terminal {
            return activeWindow.id
        }

        return snapshot.windows.last(where: { $0.kind == .terminal })?.id
    }

    private func terminalRuntime(for windowID: WindowID) async -> SSHTerminalRuntime? {
        if let runtime = await bootstrap.runtimes.terminalRuntime(for: windowID) {
            return runtime
        }

        let runtime = makeTerminalRuntime(windowID: windowID)
        _ = await bootstrap.runtimes.registerTerminal(runtime, for: windowID)
        return runtime
    }

    private func targetFilesWindowID() async -> WindowID? {
        let snapshot = await bootstrap.store.currentSnapshot()

        if let focusedWindowID = snapshot.focusedWindowID,
           snapshot.windows.contains(where: { $0.id == focusedWindowID && $0.kind == .files }) {
            return focusedWindowID
        }

        return snapshot.windows.last(where: { $0.kind == .files })?.id
    }

    private func filesRuntime(for windowID: WindowID) async -> FilesWorkspaceRuntime? {
        if let runtime = await bootstrap.runtimes.filesRuntime(for: windowID) {
            return runtime
        }

        let runtime = makeFilesRuntime(windowID: windowID)
        _ = await bootstrap.runtimes.registerFiles(runtime, for: windowID)
        await runtime.start()
        return runtime
    }

    private func targetBrowserWindowID() async -> WindowID? {
        let snapshot = await bootstrap.store.currentSnapshot()
        if snapshot.activeWorkMode == .browser,
           let activeWindow = activeWorkWindow(in: snapshot),
           activeWindow.kind == .browser {
            return activeWindow.id
        }

        return snapshot.windows.last(where: { $0.kind == .browser })?.id
    }

    private func browserRuntime(for windowID: WindowID) async -> BrowserSessionRuntime? {
        if let runtime = await bootstrap.runtimes.browserRuntime(for: windowID) {
            return runtime
        }

        let runtime = makeBrowserRuntime(windowID: windowID)
        _ = await bootstrap.runtimes.registerBrowser(runtime, for: windowID)
        await runtime.start()
        return runtime
    }

    private func targetVNCWindowID() async -> WindowID? {
        let snapshot = await bootstrap.store.currentSnapshot()
        if snapshot.activeWorkMode == .vnc,
           let activeWindow = activeWorkWindow(in: snapshot),
           activeWindow.kind == .vnc {
            return activeWindow.id
        }

        return snapshot.windows.last(where: { $0.kind == .vnc })?.id
    }

    private func vncRuntime(for windowID: WindowID) async -> VNCRuntime? {
        if let runtime = await bootstrap.runtimes.vncRuntime(for: windowID) {
            return runtime
        }

        let runtime = makeVNCRuntime(windowID: windowID)
        _ = await bootstrap.runtimes.registerVNC(runtime, for: windowID)
        return runtime
    }

    private func makeTerminalRuntime(windowID: WindowID) -> SSHTerminalRuntime {
        SSHTerminalRuntime(windowID: windowID, hostKeyTrustStore: bootstrap.sshHostKeyTrustStore) { [store = bootstrap.store] surface in
            _ = await store.dispatch(.updateTerminalSurface(windowID: windowID, surface: surface))
        }
    }

    private func makeFilesRuntime(windowID: WindowID) -> FilesWorkspaceRuntime {
        FilesWorkspaceRuntime(windowID: windowID) { [store = bootstrap.store] surface in
            _ = await store.dispatch(.updateFilesSurface(windowID: windowID, surface: surface))
        }
    }

    private func makeBrowserRuntime(windowID: WindowID) -> BrowserSessionRuntime {
        BrowserSessionRuntime(windowID: windowID) { [store = bootstrap.store] surface in
            _ = await store.dispatch(.updateBrowserSurface(windowID: windowID, surface: surface))
        }
    }

    private func makeVNCRuntime(windowID: WindowID) -> VNCRuntime {
        VNCRuntime(windowID: windowID) { [store = bootstrap.store] surface in
            _ = await store.dispatch(.updateVNCSurface(windowID: windowID, surface: surface))
        }
    }

    private func resolvePassword(for request: PhaseZeroSSHConnectionRequest) async throws -> String {
        if !request.password.isEmpty {
            return request.password
        }

        if let storedPassword = try await bootstrap.sshCredentialStore.password(for: request.credentialIdentity) {
            return storedPassword
        }

        throw PhaseZeroCoordinatorError.missingSavedCredential(connectionSummary: request.connectionSummary)
    }
}

enum PhaseZeroCoordinatorError: LocalizedError {
    case missingSavedCredential(connectionSummary: String)

    var errorDescription: String? {
        switch self {
        case .missingSavedCredential(let connectionSummary):
            return "No saved SSH password found for \(connectionSummary)."
        }
    }
}
