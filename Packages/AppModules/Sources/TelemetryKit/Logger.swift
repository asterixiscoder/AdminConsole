import Foundation

public struct Logger: Sendable {
    public let subsystem: String

    public init(subsystem: String) {
        self.subsystem = subsystem
    }

    public func log(_ message: String) {
        print("[\(subsystem)] \(message)")
    }
}
