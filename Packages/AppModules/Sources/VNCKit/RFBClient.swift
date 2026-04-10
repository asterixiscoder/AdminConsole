import ConnectionKit
import CommonCrypto
import Compression
import Foundation
import Network

public struct RFBFramebufferSnapshot: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt32]
    public var desktopName: String

    public init(width: Int, height: Int, pixels: [UInt32], desktopName: String) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.desktopName = desktopName
    }
}

public enum RFBClientError: LocalizedError, Sendable {
    case invalidProtocolVersion(String)
    case connectionClosed
    case securityNegotiationFailed(String)
    case unsupportedAuthentication
    case missingPassword
    case authenticationFailed(String)
    case unsupportedEncoding(Int32)
    case invalidServerMessage(UInt8)
    case invalidFramebufferGeometry
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidProtocolVersion(let version):
            return "Unsupported VNC protocol version: \(version)"
        case .connectionClosed:
            return "VNC connection closed unexpectedly."
        case .securityNegotiationFailed(let message):
            return "VNC security negotiation failed: \(message)"
        case .unsupportedAuthentication:
            return "This VNC server requires an authentication method the current client does not support."
        case .missingPassword:
            return "This VNC server requires a password, but none was provided."
        case .authenticationFailed(let message):
            return "VNC authentication failed: \(message)"
        case .unsupportedEncoding(let encoding):
            return "Unsupported framebuffer encoding: \(encoding)"
        case .invalidServerMessage(let type):
            return "Unexpected VNC server message type: \(type)"
        case .invalidFramebufferGeometry:
            return "Invalid framebuffer size returned by the VNC server."
        case .transportFailed(let message):
            return message
        }
    }
}

