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

public struct TerminalCursorState: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var isVisible: Bool

    public init(row: Int = 0, column: Int = 0, isVisible: Bool = true) {
        self.row = row
        self.column = column
        self.isVisible = isVisible
    }
}

public struct TerminalBufferSnapshot: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var viewportLines: [String]
    public var cursor: TerminalCursorState
    public var scrollbackLineCount: Int

    public init(
        columns: Int,
        rows: Int,
        viewportLines: [String],
        cursor: TerminalCursorState = TerminalCursorState(),
        scrollbackLineCount: Int = 0
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        let normalizedRows = max(1, rows)
        let normalizedLines = Array(viewportLines.prefix(normalizedRows))
        self.viewportLines = normalizedLines + Array(repeating: "", count: max(0, normalizedRows - normalizedLines.count))
        self.cursor = cursor
        self.scrollbackLineCount = max(0, scrollbackLineCount)
    }

    public static func placeholder(
        columns: Int,
        rows: Int,
        message: [String] = []
    ) -> TerminalBufferSnapshot {
        TerminalBufferSnapshot(
            columns: columns,
            rows: rows,
            viewportLines: Array(message.prefix(max(1, rows))),
            cursor: TerminalCursorState(row: max(0, min(rows - 1, message.count)), column: 0, isVisible: false)
        )
    }

    public func renderedViewportLines(insertingCursor: Bool = false) -> [String] {
        guard insertingCursor, cursor.isVisible else {
            return viewportLines
        }

        var lines = viewportLines
        guard cursor.row >= 0, cursor.row < lines.count else {
            return lines
        }

        var characters = Array(lines[cursor.row])
        if cursor.column >= characters.count {
            characters += Array(repeating: " ", count: cursor.column - characters.count)
            characters.append("█")
        } else {
            characters[cursor.column] = "█"
        }
        lines[cursor.row] = String(characters)
        return lines
    }

    public func viewportText(insertingCursor: Bool = false) -> String {
        renderedViewportLines(insertingCursor: insertingCursor).joined(separator: "\n")
    }
}

public struct TerminalSurfaceState: Codable, Equatable, Sendable {
    public static let maximumTranscriptLength = 12_000

    public var connectionTitle: String
    public var sessionState: TerminalConnectionState
    public var statusMessage: String
    public var transcript: String
    public var columns: Int
    public var rows: Int
    public var buffer: TerminalBufferSnapshot

    public init(
        connectionTitle: String = "Terminal",
        sessionState: TerminalConnectionState = .idle,
        statusMessage: String = "Ready for SSH session",
        transcript: String = "No SSH session yet.\nUse the iPhone control scene to connect.\n",
        columns: Int = 120,
        rows: Int = 32,
        buffer: TerminalBufferSnapshot? = nil
    ) {
        self.connectionTitle = connectionTitle
        self.sessionState = sessionState
        self.statusMessage = statusMessage
        self.transcript = Self.trimmedTranscript(transcript)
        self.columns = columns
        self.rows = rows
        self.buffer = buffer ?? Self.defaultBuffer(columns: columns, rows: rows, transcript: transcript)
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
            rows: rows,
            buffer: defaultBuffer(
                columns: columns,
                rows: rows,
                transcript: "No SSH session yet.\nUse the iPhone control scene to connect.\n"
            )
        )
    }

    public mutating func appendOutput(_ text: String) {
        transcript = Self.trimmedTranscript(transcript + text)
    }

    public mutating func replaceBuffer(_ snapshot: TerminalBufferSnapshot) {
        buffer = snapshot
        columns = snapshot.columns
        rows = snapshot.rows
    }

    public static func trimmedTranscript(_ text: String) -> String {
        guard text.count > maximumTranscriptLength else {
            return text
        }

        return String(text.suffix(maximumTranscriptLength))
    }

    private static func defaultBuffer(columns: Int, rows: Int, transcript: String) -> TerminalBufferSnapshot {
        let message = transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return TerminalBufferSnapshot.placeholder(columns: columns, rows: rows, message: message)
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
