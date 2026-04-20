import DesktopDomain
import Foundation
import NIOCore
import NIOSSH
import NIOTransportServices
import SecurityKit

public enum SSHRuntimeError: LocalizedError, Sendable {
    case shellChannelUnavailable
    case noActiveShell
    case connectionStageTimedOut(String)
    case passwordAuthenticationNotSupported

    public var errorDescription: String? {
        switch self {
        case .shellChannelUnavailable:
            return "SSH shell channel was not created."
        case .noActiveShell:
            return "There is no active SSH shell."
        case .connectionStageTimedOut(let stage):
            return "SSH connection timed out during \(stage)."
        case .passwordAuthenticationNotSupported:
            return "The SSH server does not allow password authentication for this account."
        }
    }
}

public actor SSHTerminalRuntime {
    public typealias StateSink = @Sendable (TerminalSurfaceState) async -> Void

    private final class ShellFutureBox: @unchecked Sendable {
        var future: EventLoopFuture<Channel>?
    }

    private final class UncheckedFutureValueBox<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private struct Transport {
        let eventLoopGroup: NIOTSEventLoopGroup
        let rootChannel: Channel
        let shellChannel: Channel
    }

    private let windowID: WindowID
    private let stateSink: StateSink
    private let hostKeyTrustStore: SSHHostKeyTrustStore
    private var state: TerminalSurfaceState
    private var emulator: TerminalEmulator
    private var transport: Transport?
    private var backgroundSuspendedAt: Date?

    public init(
        windowID: WindowID,
        initialState: TerminalSurfaceState = .idle(),
        hostKeyTrustStore: SSHHostKeyTrustStore = SSHHostKeyTrustStore(),
        stateSink: @escaping StateSink
    ) {
        let emulator = TerminalEmulator(
            columns: initialState.columns,
            rows: initialState.rows,
            initialTranscript: initialState.transcript
        )
        var seededState = initialState
        seededState.replaceBuffer(emulator.makeBufferSnapshot())

        self.windowID = windowID
        self.state = seededState
        self.emulator = emulator
        self.hostKeyTrustStore = hostKeyTrustStore
        self.stateSink = stateSink
    }

    public func snapshot() -> TerminalSurfaceState {
        state
    }

    @discardableResult
    public func connect(using configuration: SSHConnectionConfiguration) async -> Bool {
        await tearDownTransport()

        state = TerminalSurfaceState(
            connectionTitle: configuration.connectionSummary,
            sessionState: .connecting,
            statusMessage: "Connecting to \(configuration.connectionSummary)",
            transcript: "Connecting to \(configuration.connectionSummary)...\n",
            columns: configuration.terminalSize.columns,
            rows: configuration.terminalSize.rows
        )
        emulator.reset(
            columns: configuration.terminalSize.columns,
            rows: configuration.terminalSize.rows,
            initialTranscript: state.transcript
        )
        state.replaceBuffer(emulator.makeBufferSnapshot())
        await publishState()

        do {
            await logConnectionEvent("Starting new SSH connection.")
            let liveTransport = try await establishTransport(using: configuration)
            transport = liveTransport
            state.connectionTitle = configuration.connectionSummary
            state.sessionState = .connected
            state.statusMessage = "Connected"
            state.columns = configuration.terminalSize.columns
            state.rows = configuration.terminalSize.rows
            await logConnectionEvent("SSH handshake completed. Shell channel is active.")
            appendTerminalOutput("SSH session established.\n")
            await publishState()
            return true
        } catch {
            await tearDownTransport()
            state.connectionTitle = configuration.connectionSummary
            state.sessionState = .failed
            let userMessage = userFacingConnectionMessage(for: error)
            state.statusMessage = userMessage
            appendTerminalOutput("Connection failed: \(userMessage)\n")
            appendTerminalOutput("[debug] \(debugConnectionErrorDescription(error))\n")
            await publishState()
            return false
        }
    }

    public func presentLocalFailure(connectionTitle: String, message: String) async {
        state.connectionTitle = connectionTitle
        state.sessionState = .failed
        state.statusMessage = message
        appendTerminalOutput("Connection failed: \(message)\n")
        await publishState()
    }

    public func disconnect() async {
        await tearDownTransport()
        backgroundSuspendedAt = nil

        if state.sessionState != .idle {
            state.sessionState = .idle
            state.statusMessage = "Disconnected"
            appendTerminalOutput("SSH session disconnected.\n")
            await publishState()
        }
    }

    public func send(text: String) async throws {
        guard let shellChannel = transport?.shellChannel else {
            throw SSHRuntimeError.noActiveShell
        }

        var buffer = shellChannel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        try await futureValue(
            shellChannel.writeAndFlush(
                SSHChannelData(type: .channel, data: .byteBuffer(buffer))
            )
        )
    }

    public func resize(to terminalSize: TerminalSize) async {
        emulator.resize(columns: terminalSize.columns, rows: terminalSize.rows)
        synchronizeStateFromEmulator(columns: terminalSize.columns, rows: terminalSize.rows)
        await publishState()

        guard let shellChannel = transport?.shellChannel else {
            return
        }

        let promise = shellChannel.eventLoop.makePromise(of: Void.self)
        shellChannel.pipeline.triggerUserOutboundEvent(
            SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: terminalSize.columns,
                terminalRowHeight: terminalSize.rows,
                terminalPixelWidth: terminalSize.pixelWidth,
                terminalPixelHeight: terminalSize.pixelHeight
            ),
            promise: promise
        )

        do {
            try await futureValue(promise.futureResult)
        } catch {
            state.statusMessage = "Resize failed: \(error.localizedDescription)"
            await publishState()
        }
    }

    public func updateSelection(_ selection: TerminalSelection?) async {
        state.setSelection(selection)
        await publishState()
    }

    public func suspendForBackground() async {
        guard state.sessionState == .connected else {
            return
        }

        backgroundSuspendedAt = Date()
        state.statusMessage = "App in background. Session will resume on foreground."
        appendTerminalOutput("[SSH] App entered background. Monitoring session state.\n")
        await publishState()
    }

    public func resumeAfterForeground() async {
        guard backgroundSuspendedAt != nil else {
            return
        }
        backgroundSuspendedAt = nil

        guard state.sessionState == .connected else {
            await publishState()
            return
        }

        let hasActiveTransport =
            (transport?.rootChannel.isActive ?? false)
            && (transport?.shellChannel.isActive ?? false)

        if hasActiveTransport {
            state.statusMessage = "Connected"
            appendTerminalOutput("[SSH] App entered foreground. Session remains active.\n")
            await publishState()
            return
        }

        state.sessionState = .failed
        state.statusMessage = "Connection dropped while app was in background."
        appendTerminalOutput("[SSH] Session dropped during background. Reconnect is required.\n")
        await publishState()
        await tearDownTransport()
    }

    public func selectedText() -> String? {
        state.selectedText()
    }

    private func establishTransport(using configuration: SSHConnectionConfiguration) async throws -> Transport {
        let group = NIOTSEventLoopGroup(loopCount: 1)
        let shellFutureBox = ShellFutureBox()

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .connectTimeout(.seconds(15))
            .channelInitializer { [self, windowID] channel in
                let shellPromise = channel.eventLoop.makePromise(of: Channel.self)
                shellFutureBox.future = shellPromise.futureResult

                let sshHandler = NIOSSHHandler(
                    role: .client(
                        .init(
                            userAuthDelegate: SSHPasswordAuthenticationDelegate(
                                username: configuration.username,
                                password: configuration.password,
                                onEvent: { message in
                                    Task {
                                        await self.logConnectionEvent(message)
                                    }
                                }
                            ),
                            serverAuthDelegate: SSHKnownHostKeyDelegate(
                                host: configuration.connection.host,
                                port: configuration.connection.port,
                                trustStore: hostKeyTrustStore,
                                onEvent: { message in
                                    Task {
                                        await self.logConnectionEvent(message)
                                    }
                                }
                            )
                        )
                    ),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )

                do {
                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }

                sshHandler.createChannel(shellPromise) { childChannel, _ in
                    Task {
                        await self.logConnectionEvent("SSH session channel opened. Requesting interactive shell.")
                    }
                    let shellHandler = SSHInteractiveShellHandler(
                        onOutput: { output in
                            Task {
                                await self.consumeRemoteOutput(output)
                            }
                        },
                        onTermination: { reason in
                            Task {
                                await self.handleRemoteTermination(reason: reason, sourceWindowID: windowID)
                            }
                        }
                    )

                    return childChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                        .flatMap {
                            childChannel.pipeline.addHandler(shellHandler)
                        }
                        .map {
                            // Fire-and-forget: waiting for request replies can deadlock on some SSH servers.
                            let ptyPromise = childChannel.eventLoop.makePromise(of: Void.self)
                            childChannel.pipeline.triggerUserOutboundEvent(
                                SSHChannelRequestEvent.PseudoTerminalRequest(
                                    wantReply: false,
                                    term: configuration.terminalType,
                                    terminalCharacterWidth: configuration.terminalSize.columns,
                                    terminalRowHeight: configuration.terminalSize.rows,
                                    terminalPixelWidth: configuration.terminalSize.pixelWidth,
                                    terminalPixelHeight: configuration.terminalSize.pixelHeight,
                                    terminalModes: SSHTerminalModes([:])
                                ),
                                promise: ptyPromise
                            )
                            let shellPromise = childChannel.eventLoop.makePromise(of: Void.self)
                            childChannel.pipeline.triggerUserOutboundEvent(
                                SSHChannelRequestEvent.ShellRequest(wantReply: false),
                                promise: shellPromise
                            )
                            Task {
                                await self.logConnectionEvent("PTY and shell requests sent.")
                            }
                        }
                }

                return channel.eventLoop.makeSucceededVoidFuture()
            }

        do {
            state.statusMessage = "Opening TCP connection..."
            await logConnectionEvent("Resolving host \(configuration.connection.host):\(configuration.connection.port).")
            await publishState()
            let connectFuture: EventLoopFuture<Channel> = bootstrap.connect(
                host: configuration.connection.host,
                port: configuration.connection.port
            )
            let rootChannel = try await timedFutureValue(
                connectFuture,
                timeoutSeconds: 20,
                stage: "TCP connection"
            )
            await logConnectionEvent("TCP connection established.")

            guard let shellFuture = shellFutureBox.future else {
                throw SSHRuntimeError.shellChannelUnavailable
            }

            state.statusMessage = "Negotiating SSH session..."
            await logConnectionEvent("Negotiating SSH algorithms and authenticating user \(configuration.username).")
            await publishState()
            let shellChannel = try await timedFutureValue(
                shellFuture,
                timeoutSeconds: 20,
                stage: "SSH session negotiation"
            )
            await logConnectionEvent("Interactive shell request accepted by server.")
            return Transport(
                eventLoopGroup: group,
                rootChannel: rootChannel,
                shellChannel: shellChannel
            )
        } catch {
            await shutdown(group)
            throw error
        }
    }

    private func consumeRemoteOutput(_ output: String) async {
        guard !output.isEmpty else {
            return
        }

        appendTerminalOutput(output)
        await publishState()
    }

    private func handleRemoteTermination(reason: String, sourceWindowID: WindowID) async {
        guard sourceWindowID == windowID, transport != nil else {
            return
        }

        state.sessionState = .failed
        if backgroundSuspendedAt != nil {
            state.statusMessage = "Connection dropped while app was in background."
        } else {
            state.statusMessage = reason
        }
        appendTerminalOutput("\nSession ended: \(reason)\n")
        await publishState()
        await tearDownTransport()
    }

    private func appendTerminalOutput(_ text: String) {
        emulator.consume(text)
        state.screenTitle = emulator.currentScreenTitle()
        state.transcript = emulator.makeTranscript()
        state.replaceBuffer(emulator.makeBufferSnapshot())
    }

    private func synchronizeStateFromEmulator(columns: Int, rows: Int) {
        state.columns = columns
        state.rows = rows
        state.screenTitle = emulator.currentScreenTitle()
        state.transcript = emulator.makeTranscript()
        state.replaceBuffer(emulator.makeBufferSnapshot())
    }

    private func publishState() async {
        await stateSink(state)
    }

    private func tearDownTransport() async {
        guard let currentTransport = transport else {
            return
        }

        transport = nil
        await closeIfActive(currentTransport.shellChannel)
        await closeIfActive(currentTransport.rootChannel)
        await shutdown(currentTransport.eventLoopGroup)
    }

    private func closeIfActive(_ channel: Channel) async {
        if channel.isActive {
            let promise = channel.eventLoop.makePromise(of: Void.self)
            channel.close(promise: promise)
            _ = try? await futureValue(promise.futureResult)
        }
    }

    private func shutdown(_ eventLoopGroup: NIOTSEventLoopGroup) async {
        await withCheckedContinuation { continuation in
            eventLoopGroup.shutdownGracefully(queue: .global()) { _ in
                continuation.resume()
            }
        }
    }

    private func futureValue<Value: Sendable>(_ future: EventLoopFuture<Value>) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            future.whenComplete { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func unsafeFutureValue<Value>(_ future: EventLoopFuture<Value>) async throws -> Value {
        let boxed = try await futureValue(future.map(UncheckedFutureValueBox.init))
        return boxed.value
    }

    private func timedFutureValue<Value>(
        _ future: EventLoopFuture<Value>,
        timeoutSeconds: Double,
        stage: String
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: UncheckedFutureValueBox<Value>.self) { group in
            group.addTask {
                try await self.futureValue(future.map(UncheckedFutureValueBox.init))
            }
            group.addTask {
                let duration = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: duration)
                throw SSHRuntimeError.connectionStageTimedOut(stage)
            }

            let boxed = try await group.next()!
            group.cancelAll()
            return boxed.value
        }
    }

    private func logConnectionEvent(_ message: String) async {
        appendTerminalOutput("[SSH] \(message)\n")
        await publishState()
    }

    private func userFacingConnectionMessage(for error: Error) -> String {
        if case SSHRuntimeError.passwordAuthenticationNotSupported = error {
            return "Server does not allow password authentication for this account."
        }

        if case SSHRuntimeError.connectionStageTimedOut(let stage) = error {
            return "Connection timed out during \(stage). Check host, port, and network."
        }

        if let hostKeyError = error as? SSHKnownHostValidationError {
            switch hostKeyError {
            case .hostKeyMismatch:
                return "Host key mismatch. Server identity changed or may be unsafe."
            case .invalidHostKeyFormat:
                return "Server returned an invalid SSH host key."
            }
        }

        if let sshError = error as? NIOSSHError, sshError.type == .channelSetupRejected {
            return "SSH channel was rejected by the server."
        }

        let diagnostic = (error.localizedDescription + " " + String(describing: error)).lowercased()

        if diagnostic.contains("permission denied")
            || diagnostic.contains("authentication failed")
            || diagnostic.contains("unable to authenticate")
            || diagnostic.contains("user authentication") {
            return "Authentication failed. Verify username and password."
        }

        if diagnostic.contains("no such host")
            || diagnostic.contains("name or service not known")
            || diagnostic.contains("nodename nor servname provided")
            || diagnostic.contains("hostname") && diagnostic.contains("could not be found") {
            return "Host not found. Verify the server address (DNS/hostname)."
        }

        if diagnostic.contains("connection refused") {
            return "Connection refused. SSH service may be unavailable on this port."
        }

        if diagnostic.contains("network is unreachable")
            || diagnostic.contains("no route to host")
            || diagnostic.contains("internet connection appears to be offline") {
            return "Network is unreachable. Check device connectivity and VPN."
        }

        if diagnostic.contains("timed out") {
            return "Connection timed out. Check network path and firewall."
        }

        return error.localizedDescription
    }

    private func debugConnectionErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(type(of: error)): \(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
    }
}