public actor RFBClient {
    private enum ProtocolVersion: String {
        case rfb33 = "RFB 003.003\n"
        case rfb37 = "RFB 003.007\n"
        case rfb38 = "RFB 003.008\n"
    }

    private let configuration: VNCSessionConfiguration
    private let queue: DispatchQueue
    private let onFramebufferUpdate: @Sendable (RFBFramebufferSnapshot) async -> Void
    private let onServerCutText: (@Sendable (String) async -> Void)?
    private let onBell: (@Sendable () async -> Void)?

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var stateContinuation: CheckedContinuation<Void, Error>?
    private var activePixelFormat = RFBPixelFormat.clientPreferred
    private var framebuffer = RFBFramebuffer(width: 0, height: 0)
    private var desktopName = "Remote Desktop"
    private var receiveTask: Task<Void, Never>?
    private var negotiatedProtocolVersion: ProtocolVersion = .rfb38

    public init(
        configuration: VNCSessionConfiguration,
        onFramebufferUpdate: @escaping @Sendable (RFBFramebufferSnapshot) async -> Void,
        onServerCutText: (@Sendable (String) async -> Void)? = nil,
        onBell: (@Sendable () async -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onFramebufferUpdate = onFramebufferUpdate
        self.onServerCutText = onServerCutText
        self.onBell = onBell
        self.queue = DispatchQueue(label: "AdminConsole.RFBClient.\(configuration.connection.host).\(configuration.connection.port)")
    }

    @discardableResult
    public func connect() async throws -> RFBFramebufferSnapshot {
        let endpointHost = NWEndpoint.Host(configuration.connection.host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(configuration.connection.port)) else {
            throw RFBClientError.transportFailed("Invalid VNC port: \(configuration.connection.port)")
        }

        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }

            Task {
                await self.handleConnectionState(state)
            }
        }
        connection.start(queue: queue)

        try await waitForReadyState()
        try await negotiateSession()

        let snapshot = makeSnapshot()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        try await requestFramebufferUpdate(incremental: false)
        return snapshot
    }

    public func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        stateContinuation = nil
        receiveBuffer.removeAll(keepingCapacity: false)
    }

    public func movePointer(normalizedX: Double, normalizedY: Double, buttonMask: UInt8 = 0) async throws {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            return
        }

        let x = UInt16(max(0, min(framebuffer.width - 1, Int(Double(framebuffer.width - 1) * normalizedX))))
        let y = UInt16(max(0, min(framebuffer.height - 1, Int(Double(framebuffer.height - 1) * normalizedY))))

        var message = Data([5, buttonMask])
        message.appendUInt16(x)
        message.appendUInt16(y)
        try await send(message)
    }

    public func click(normalizedX: Double, normalizedY: Double) async throws {
        try await click(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: 1)
    }

    public func click(normalizedX: Double, normalizedY: Double, buttonMask: UInt8) async throws {
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: buttonMask)
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: 0)
    }

    public func pressPointer(normalizedX: Double, normalizedY: Double, buttonMask: UInt8) async throws {
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: buttonMask)
    }

    public func releasePointer(normalizedX: Double, normalizedY: Double, buttonMask: UInt8) async throws {
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: buttonMask)
    }

    public func scroll(normalizedX: Double, normalizedY: Double, buttonMask: UInt8, steps: Int = 1) async throws {
        guard steps > 0 else {
            return
        }

        for _ in 0..<steps {
            try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: buttonMask)
            try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: 0)
        }
    }

    public func send(text: String) async throws {
        for keySymbol in RFBKeySymbolTranslator.keySymbols(for: text) {
            try await sendKeyEvent(isDown: true, keySymbol: keySymbol)
            try await sendKeyEvent(isDown: false, keySymbol: keySymbol)
        }
    }

    public func sendClipboardText(_ text: String) async throws {
        var data = Data([6, 0, 0, 0])
        let payload = Data(text.utf8)
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        try await send(data)
    }

    public func updateQualityPreset(_ preset: VNCQualityPreset) async throws {
        try await setEncodings(preferredEncodings(for: preset))
        try await requestFramebufferUpdate(incremental: false)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            stateContinuation?.resume()
            stateContinuation = nil
        case .failed(let error):
            stateContinuation?.resume(throwing: RFBClientError.transportFailed(error.localizedDescription))
            stateContinuation = nil
        case .cancelled:
            stateContinuation?.resume(throwing: RFBClientError.connectionClosed)
            stateContinuation = nil
        default:
            break
        }
    }

    private func waitForReadyState() async throws {
        guard let connection else {
            throw RFBClientError.connectionClosed
        }

        switch connection.state {
        case .ready:
            return
        case .failed(let error):
            throw RFBClientError.transportFailed(error.localizedDescription)
        case .cancelled:
            throw RFBClientError.connectionClosed
        default:
            try await withCheckedThrowingContinuation { continuation in
                stateContinuation = continuation
            }
        }
    }

    private func negotiateSession() async throws {
        let versionData = try await receiveExact(count: 12)
        guard let versionString = String(data: versionData, encoding: .ascii) else {
            throw RFBClientError.invalidProtocolVersion("invalid-ascii")
        }

        let negotiatedVersion: ProtocolVersion
        if versionString.hasPrefix("RFB 003.003") {
            negotiatedVersion = .rfb33
        } else if versionString.hasPrefix("RFB 003.007") {
            negotiatedVersion = .rfb37
        } else if versionString.hasPrefix("RFB 003.008") {
            negotiatedVersion = .rfb38
        } else {
            throw RFBClientError.invalidProtocolVersion(versionString.trimmingCharacters(in: .newlines))
        }

        negotiatedProtocolVersion = negotiatedVersion
        try await send(Data(negotiatedVersion.rawValue.utf8))
        if negotiatedVersion == .rfb33 {
            try await negotiateSecurityForRFB33()
        } else {
            try await negotiateSecurityTypes()
        }

        try await send(Data([1]))
        try await readServerInit()
        try await setPixelFormat(activePixelFormat)
        try await setEncodings(preferredEncodings(for: configuration.qualityPreset))
    }

    private func negotiateSecurityForRFB33() async throws {
        let securityType = try await receiveUInt32()
        switch securityType {
        case 1:
            return
        case 2:
            try await performVNCAuthentication()
        default:
            let reason = try await readFailureReasonIfPresent()
            throw RFBClientError.securityNegotiationFailed(reason ?? "security type \(securityType)")
        }
    }

    private func negotiateSecurityTypes() async throws {
        let typeCount = try await receiveUInt8()
        if typeCount == 0 {
            let reasonLength = Int(try await receiveUInt32())
            let reason = try await receiveString(count: reasonLength)
            throw RFBClientError.securityNegotiationFailed(reason)
        }

        let data = try await receiveExact(count: Int(typeCount))
        let types = Array(data)
        if types.contains(2) {
            try await send(Data([2]))
            try await performVNCAuthentication()
            return
        }

        if types.contains(1) {
            try await send(Data([1]))
            let result = try await receiveUInt32()
            guard result == 0 else {
                let reason = try await readFailureReasonIfPresent()
                throw RFBClientError.authenticationFailed(reason ?? "security result \(result)")
            }
            return
        }

        throw RFBClientError.securityNegotiationFailed("No supported security type. Server offered: \(types)")
    }

    private func performVNCAuthentication() async throws {
        guard !configuration.password.isEmpty else {
            throw RFBClientError.missingPassword
        }

        let challenge = try await receiveExact(count: 16)
        let response = try VNCAuthentication.encryptChallenge(challenge, password: configuration.password)
        try await send(response)

        let result = try await receiveUInt32()
        guard result == 0 else {
            let reason = try await readFailureReasonIfPresent()
            throw RFBClientError.authenticationFailed(reason ?? "security result \(result)")
        }
    }

    private func readServerInit() async throws {
        let width = Int(try await receiveUInt16())
        let height = Int(try await receiveUInt16())
        guard width > 0, height > 0 else {
            throw RFBClientError.invalidFramebufferGeometry
        }

        let pixelFormatData = try await receiveExact(count: 16)
        activePixelFormat = try RFBPixelFormat(data: pixelFormatData)
        let nameLength = Int(try await receiveUInt32())
        desktopName = try await receiveString(count: nameLength)
        framebuffer = RFBFramebuffer(width: width, height: height)
    }

    private func setPixelFormat(_ pixelFormat: RFBPixelFormat) async throws {
        var data = Data([0, 0, 0, 0])
        data.append(pixelFormat.serialized)
        try await send(data)
        activePixelFormat = pixelFormat
    }

    private func setEncodings(_ encodings: [Int32]) async throws {
        var data = Data([2, 0])
        data.appendUInt16(UInt16(encodings.count))
        for encoding in encodings {
            data.appendInt32(encoding)
        }
        try await send(data)
    }

    private func requestFramebufferUpdate(incremental: Bool) async throws {
        var data = Data([3, incremental ? 1 : 0])
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(UInt16(framebuffer.width))
        data.appendUInt16(UInt16(framebuffer.height))
        try await send(data)
    }

    private func sendKeyEvent(isDown: Bool, keySymbol: UInt32) async throws {
        var data = Data([4, isDown ? 1 : 0, 0, 0])
        data.appendUInt32(keySymbol)
        try await send(data)
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled {
                let messageType = try await receiveUInt8()
                switch messageType {
                case 0:
                    try await handleFramebufferUpdate()
                    try await requestFramebufferUpdate(incremental: true)
                case 2:
                    if let onBell {
                        await onBell()
                    }
                    continue
                case 3:
                    _ = try await receiveUInt8()
                    _ = try await receiveUInt16()
                    let byteCount = Int(try await receiveUInt32())
                    let text = try await receiveString(count: byteCount)
                    if let onServerCutText {
                        await onServerCutText(text)
                    }
                default:
                    throw RFBClientError.invalidServerMessage(messageType)
                }
            }
        } catch {
            if Task.isCancelled {
                return
            }
        }
    }

    private func handleFramebufferUpdate() async throws {
        _ = try await receiveUInt8()
        let rectangleCount = Int(try await receiveUInt16())

        for _ in 0..<rectangleCount {
            let x = Int(try await receiveUInt16())
            let y = Int(try await receiveUInt16())
            let width = Int(try await receiveUInt16())
            let height = Int(try await receiveUInt16())
            let encoding = try await receiveInt32()

            switch encoding {
            case 0:
                let bytesPerPixel = activePixelFormat.bytesPerPixel
                let rawData = try await receiveExact(count: width * height * bytesPerPixel)
                framebuffer.applyRawRectangle(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    pixelFormat: activePixelFormat,
                    bytes: rawData
                )
            case 1:
                let sourceX = Int(try await receiveUInt16())
                let sourceY = Int(try await receiveUInt16())
                framebuffer.copyRectangle(
                    fromX: sourceX,
                    fromY: sourceY,
                    toX: x,
                    toY: y,
                    width: width,
                    height: height
                )
            case 2:
                try await handleRRERectangle(x: x, y: y, width: width, height: height)
            case 5:
                try await handleHextileRectangle(x: x, y: y, width: width, height: height)
            case 16:
                try await handleZRLERectangle(x: x, y: y, width: width, height: height)
            case -223:
                framebuffer.resize(width: width, height: height)
            case -224:
                break
            default:
                throw RFBClientError.unsupportedEncoding(encoding)
            }
        }

        await onFramebufferUpdate(makeSnapshot())
    }

    private func handleRRERectangle(x: Int, y: Int, width: Int, height: Int) async throws {
        let subrectangleCount = Int(try await receiveUInt32())
        let backgroundPixel = try await receivePixel()
        framebuffer.fillRectangle(
            x: x,
            y: y,
            width: width,
            height: height,
            pixel: backgroundPixel
        )

        for _ in 0..<subrectangleCount {
            let foregroundPixel = try await receivePixel()
            let subX = Int(try await receiveUInt16())
            let subY = Int(try await receiveUInt16())
            let subWidth = Int(try await receiveUInt16())
            let subHeight = Int(try await receiveUInt16())
            framebuffer.fillRectangle(
                x: x + subX,
                y: y + subY,
                width: subWidth,
                height: subHeight,
                pixel: foregroundPixel
            )
        }
    }

    private func handleHextileRectangle(x: Int, y: Int, width: Int, height: Int) async throws {
        var backgroundPixel: UInt32 = 0x181C24FF
        var foregroundPixel: UInt32 = 0xFFFFFFFF

        for tileY in stride(from: 0, to: height, by: 16) {
            for tileX in stride(from: 0, to: width, by: 16) {
                let tileWidth = min(16, width - tileX)
                let tileHeight = min(16, height - tileY)
                let subencoding = try await receiveUInt8()

                if (subencoding & 0b0000_0001) != 0 {
                    let rawBytes = try await receiveExact(count: tileWidth * tileHeight * activePixelFormat.bytesPerPixel)
                    framebuffer.applyRawRectangle(
                        x: x + tileX,
                        y: y + tileY,
                        width: tileWidth,
                        height: tileHeight,
                        pixelFormat: activePixelFormat,
                        bytes: rawBytes
                    )
                    continue
                }

                if (subencoding & 0b0000_0010) != 0 {
                    backgroundPixel = try await receivePixel()
                }
                framebuffer.fillRectangle(
                    x: x + tileX,
                    y: y + tileY,
                    width: tileWidth,
                    height: tileHeight,
                    pixel: backgroundPixel
                )

                if (subencoding & 0b0000_0100) != 0 {
                    foregroundPixel = try await receivePixel()
                }

                guard (subencoding & 0b0000_1000) != 0 else {
                    continue
                }

                let subrectangleCount = Int(try await receiveUInt8())
                let coloredSubrectangles = (subencoding & 0b0001_0000) != 0

                for _ in 0..<subrectangleCount {
                    let pixel = coloredSubrectangles ? (try await receivePixel()) : foregroundPixel
                    let xy = try await receiveUInt8()
                    let wh = try await receiveUInt8()
                    let subX = Int(xy >> 4)
                    let subY = Int(xy & 0x0F)
                    let subWidth = Int((wh >> 4) & 0x0F) + 1
                    let subHeight = Int(wh & 0x0F) + 1

                    framebuffer.fillRectangle(
                        x: x + tileX + subX,
                        y: y + tileY + subY,
                        width: subWidth,
                        height: subHeight,
                        pixel: pixel
                    )
                }
            }
        }
    }

    private func handleZRLERectangle(x: Int, y: Int, width: Int, height: Int) async throws {
        let compressedLength = Int(try await receiveUInt32())
        let compressedData = try await receiveExact(count: compressedLength)
        let decoded = try RFBZRLEDecoder.decompress(compressedData)
        var reader = RFBDataReader(data: decoded)
        try RFBZRLEDecoder.decodeRectangle(
            into: &framebuffer,
            pixelFormat: activePixelFormat,
            x: x,
            y: y,
            width: width,
            height: height,
            reader: &reader
        )
    }

    private func makeSnapshot() -> RFBFramebufferSnapshot {
        RFBFramebufferSnapshot(
            width: framebuffer.width,
            height: framebuffer.height,
            pixels: framebuffer.pixels,
            desktopName: desktopName
        )
    }

    private func readFailureReasonIfPresent() async throws -> String? {
        guard let connection else {
            return nil
        }

        switch connection.state {
        case .cancelled:
            return nil
        default:
            if receiveBuffer.isEmpty {
                return nil
            }

            let reasonLength = Int(try await receiveUInt32())
            return try await receiveString(count: reasonLength)
        }
    }

    private func send(_ data: Data) async throws {
        guard let connection else {
            throw RFBClientError.connectionClosed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: RFBClientError.transportFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveExact(count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let chunk = try await receiveChunk()
            guard !chunk.isEmpty else {
                throw RFBClientError.connectionClosed
            }
            receiveBuffer.append(chunk)
        }

        let output = receiveBuffer.prefix(count)
        receiveBuffer.removeFirst(count)
        return Data(output)
    }

    private func receiveChunk() async throws -> Data {
        guard let connection else {
            throw RFBClientError.connectionClosed
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: RFBClientError.transportFailed(error.localizedDescription))
                    return
                }

                if isComplete, (data == nil || data?.isEmpty == true) {
                    continuation.resume(returning: Data())
                    return
                }

                continuation.resume(returning: data ?? Data())
            }
        }
    }

    private func receiveUInt8() async throws -> UInt8 {
        let data = try await receiveExact(count: 1)
        return data[data.startIndex]
    }

    private func receiveUInt16() async throws -> UInt16 {
        let data = try await receiveExact(count: 2)
        return UInt16(bigEndian: data.readUnalignedUInt16(at: 0))
    }

    private func receiveUInt32() async throws -> UInt32 {
        let data = try await receiveExact(count: 4)
        return UInt32(bigEndian: data.readUnalignedUInt32(at: 0))
    }

    private func receiveInt32() async throws -> Int32 {
        let value = try await receiveUInt32()
        return Int32(bitPattern: value)
    }

    private func receivePixel() async throws -> UInt32 {
        let data = try await receiveExact(count: activePixelFormat.bytesPerPixel)
        return data.withUnsafeBytes { pointer in
            let baseAddress = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self)
            guard let baseAddress else {
                return UInt32(0)
            }
            return activePixelFormat.decodePixel(
                bytes: UnsafeBufferPointer(start: baseAddress, count: activePixelFormat.bytesPerPixel)
            )
        }
    }

    private func receiveString(count: Int) async throws -> String {
        let data = try await receiveExact(count: count)
        return String(decoding: data, as: UTF8.self)
    }

    private func preferredEncodings(for preset: VNCQualityPreset) -> [Int32] {
        switch preset {
        case .low:
            return [16, 5, 2, 1, 0, -223, -224]
        case .balanced:
            return [16, 5, 1, 2, 0, -223, -224]
        case .high:
            return [16, 5, 0, 1, 2, -223, -224]
        }
    }
}

