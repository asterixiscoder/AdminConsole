import CryptoKit
import Foundation

public struct SSHKnownHostRecord: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var algorithm: String
    public var openSSHPublicKey: String
    public var fingerprintSHA256: String
    public var trustedAt: Date

    public init(
        host: String,
        port: Int,
        algorithm: String,
        openSSHPublicKey: String,
        fingerprintSHA256: String,
        trustedAt: Date
    ) {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.openSSHPublicKey = openSSHPublicKey
        self.fingerprintSHA256 = fingerprintSHA256
        self.trustedAt = trustedAt
    }
}

public enum SSHKnownHostValidationOutcome: Equatable, Sendable {
    case trustedFirstUse(SSHKnownHostRecord)
    case trustedExisting(SSHKnownHostRecord)
}

public enum SSHKnownHostValidationError: LocalizedError, Sendable {
    case invalidHostKeyFormat
    case hostKeyMismatch(host: String, port: Int, expectedFingerprint: String, receivedFingerprint: String)

    public var errorDescription: String? {
        switch self {
        case .invalidHostKeyFormat:
            return "The SSH server returned an invalid host key."
        case .hostKeyMismatch(let host, let port, let expectedFingerprint, let receivedFingerprint):
            return "Host key mismatch for \(host):\(port). Expected SHA256:\(expectedFingerprint), received SHA256:\(receivedFingerprint)."
        }
    }
}

public actor SSHHostKeyTrustStore {
    public static let knownHostService = "AdminConsole.SSH.KnownHost"

    private let keychain: KeychainStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func knownHost(host: String, port: Int) async throws -> SSHKnownHostRecord? {
        let reference = keychainReference(host: host, port: port)
        guard let data = try await keychain.readData(service: reference.service, account: reference.account) else {
            return nil
        }

        return try decoder.decode(SSHKnownHostRecord.self, from: data)
    }

    @discardableResult
    public func validateOrTrustOnFirstUse(
        host: String,
        port: Int,
        openSSHPublicKey: String,
        trustedAt: Date = Date()
    ) async throws -> SSHKnownHostValidationOutcome {
        let candidateRecord = try makeRecord(
            host: host,
            port: port,
            openSSHPublicKey: openSSHPublicKey,
            trustedAt: trustedAt
        )

        if let storedRecord = try await knownHost(host: host, port: port) {
            guard storedRecord.openSSHPublicKey == candidateRecord.openSSHPublicKey else {
                throw SSHKnownHostValidationError.hostKeyMismatch(
                    host: host,
                    port: port,
                    expectedFingerprint: storedRecord.fingerprintSHA256,
                    receivedFingerprint: candidateRecord.fingerprintSHA256
                )
            }

            return .trustedExisting(storedRecord)
        }

        let reference = keychainReference(host: host, port: port)
        let data = try encoder.encode(candidateRecord)
        try await keychain.writeData(data, service: reference.service, account: reference.account)
        return .trustedFirstUse(candidateRecord)
    }

    private func keychainReference(host: String, port: Int) -> KeychainCredentialReference {
        KeychainCredentialReference(
            service: Self.knownHostService,
            account: "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
        )
    }

    private func makeRecord(
        host: String,
        port: Int,
        openSSHPublicKey: String,
        trustedAt: Date
    ) throws -> SSHKnownHostRecord {
        let parts = openSSHPublicKey.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let keyData = Data(base64Encoded: String(parts[1])) else {
            throw SSHKnownHostValidationError.invalidHostKeyFormat
        }

        let digest = SHA256.hash(data: keyData)
        let fingerprint = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))

        return SSHKnownHostRecord(
            host: host,
            port: port,
            algorithm: String(parts[0]),
            openSSHPublicKey: openSSHPublicKey,
            fingerprintSHA256: fingerprint,
            trustedAt: trustedAt
        )
    }
}
