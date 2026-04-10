import DesktopDomain
import Foundation
import NIOCore
import NIOSSH
import NIOTransportServices
import SecurityKit

public enum SSHRuntimeError: LocalizedError, Sendable {
    case shellChannelUnavailable
    case noActiveShell

    public var errorDescription: String? {
        switch self {
        case .shellChannelUnavailable:
            return "SSH shell channel was not created."
        case .noActiveShell:
            return "There is no active SSH shell."
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
            let liveTransport = try await establishTransport(using: configuration)
            transport = liveTransport
            state.connectionTitle = configuration.connectionSummary
            state.sessionState = .connected
            state.statusMessage = "Connected"
            state.columns = configuration.terminalSize.columns
            state.rows = configuration.terminalSize.rows
            appendTerminalOutput("SSH session established.\n")
            await publishState()
            return true
        } catch {
            await tearDownTransport()
            state.connectionTitle = configuration.connectionSummary
            state.sessionState = .failed
            state.statusMessage = error.localizedDescription
            appendTerminalOutput("Connection failed: \(error.localizedDescription)\n")
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
                                password: configuration.password
                            ),
                            serverAuthDelegate: SSHKnownHostKeyDelegate(
                                host: configuration.connection.host,
                                port: configuration.connection.port,
                                trustStore: hostKeyTrustStore
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
                        .flatMap {
                            let ptyPromise = childChannel.eventLoop.makePromise(of: Void.self)
                            childChannel.pipeline.triggerUserOutboundEvent(
                                SSHChannelRequestEvent.PseudoTerminalRequest(
                                    wantReply: true,
                                    term: configuration.terminalType,
                                    terminalCharacterWidth: configuration.terminalSize.columns,
                                    terminalRowHeight: configuration.terminalSize.rows,
                                    terminalPixelWidth: configuration.terminalSize.pixelWidth,
                                    terminalPixelHeight: configuration.terminalSize.pixelHeight,
                                    terminalModes: SSHTerminalModes([:])
                                ),
                                promise: ptyPromise
                            )
                            return ptyPromise.futureResult
                        }
                        .flatMap {
                            let shellRequestPromise = childChannel.eventLoop.makePromise(of: Void.self)
                            childChannel.pipeline.triggerUserOutboundEvent(
                                SSHChannelRequestEvent.ShellRequest(wantReply: true),
                                promise: shellRequestPromise
                            )
                            return shellRequestPromise.futureResult
                        }
                }

                return channel.eventLoop.makeSucceededVoidFuture()
            }

        do {
            let connectFuture: EventLoopFuture<Channel> = bootstrap.connect(
                host: configuration.connection.host,
                port: configuration.connection.port
            )
            let rootChannel = try await unsafeFutureValue(connectFuture)

            guard let shellFuture = shellFutureBox.future else {
                throw SSHRuntimeError.shellChannelUnavailable
            }

            let shellChannel = try await unsafeFutureValue(shellFuture)
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
        state.statusMessage = reason
        appendTerminalOutput("\nSession ended: \(reason)\n")
        await publishState()
        await tearDownTransport()
    }

    private func appendTerminalOutput(_ text: String) {
        emulator.consume(text)
        state.transcript = emulator.makeTranscript()
        state.replaceBuffer(emulator.makeBufferSnapshot())
    }

    private func synchronizeStateFromEmulator(columns: Int, rows: Int) {
        state.columns = columns
        state.rows = rows
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
}

private final class SSHPasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.password) else {
            nextChallengePromise.fail(
                NSError(
                    domain: "SSHKit.Auth",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Password authentication is not supported by this server."]
                )
            )
            return
        }

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

    init(host: String, port: Int, trustStore: SSHHostKeyTrustStore) {
        self.host = host
        self.port = port
        self.trustStore = trustStore
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let openSSHPublicKey = String(openSSHPublicKey: hostKey)
        let eventLoop = validationCompletePromise.futureResult.eventLoop

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
            } catch {
                eventLoop.execute {
                    validationCompletePromise.fail(error)
                }
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