private struct RFBFramebuffer {
    var width: Int
    var height: Int
    var pixels: [UInt32]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: 0x181C24FF, count: max(0, width * height))
    }

    mutating func applyRawRectangle(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixelFormat: RFBPixelFormat,
        bytes: Data
    ) {
        let bytesPerPixel = pixelFormat.bytesPerPixel
        guard width > 0, height > 0, bytes.count >= width * height * bytesPerPixel else {
            return
        }

        bytes.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for row in 0..<height {
                for column in 0..<width {
                    let offset = (row * width + column) * bytesPerPixel
                    let pixel = pixelFormat.decodePixel(bytes: UnsafeBufferPointer(start: baseAddress + offset, count: bytesPerPixel))
                    let destinationX = x + column
                    let destinationY = y + row
                    guard destinationX >= 0, destinationX < self.width, destinationY >= 0, destinationY < self.height else {
                        continue
                    }

                    pixels[destinationY * self.width + destinationX] = pixel
                }
            }
        }
    }

    mutating func fillRectangle(x: Int, y: Int, width: Int, height: Int, pixel: UInt32) {
        guard width > 0, height > 0 else {
            return
        }

        for row in 0..<height {
            for column in 0..<width {
                let destinationX = x + column
                let destinationY = y + row
                guard destinationX >= 0, destinationX < self.width, destinationY >= 0, destinationY < self.height else {
                    continue
                }

                pixels[destinationY * self.width + destinationX] = pixel
            }
        }
    }

    mutating func setPixel(x: Int, y: Int, pixel: UInt32) {
        guard x >= 0, x < width, y >= 0, y < height else {
            return
        }

        pixels[y * width + x] = pixel
    }

    mutating func copyRectangle(fromX: Int, fromY: Int, toX: Int, toY: Int, width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return
        }

        let snapshot = pixels
        for row in 0..<height {
            for column in 0..<width {
                let sourceX = fromX + column
                let sourceY = fromY + row
                let destinationX = toX + column
                let destinationY = toY + row

                guard sourceX >= 0, sourceX < self.width,
                      sourceY >= 0, sourceY < self.height,
                      destinationX >= 0, destinationX < self.width,
                      destinationY >= 0, destinationY < self.height else {
                    continue
                }

                pixels[destinationY * self.width + destinationX] = snapshot[sourceY * self.width + sourceX]
            }
        }
    }

    mutating func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: 0x181C24FF, count: max(0, width * height))
    }
}

