import Foundation
import Security

public struct KeychainStoreError: LocalizedError, Sendable {
    public let operation: String
    public let status: OSStatus

    public init(operation: String, status: OSStatus) {
        self.operation = operation
        self.status = status
    }

    public var errorDescription: String? {
        let systemMessage = SecCopyErrorMessageString(status, nil) as String?
        return "\(operation) failed: \(systemMessage ?? "OSStatus \(status)")"
    }
}

public actor KeychainStore {
    public enum Mode: Sendable {
        case live
        case inMemory
    }

    private let mode: Mode
    private var inMemoryValues: [String: Data] = [:]

    public init(mode: Mode = .live) {
        self.mode = mode
    }

    public func readData(service: String, account: String) throws -> Data? {
        switch mode {
        case .live:
            return try readLiveData(service: service, account: account)
        case .inMemory:
            return inMemoryValues[storageKey(service: service, account: account)]
        }
    }

    public func writeData(_ data: Data, service: String, account: String) throws {
        switch mode {
        case .live:
            try writeLiveData(data, service: service, account: account)
        case .inMemory:
            inMemoryValues[storageKey(service: service, account: account)] = data
        }
    }

    public func deleteData(service: String, account: String) throws {
        switch mode {
        case .live:
            try deleteLiveData(service: service, account: account)
        case .inMemory:
            inMemoryValues.removeValue(forKey: storageKey(service: service, account: account))
        }
    }

    private func storageKey(service: String, account: String) -> String {
        "\(service)|\(account)"
    }

    private func readLiveData(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError(operation: "Read keychain item", status: status)
        }
    }

    private func writeLiveData(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let updateAttributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError(operation: "Add keychain item", status: addStatus)
            }

            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainStoreError(operation: "Update keychain item", status: updateStatus)
        }
    }

    private func deleteLiveData(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(operation: "Delete keychain item", status: status)
        }
    }

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
