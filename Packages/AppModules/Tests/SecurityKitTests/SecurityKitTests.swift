import SecurityKit
import XCTest

final class SecurityKitTests: XCTestCase {
    func testCredentialStoreSavesAndReadsPassword() async throws {
        let keychain = KeychainStore(mode: .inMemory)
        let store = SSHCredentialStore(keychain: keychain)
        let identity = SSHCredentialIdentity(host: "server.example.com", port: 22, username: "root")

        _ = try await store.savePassword("secret", for: identity)
        let password = try await store.password(for: identity)

        XCTAssertEqual(password, "secret")
    }

    func testHostKeyTrustStoreUsesTrustOnFirstUseAndRejectsMismatch() async throws {
        let keychain = KeychainStore(mode: .inMemory)
        let store = SSHHostKeyTrustStore(keychain: keychain)
        let host = "server.example.com"
        let port = 22
        let firstKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzBv6JqqPiR+jYwIV/pY5Pja/qvpDMAYA9Yg3gCBXlI"
        let secondKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG8A0rB7Yv7FpC18JNpDutLCRa14Q6gttxyPjdvVSxG1"

        let firstOutcome = try await store.validateOrTrustOnFirstUse(
            host: host,
            port: port,
            openSSHPublicKey: firstKey
        )

        guard case .trustedFirstUse(let firstRecord) = firstOutcome else {
            return XCTFail("Expected first-use trust")
        }

        XCTAssertEqual(firstRecord.algorithm, "ssh-ed25519")
        XCTAssertFalse(firstRecord.fingerprintSHA256.isEmpty)

        let secondOutcome = try await store.validateOrTrustOnFirstUse(
            host: host,
            port: port,
            openSSHPublicKey: firstKey
        )

        guard case .trustedExisting(let existingRecord) = secondOutcome else {
            return XCTFail("Expected existing trust")
        }

        XCTAssertEqual(existingRecord, firstRecord)

        do {
            _ = try await store.validateOrTrustOnFirstUse(
                host: host,
                port: port,
                openSSHPublicKey: secondKey
            )
            XCTFail("Expected host key mismatch")
        } catch let error as SSHKnownHostValidationError {
            switch error {
            case .hostKeyMismatch(let mismatchHost, let mismatchPort, let expectedFingerprint, let receivedFingerprint):
                XCTAssertEqual(mismatchHost, host)
                XCTAssertEqual(mismatchPort, port)
                XCTAssertEqual(expectedFingerprint, firstRecord.fingerprintSHA256)
                XCTAssertNotEqual(receivedFingerprint, expectedFingerprint)
            case .invalidHostKeyFormat:
                XCTFail("Expected host key mismatch, got invalid format")
            }
        }
    }
}