struct RFBPixelFormat {
    var bitsPerPixel: UInt8
    var depth: UInt8
    var isBigEndian: Bool
    var isTrueColor: Bool
    var redMax: UInt16
    var greenMax: UInt16
    var blueMax: UInt16
    var redShift: UInt8
    var greenShift: UInt8
    var blueShift: UInt8

    static let clientPreferred = RFBPixelFormat(
        bitsPerPixel: 32,
        depth: 24,
        isBigEndian: false,
        isTrueColor: true,
        redMax: 255,
        greenMax: 255,
        blueMax: 255,
        redShift: 16,
        greenShift: 8,
        blueShift: 0
    )

    init(
        bitsPerPixel: UInt8,
        depth: UInt8,
        isBigEndian: Bool,
        isTrueColor: Bool,
        redMax: UInt16,
        greenMax: UInt16,
        blueMax: UInt16,
        redShift: UInt8,
        greenShift: UInt8,
        blueShift: UInt8
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.isBigEndian = isBigEndian
        self.isTrueColor = isTrueColor
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    init(data: Data) throws {
        guard data.count == 16 else {
            throw RFBClientError.transportFailed("Invalid pixel format payload")
        }

        bitsPerPixel = data[0]
        depth = data[1]
        isBigEndian = data[2] != 0
        isTrueColor = data[3] != 0
        redMax = UInt16(bigEndian: data.readUnalignedUInt16(at: 4))
        greenMax = UInt16(bigEndian: data.readUnalignedUInt16(at: 6))
        blueMax = UInt16(bigEndian: data.readUnalignedUInt16(at: 8))
        redShift = data[10]
        greenShift = data[11]
        blueShift = data[12]
    }

    var bytesPerPixel: Int {
        max(1, Int(bitsPerPixel / 8))
    }

    var serialized: Data {
        var data = Data()
        data.append(bitsPerPixel)
        data.append(depth)
        data.append(isBigEndian ? 1 : 0)
        data.append(isTrueColor ? 1 : 0)
        data.appendUInt16(redMax)
        data.appendUInt16(greenMax)
        data.appendUInt16(blueMax)
        data.append(redShift)
        data.append(greenShift)
        data.append(blueShift)
        data.append(contentsOf: [0, 0, 0])
        return data
    }

    func decodePixel(bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
        guard isTrueColor else {
            let value = UInt32(bytes.first ?? 0)
            return (value << 24) | (value << 16) | (value << 8) | 0xFF
        }

        var rawValue: UInt32 = 0
        if isBigEndian {
            for byte in bytes {
                rawValue = (rawValue << 8) | UInt32(byte)
            }
        } else {
            for (index, byte) in bytes.enumerated() {
                rawValue |= UInt32(byte) << UInt32(index * 8)
            }
        }

        let red = scale(component: (rawValue >> UInt32(redShift)) & UInt32(redMax), max: redMax)
        let green = scale(component: (rawValue >> UInt32(greenShift)) & UInt32(greenMax), max: greenMax)
        let blue = scale(component: (rawValue >> UInt32(blueShift)) & UInt32(blueMax), max: blueMax)
        return (red << 24) | (green << 16) | (blue << 8) | 0xFF
    }

    private func scale(component: UInt32, max: UInt16) -> UInt32 {
        guard max > 0 else {
            return 0
        }

        return (component * 255) / UInt32(max)
    }
}

enum RFBKeySymbolTranslator {
    static func keySymbols(for text: String) -> [UInt32] {
        if text == "\u{001B}[A" {
            return [0xFF52]
        }

        if text == "\u{001B}[B" {
            return [0xFF54]
        }

        if text == "\u{001B}[C" {
            return [0xFF53]
        }

        if text == "\u{001B}[D" {
            return [0xFF51]
        }

        var result: [UInt32] = []
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A:
                result.append(0xFF0D)
            case 0x09:
                result.append(0xFF09)
            case 0x08, 0x7F:
                result.append(0xFF08)
            case 0x1B:
                result.append(0xFF1B)
            default:
                result.append(scalar.value)
            }
        }
        return result
    }
}

