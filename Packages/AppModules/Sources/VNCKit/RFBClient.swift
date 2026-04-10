import ConnectionKit
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
            return "This VNC server requires password authentication. The current transport supports security type None only."
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
    private let configuration: VNCSessionConfiguration
    private let queue: DispatchQueue
    private let onFramebufferUpdate: @Sendable (RFBFramebufferSnapshot) async -> Void

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var stateContinuation: CheckedContinuation<Void, Error>?
    private var activePixelFormat = RFBPixelFormat.clientPreferred
    private var framebuffer = RFBFramebuffer(width: 0, height: 0)
    private var desktopName = "Remote Desktop"
    private var receiveTask: Task<Void, Never>?

    public init(
        configuration: VNCSessionConfiguration,
        onFramebufferUpdate: @escaping @Sendable (RFBFramebufferSnapshot) async -> Void
    ) {
        self.configuration = configuration
        self.onFramebufferUpdate = onFramebufferUpdate
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
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: 1)
        try await movePointer(normalizedX: normalizedX, normalizedY: normalizedY, buttonMask: 0)
    }

    public func send(text: String) async throws {
        for keySymbol in RFBKeySymbolTranslator.keySymbols(for: text) {
            try await sendKeyEvent(isDown: true, keySymbol: keySymbol)
            try await sendKeyEvent(isDown: false, keySymbol: keySymbol)
        }
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

        let negotiatedVersion: String
        if versionString.hasPrefix("RFB 003.003") {
            negotiatedVersion = "RFB 003.003\n"
        } else if versionString.hasPrefix("RFB 003.007") {
            negotiatedVersion = "RFB 003.007\n"
        } else if versionString.hasPrefix("RFB 003.008") {
            negotiatedVersion = "RFB 003.008\n"
        } else {
            throw RFBClientError.invalidProtocolVersion(versionString.trimmingCharacters(in: .newlines))
        }

        try await send(Data(negotiatedVersion.utf8))
        if negotiatedVersion == "RFB 003.003\n" {
            try await negotiateSecurityForRFB33()
        } else {
            try await negotiateSecurityTypes()
        }

        try await send(Data([1]))
        try await readServerInit()
        try await setPixelFormat(activePixelFormat)
        try await setEncodings([0])
    }

    private func negotiateSecurityForRFB33() async throws {
        let securityType = try await receiveUInt32()
        switch securityType {
        case 1:
            return
        case 2:
            throw RFBClientError.unsupportedAuthentication
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
        if types.contains(1) {
            try await send(Data([1]))
            let result = try await receiveUInt32()
            guard result == 0 else {
                let reason = try await readFailureReasonIfPresent()
                throw RFBClientError.authenticationFailed(reason ?? "security result \(result)")
            }
            return
        }

        if types.contains(2) {
            throw RFBClientError.unsupportedAuthentication
        }

        throw RFBClientError.securityNegotiationFailed("No supported security type. Server offered: \(types)")
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
                    continue
                case 3:
                    _ = try await receiveUInt8()
                    _ = try await receiveUInt16()
                    let byteCount = Int(try await receiveUInt32())
                    _ = try await receiveExact(count: byteCount)
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

            guard encoding == 0 else {
                throw RFBClientError.unsupportedEncoding(encoding)
            }

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
        }

        await onFramebufferUpdate(makeSnapshot())
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

    private func receiveString(count: Int) async throws -> String {
        let data = try await receiveExact(count: count)
        return String(decoding: data, as: UTF8.self)
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
