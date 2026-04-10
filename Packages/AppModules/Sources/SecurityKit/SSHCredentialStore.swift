import Foundation

public struct SSHCredentialIdentity: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var username: String

    public init(host: String, port: Int, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }

    public var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var account: String {
        "\(normalizedHost):\(port):\(username)"
    }
}

public actor SSHCredentialStore {
    public static let passwordService = "AdminConsole.SSH.Password"

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    @discardableResult
    public func savePassword(_ password: String, for identity: SSHCredentialIdentity) async throws -> KeychainCredentialReference {
        let reference = KeychainCredentialReference(service: Self.passwordService, account: identity.account)
        let data = Data(password.utf8)
        try await keychain.writeData(data, service: reference.service, account: reference.account)
        return reference
    }

    public func password(for identity: SSHCredentialIdentity) async throws -> String? {
        let reference = KeychainCredentialReference(service: Self.passwordService, account: identity.account)
        guard let data = try await keychain.readData(service: reference.service, account: reference.account) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func deletePassword(for identity: SSHCredentialIdentity) async throws {
        try await keychain.deleteData(service: Self.passwordService, account: identity.account)
    }
}