enum VNCAuthentication {
    static func encryptChallenge(_ challenge: Data, password: String) throws -> Data {
        let key = makeDESKey(from: password)
        return try encryptDESBlock(challenge, key: key)
    }

    static func makeDESKey(from password: String) -> Data {
        let bytes = Array(password.utf8.prefix(8))
        var keyBytes = Array(repeating: UInt8(0), count: 8)

        for index in 0..<8 {
            let byte = index < bytes.count ? bytes[index] : 0
            keyBytes[index] = reverseBits(byte)
        }

        return Data(keyBytes)
    }

    private static func encryptDESBlock(_ challenge: Data, key: Data) throws -> Data {
        precondition(challenge.count == 16)
        precondition(key.count == 8)

        var output = Data(count: challenge.count)
        let outputCount = output.count
        var encryptedBytes = 0

        let status = output.withUnsafeMutableBytes { outputPointer in
            challenge.withUnsafeBytes { inputPointer in
                key.withUnsafeBytes { keyPointer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionECBMode),
                        keyPointer.baseAddress,
                        key.count,
                        nil,
                        inputPointer.baseAddress,
                        challenge.count,
                        outputPointer.baseAddress,
                        outputCount,
                        &encryptedBytes
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw RFBClientError.authenticationFailed("DES encryption failed with status \(status)")
        }

        output.removeSubrange(encryptedBytes..<output.count)
        return output
    }

    private static func reverseBits(_ value: UInt8) -> UInt8 {
        var input = value
        var result: UInt8 = 0
        for _ in 0..<8 {
            result = (result << 1) | (input & 1)
            input >>= 1
        }
        return result
    }
}

struct RFBDataReader {
    let data: Data
    private(set) var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset >= data.count
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw RFBClientError.transportFailed("Unexpected end of ZRLE payload")
        }

        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw RFBClientError.transportFailed("Unexpected end of ZRLE payload")
        }

        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func readPixel(format: RFBPixelFormat) throws -> UInt32 {
        let bytes = try readBytes(count: format.bytesPerPixel)
        return bytes.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(0)
            }
            return format.decodePixel(bytes: UnsafeBufferPointer(start: baseAddress, count: format.bytesPerPixel))
        }
    }
}

