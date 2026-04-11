import Foundation

enum VNCFailureCategory: String, Sendable {
    case network
    case authentication
    case protocolViolation
    case unknown

    var title: String {
        switch self {
        case .network:
            return "Network"
        case .authentication:
            return "Authentication"
        case .protocolViolation:
            return "Protocol"
        case .unknown:
            return "Unknown"
        }
    }
}

enum VNCReconnectPolicy {
    static func classify(_ error: Error) -> VNCFailureCategory {
        guard let clientError = error as? RFBClientError else {
            return .unknown
        }

        switch clientError {
        case .connectionClosed, .transportFailed:
            return .network
        case .missingPassword, .authenticationFailed, .unsupportedAuthentication, .securityNegotiationFailed:
            return .authentication
        case .invalidProtocolVersion, .unsupportedEncoding, .invalidServerMessage, .invalidFramebufferGeometry:
            return .protocolViolation
        }
    }

    static func shouldRetry(_ error: Error) -> Bool {
        classify(error) == .network
    }

    static func delaySeconds(forAttempt attempt: Int) -> Int {
        let normalizedAttempt = max(1, attempt)
        return min(30, 1 << min(normalizedAttempt - 1, 5))
    }

    static func userFacingStatus(for error: Error) -> String {
        let category = classify(error)
        return "\(category.title) issue: \(error.localizedDescription)"
    }
}
