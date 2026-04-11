@testable import VNCKit
import XCTest

final class VNCReconnectPolicyTests: XCTestCase {
    func testNetworkErrorsAreRetriable() {
        XCTAssertTrue(VNCReconnectPolicy.shouldRetry(RFBClientError.connectionClosed))
        XCTAssertTrue(VNCReconnectPolicy.shouldRetry(RFBClientError.transportFailed("timeout")))
    }

    func testAuthenticationErrorsAreNotRetriable() {
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.missingPassword))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.authenticationFailed("denied")))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.unsupportedAuthentication))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.securityNegotiationFailed("rejected")))
    }

    func testProtocolErrorsAreNotRetriable() {
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.invalidProtocolVersion("RFB 004.000")))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.unsupportedEncoding(999)))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.invalidServerMessage(0xFF)))
        XCTAssertFalse(VNCReconnectPolicy.shouldRetry(RFBClientError.invalidFramebufferGeometry))
    }

    func testBackoffDelayIsExponentialAndCapped() {
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 1), 1)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 2), 2)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 3), 4)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 4), 8)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 5), 16)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 6), 30)
        XCTAssertEqual(VNCReconnectPolicy.delaySeconds(forAttempt: 12), 30)
    }

    func testUserFacingStatusContainsCategory() {
        let authStatus = VNCReconnectPolicy.userFacingStatus(for: RFBClientError.authenticationFailed("bad password"))
        XCTAssertTrue(authStatus.hasPrefix("Authentication issue:"))

        let networkStatus = VNCReconnectPolicy.userFacingStatus(for: RFBClientError.connectionClosed)
        XCTAssertTrue(networkStatus.hasPrefix("Network issue:"))

        let protocolStatus = VNCReconnectPolicy.userFacingStatus(for: RFBClientError.unsupportedEncoding(16))
        XCTAssertTrue(protocolStatus.hasPrefix("Protocol issue:"))
    }
}