enum RFBZRLEDecoder {
    static func decompress(_ compressedData: Data) throws -> Data {
        if compressedData.isEmpty {
            return Data()
        }

        let destinationBufferSize = max(64 * 1024, compressedData.count * 8)
        let dummyDestination = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        dummyDestination.initialize(to: 0)
        let dummySource = UnsafePointer(dummyDestination)
        var stream = compression_stream(
            dst_ptr: dummyDestination,
            dst_size: 0,
            src_ptr: dummySource,
            src_size: 0,
            state: nil
        )
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw RFBClientError.transportFailed("Failed to initialize ZRLE decompressor")
        }
        defer {
            compression_stream_destroy(&stream)
            dummyDestination.deinitialize(count: 1)
            dummyDestination.deallocate()
        }

        return try compressedData.withUnsafeBytes { sourcePointer in
            guard let sourceBase = sourcePointer.bindMemory(to: UInt8.self).baseAddress else {
                return Data()
            }

            var output = Data()
            var scratch = [UInt8](repeating: 0, count: destinationBufferSize)

            stream.src_ptr = sourceBase
            stream.src_size = compressedData.count

            repeat {
                let scratchCount = scratch.count
                let decodedCount = try scratch.withUnsafeMutableBytes { scratchPointer -> Int in
                    guard let destinationBase = scratchPointer.bindMemory(to: UInt8.self).baseAddress else {
                        throw RFBClientError.transportFailed("Failed to allocate ZRLE buffer")
                    }

                    stream.dst_ptr = destinationBase
                    stream.dst_size = scratchCount
                    status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw RFBClientError.transportFailed("Failed to decompress ZRLE payload")
                    }
                    return scratchCount - stream.dst_size
                }

                if decodedCount > 0 {
                    output.append(scratch, count: decodedCount)
                }
            } while status == COMPRESSION_STATUS_OK

