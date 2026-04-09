import Foundation

public struct WorkspaceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }
}

public struct WindowID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }
}

public enum DesktopWindowKind: String, Codable, CaseIterable, Sendable {
    case terminal
    case files
    case browser
    case vnc
}

public enum TerminalConnectionState: String, Codable, CaseIterable, Sendable {
    case idle
    case connecting
    case connected
    case failed
}

public struct TerminalSurfaceState: Codable, Equatable, Sendable {
    public static let maximumTranscriptLength = 12_000

    public var connectionTitle: String
    public var sessionState: TerminalConnectionState
    public var statusMessage: String
    public var transcript: String
    public var columns: Int
    public var rows: Int

    public init(
        connectionTitle: String = "Terminal",
        sessionState: TerminalConnectionState = .idle,
        statusMessage: String = "Ready for SSH session",
        transcript: String = "No SSH session yet.\nUse the iPhone control scene to connect.\n",
        columns: Int = 120,
        rows: Int = 32
    ) {
        self.connectionTitle = connectionTitle
        self.sessionState = sessionState
        self.statusMessage = statusMessage
        self.transcript = Self.trimmedTranscript(transcript)
        self.columns = columns
        self.rows = rows
    }

    public static func idle(
        title: String = "Terminal",
        columns: Int = 120,
        rows: Int = 32
    ) -> TerminalSurfaceState {
        TerminalSurfaceState(
            connectionTitle: title,
            sessionState: .idle,
            statusMessage: "Ready for SSH session",
            transcript: "No SSH session yet.\nUse the iPhone control scene to connect.\n",
            columns: columns,
            rows: rows
        )
    }

    public mutating func appendOutput(_ text: String) {
        transcript = Self.trimmedTranscript(transcript + text)
    }

    public static func trimmedTranscript(_ text: String) -> String {
        guard text.count > maximumTranscriptLength else {
            return text
        }

        return String(text.suffix(maximumTranscriptLength))
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let defaultWindow = NormalizedRect(x: 0.08, y: 0.10, width: 0.42, height: 0.34)
}

public struct DesktopWindow: Identifiable, Codable, Equatable, Sendable {
    public let id: WindowID
    public var kind: DesktopWindowKind
    public var title: String
    public var frame: NormalizedRect
    public var isFocused: Bool
    public var terminalState: TerminalSurfaceState?

    public init(
        id: WindowID = WindowID(),
        kind: DesktopWindowKind,
        title: String,
        frame: NormalizedRect = .defaultWindow,
        isFocused: Bool = false,
        terminalState: TerminalSurfaceState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.frame = frame
        self.isFocused = isFocused
        self.terminalState = terminalState
    }
}

public struct DisplayProfile: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var scale: Double

    public init(width: Double = 1440, height: Double = 900, scale: Double = 1.0) {
        self.width = width
        self.height = height
        self.scale = scale
    }
}

public struct CursorState: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0.5, y: Double = 0.5) {
        self.x = x
        self.y = y
    }
}

public struct DesktopSnapshot: Codable, Equatable, Sendable {
    public var workspaceID: WorkspaceID
    public var windows: [DesktopWindow]
    public var focusedWindowID: WindowID?
    public var displayProfile: DisplayProfile
    public var cursor: CursorState
    public var isExternalDisplayConnected: Bool
    public var lastInputDescription: String
    public var revision: Int

    public init(
        workspaceID: WorkspaceID = WorkspaceID(),
        windows: [DesktopWindow] = [],
        focusedWindowID: WindowID? = nil,
        displayProfile: DisplayProfile = DisplayProfile(),
        cursor: CursorState = CursorState(),
        isExternalDisplayConnected: Bool = false,
        lastInputDescription: String = "No input yet",
        revision: Int = 0
    ) {
        self.workspaceID = workspaceID
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.displayProfile = displayProfile
        self.cursor = cursor
        self.isExternalDisplayConnected = isExternalDisplayConnected
        self.lastInputDescription = lastInputDescription
        self.revision = revision
    }

    public static let empty = DesktopSnapshot()
}