private final class SSHPasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String
    private let onEvent: @Sendable (String) -> Void

    init(username: String, password: String, onEvent: @escaping @Sendable (String) -> Void) {
        self.username = username
        self.password = password
        self.onEvent = onEvent
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        onEvent("Server auth methods: \(availableMethods)")
        guard availableMethods.contains(.password) else {
            onEvent("Password authentication is not accepted by server.")
            nextChallengePromise.fail(SSHRuntimeError.passwordAuthenticationNotSupported)
            return
        }

        onEvent("Sending password authentication request.")

        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
        )
    }
}

private final class SSHKnownHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let trustStore: SSHHostKeyTrustStore
    private let onEvent: @Sendable (String) -> Void

    init(
        host: String,
        port: Int,
        trustStore: SSHHostKeyTrustStore,
        onEvent: @escaping @Sendable (String) -> Void
    ) {
        self.host = host
        self.port = port
        self.trustStore = trustStore
        self.onEvent = onEvent
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let openSSHPublicKey = String(openSSHPublicKey: hostKey)
        let eventLoop = validationCompletePromise.futureResult.eventLoop
        onEvent("Validating server host key for \(host):\(port).")

        Task {
            do {
                _ = try await trustStore.validateOrTrustOnFirstUse(
                    host: host,
                    port: port,
                    openSSHPublicKey: openSSHPublicKey
                )
                eventLoop.execute {
                    validationCompletePromise.succeed(())
                }
                self.onEvent("Host key trusted.")
            } catch {
                eventLoop.execute {
                    validationCompletePromise.fail(error)
                }
                self.onEvent("Host key validation failed: \(error.localizedDescription)")
            }
        }
    }
}

private final class SSHInteractiveShellHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let onOutput: @Sendable (String) -> Void
    private let onTermination: @Sendable (String) -> Void
    private var didTerminate = false

    init(
        onOutput: @escaping @Sendable (String) -> Void,
        onTermination: @escaping @Sendable (String) -> Void
    ) {
        self.onOutput = onOutput
        self.onTermination = onTermination
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)

        switch payload.data {
        case .byteBuffer(var buffer):
            if let text = buffer.readString(length: buffer.readableBytes) {
                onOutput(text)
            } else if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                onOutput(String(decoding: bytes, as: UTF8.self))
            }
        case .fileRegion:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exitStatus as SSHChannelRequestEvent.ExitStatus:
            onOutput("\n[remote process exited: \(exitStatus.exitStatus)]\n")
        case let exitSignal as SSHChannelRequestEvent.ExitSignal:
            onOutput("\n[remote signal: \(exitSignal.signalName)]\n")
        default:
            break
        }

        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        terminateIfNeeded("Remote shell closed.")
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        terminateIfNeeded(error.localizedDescription)
        context.close(promise: nil)
    }

    private func terminateIfNeeded(_ reason: String) {
        guard !didTerminate else {
            return
        }

        didTerminate = true
        onTermination(reason)
    }
}