            return output
        }
    }

    fileprivate static func decodeRectangle(
        into framebuffer: inout RFBFramebuffer,
        pixelFormat: RFBPixelFormat,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        reader: inout RFBDataReader
    ) throws {
        for tileY in stride(from: 0, to: height, by: 64) {
            for tileX in stride(from: 0, to: width, by: 64) {
                let tileWidth = min(64, width - tileX)
                let tileHeight = min(64, height - tileY)
                try decodeTile(
                    into: &framebuffer,
                    pixelFormat: pixelFormat,
                    x: x + tileX,
                    y: y + tileY,
                    width: tileWidth,
                    height: tileHeight,
                    reader: &reader
                )
            }
        }
    }

    static func decodePixelsForTesting(
        payload: Data,
        pixelFormat: RFBPixelFormat,
        width: Int,
        height: Int
    ) throws -> [UInt32] {
        var framebuffer = RFBFramebuffer(width: width, height: height)
        var reader = RFBDataReader(data: payload)
        try decodeRectangle(
            into: &framebuffer,
            pixelFormat: pixelFormat,
            x: 0,
            y: 0,
            width: width,
            height: height,
            reader: &reader
        )
        return framebuffer.pixels
    }

    fileprivate static func decodeTile(
        into framebuffer: inout RFBFramebuffer,
        pixelFormat: RFBPixelFormat,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        reader: inout RFBDataReader
    ) throws {
        let mode = Int(try reader.readUInt8())
        let isRunLengthEncoded = (mode & 0x80) != 0
        let paletteSize = mode & 0x7F

        if !isRunLengthEncoded && paletteSize == 0 {
            let rawBytes = try reader.readBytes(count: width * height * pixelFormat.bytesPerPixel)
            framebuffer.applyRawRectangle(
                x: x,
                y: y,
                width: width,
                height: height,
                pixelFormat: pixelFormat,
                bytes: rawBytes
            )
            return
        }

        let palette = try readPalette(count: paletteSize, pixelFormat: pixelFormat, reader: &reader)

        if !isRunLengthEncoded {
            if paletteSize == 1, let color = palette.first {
                framebuffer.fillRectangle(x: x, y: y, width: width, height: height, pixel: color)
                return
            }

            try decodePackedPaletteTile(
                into: &framebuffer,
                palette: palette,
                x: x,
                y: y,
                width: width,
                height: height,
                reader: &reader
            )
            return
        }

        if paletteSize == 0 {
            try decodePlainRLETile(
                into: &framebuffer,
                pixelFormat: pixelFormat,
                x: x,
                y: y,
                width: width,
                height: height,
                reader: &reader
            )
            return
        }

        try decodePaletteRLETile(
            into: &framebuffer,
            palette: palette,
            x: x,
            y: y,
            width: width,
            height: height,
            reader: &reader
        )
    }

    private static func readPalette(
        count: Int,
        pixelFormat: RFBPixelFormat,
        reader: inout RFBDataReader
    ) throws -> [UInt32] {
        if count == 0 {
            return []
        }

        var palette: [UInt32] = []
        palette.reserveCapacity(count)
        for _ in 0..<count {
            palette.append(try reader.readPixel(format: pixelFormat))
        }
        return palette
    }

    fileprivate static func decodePackedPaletteTile(
        into framebuffer: inout RFBFramebuffer,
        palette: [UInt32],
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        reader: inout RFBDataReader
    ) throws {
        guard !palette.isEmpty else {
            throw RFBClientError.transportFailed("ZRLE packed palette tile is missing palette colors")
        }

        let bitsPerIndex: Int
        switch palette.count {
        case 2:
            bitsPerIndex = 1
        case 3...4:
            bitsPerIndex = 2
        case 5...16:
            bitsPerIndex = 4
        default:
            throw RFBClientError.transportFailed("Unsupported ZRLE packed palette size: \(palette.count)")
        }

        let mask = (1 << bitsPerIndex) - 1
        let bytesPerRow = (width * bitsPerIndex + 7) / 8

        for row in 0..<height {
            let rowBytes = try reader.readBytes(count: bytesPerRow)
            var bitOffset = 0

            for column in 0..<width {
                let byteIndex = bitOffset / 8
                let intraByteOffset = bitOffset % 8
                let byteValue = Int(rowBytes[rowBytes.startIndex + byteIndex])
                let shift = 8 - bitsPerIndex - intraByteOffset
                let paletteIndex = (byteValue >> shift) & mask
                guard paletteIndex < palette.count else {
                    throw RFBClientError.transportFailed("ZRLE palette index out of range")
                }

                framebuffer.setPixel(x: x + column, y: y + row, pixel: palette[paletteIndex])
                bitOffset += bitsPerIndex
            }
        }
    }

    fileprivate static func decodePlainRLETile(
        into framebuffer: inout RFBFramebuffer,
        pixelFormat: RFBPixelFormat,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        reader: inout RFBDataReader
    ) throws {
        let totalPixels = width * height
        var writtenPixels = 0

        while writtenPixels < totalPixels {
            let pixel = try reader.readPixel(format: pixelFormat)
            let runLength = try readRunLength(reader: &reader)
            try writeRun(
                into: &framebuffer,
                x: x,
                y: y,
                width: width,
                totalPixels: totalPixels,
                writtenPixels: &writtenPixels,
                runLength: runLength,
                pixel: pixel
            )
        }
    }

    fileprivate static func decodePaletteRLETile(
        into framebuffer: inout RFBFramebuffer,
        palette: [UInt32],
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        reader: inout RFBDataReader
    ) throws {
        guard !palette.isEmpty else {
            throw RFBClientError.transportFailed("ZRLE palette RLE tile is missing palette colors")
        }

        let totalPixels = width * height
        var writtenPixels = 0

        while writtenPixels < totalPixels {
            let encodedIndex = Int(try reader.readUInt8())
            let paletteIndex = encodedIndex & 0x7F
            guard paletteIndex < palette.count else {
                throw RFBClientError.transportFailed("ZRLE palette RLE index out of range")
            }

            let runLength = (encodedIndex & 0x80) != 0 ? (try readRunLength(reader: &reader)) : 1
            try writeRun(
                into: &framebuffer,
                x: x,
                y: y,
                width: width,
                totalPixels: totalPixels,
                writtenPixels: &writtenPixels,
                runLength: runLength,
                pixel: palette[paletteIndex]
            )
        }
    }

    private static func readRunLength(reader: inout RFBDataReader) throws -> Int {
        var runLength = 1
        while true {
            let extensionByte = Int(try reader.readUInt8())
            runLength += extensionByte
            if extensionByte < 255 {
                return runLength
            }
        }
    }

    fileprivate static func writeRun(
        into framebuffer: inout RFBFramebuffer,
        x: Int,
        y: Int,
        width: Int,
        totalPixels: Int,
        writtenPixels: inout Int,
        runLength: Int,
        pixel: UInt32
    ) throws {
        guard runLength > 0, writtenPixels + runLength <= totalPixels else {
            throw RFBClientError.transportFailed("Invalid ZRLE run length")
        }

        for _ in 0..<runLength {
            let localY = writtenPixels / width
            let localX = writtenPixels % width
            framebuffer.setPixel(x: x + localX, y: y + localY, pixel: pixel)
            writtenPixels += 1
        }
    }
}

enum RFBHextileDecoder {
    static func decodePixelsForTesting(
        payload: Data,
        pixelFormat: RFBPixelFormat,
        width: Int,
        height: Int
    ) throws -> [UInt32] {
        var framebuffer = RFBFramebuffer(width: width, height: height)
        var reader = RFBDataReader(data: payload)
        var backgroundPixel: UInt32 = 0x181C24FF
        var foregroundPixel: UInt32 = 0xFFFFFFFF

        for tileY in stride(from: 0, to: height, by: 16) {
            for tileX in stride(from: 0, to: width, by: 16) {
                let tileWidth = min(16, width - tileX)
                let tileHeight = min(16, height - tileY)
                let subencoding = try reader.readUInt8()

                if (subencoding & 0b0000_0001) != 0 {
                    let rawBytes = try reader.readBytes(count: tileWidth * tileHeight * pixelFormat.bytesPerPixel)
                    framebuffer.applyRawRectangle(
                        x: tileX,
                        y: tileY,
                        width: tileWidth,
                        height: tileHeight,
                        pixelFormat: pixelFormat,
                        bytes: rawBytes
                    )
                    continue
                }

                if (subencoding & 0b0000_0010) != 0 {
                    backgroundPixel = try reader.readPixel(format: pixelFormat)
                }

                framebuffer.fillRectangle(
                    x: tileX,
                    y: tileY,
                    width: tileWidth,
                    height: tileHeight,
                    pixel: backgroundPixel
                )

                if (subencoding & 0b0000_0100) != 0 {
                    foregroundPixel = try reader.readPixel(format: pixelFormat)
                }

                guard (subencoding & 0b0000_1000) != 0 else {
                    continue
                }

                let subrectangleCount = Int(try reader.readUInt8())
                let coloredSubrectangles = (subencoding & 0b0001_0000) != 0
                for _ in 0..<subrectangleCount {
                    let pixel = coloredSubrectangles ? (try reader.readPixel(format: pixelFormat)) : foregroundPixel
                    let xy = try reader.readUInt8()
                    let wh = try reader.readUInt8()
                    let subX = Int(xy >> 4)
                    let subY = Int(xy & 0x0F)
                    let subWidth = Int((wh >> 4) & 0x0F) + 1
                    let subHeight = Int(wh & 0x0F) + 1

                    framebuffer.fillRectangle(
                        x: tileX + subX,
                        y: tileY + subY,
                        width: subWidth,
                        height: subHeight,
                        pixel: pixel
                    )
                }
            }
        }

        return framebuffer.pixels
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    func readUnalignedUInt16(at offset: Int) -> UInt16 {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: 2)
        return subdata(in: start..<end).withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    func readUnalignedUInt32(at offset: Int) -> UInt32 {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: 4)
        return subdata(in: start..<end).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}
