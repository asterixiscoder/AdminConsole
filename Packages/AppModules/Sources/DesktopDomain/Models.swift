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

public enum VNCConnectionState: String, Codable, CaseIterable, Sendable {
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

public struct TerminalGridPoint: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public struct TerminalSelection: Codable, Equatable, Sendable {
    public var anchor: TerminalGridPoint
    public var focus: TerminalGridPoint

    public init(anchor: TerminalGridPoint, focus: TerminalGridPoint) {
        self.anchor = anchor
        self.focus = focus
    }

    public var normalized: (start: TerminalGridPoint, end: TerminalGridPoint) {
        if anchor.row < focus.row {
            return (anchor, focus)
        }

        if anchor.row > focus.row {
            return (focus, anchor)
        }

        if anchor.column <= focus.column {
            return (anchor, focus)
        }

        return (focus, anchor)
    }
}

public enum TerminalColor: Codable, Equatable, Sendable {
    case `default`
    case ansi256(Int)
    case rgb(red: Int, green: Int, blue: Int)
}

public struct TerminalTextStyle: Codable, Equatable, Sendable {
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var isInverse: Bool

    public init(
        foreground: TerminalColor = .default,
        background: TerminalColor = .default,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isInverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isInverse = isInverse
    }

    public static let `default` = TerminalTextStyle()
}

public struct TerminalCell: Codable, Equatable, Sendable {
    public var character: String
    public var style: TerminalTextStyle

    public init(character: String = " ", style: TerminalTextStyle = .default) {
        let normalizedCharacter = character.isEmpty ? " " : String(character.prefix(1))
        self.character = normalizedCharacter
        self.style = style
    }
}

public struct TerminalStyledLine: Codable, Equatable, Sendable {
    public var cells: [TerminalCell]

    public init(cells: [TerminalCell] = []) {
        self.cells = cells
    }

    public var plainText: String {
        cells.map(\.character).joined()
    }

    public var plainTextTrimmed: String {
        var output = plainText
        while output.last == " " {
            output.removeLast()
        }
        return output
    }
}

public struct TerminalBufferSnapshot: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var styledLines: [TerminalStyledLine]
    public var cursor: TerminalCursorState
    public var scrollbackLineCount: Int

    public init(
        columns: Int,
        rows: Int,
        styledLines: [TerminalStyledLine],
        cursor: TerminalCursorState = TerminalCursorState(),
        scrollbackLineCount: Int = 0
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        let normalizedRows = max(1, rows)
        let normalizedLines = Array(styledLines.prefix(normalizedRows))
        self.styledLines = normalizedLines + Array(
            repeating: TerminalStyledLine(
                cells: Array(repeating: TerminalCell(), count: max(1, columns))
            ),
            count: max(0, normalizedRows - normalizedLines.count)
        )
        self.cursor = cursor
        self.scrollbackLineCount = max(0, scrollbackLineCount)
    }

    public init(
        columns: Int,
        rows: Int,
        viewportLines: [String],
        cursor: TerminalCursorState = TerminalCursorState(),
        scrollbackLineCount: Int = 0,
        style: TerminalTextStyle = .default
    ) {
        self.init(
            columns: columns,
            rows: rows,
            styledLines: viewportLines.map { line in
                TerminalStyledLine(
                    cells: Array(line.prefix(max(1, columns))).map { TerminalCell(character: String($0), style: style) }
                )
            },
            cursor: cursor,
            scrollbackLineCount: scrollbackLineCount
        )
    }

    public var viewportLines: [String] {
        styledLines.map(\.plainTextTrimmed)
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

    public func renderedStyledLines(insertingCursor: Bool = false) -> [TerminalStyledLine] {
        guard insertingCursor, cursor.isVisible else {
            return styledLines
        }

        var lines = styledLines
        guard cursor.row >= 0, cursor.row < lines.count else {
            return lines
        }

        var cells = lines[cursor.row].cells
        while cells.count <= cursor.column {
            cells.append(TerminalCell())
        }

        var cursorCell = cells[cursor.column]
        cursorCell.style.isInverse.toggle()
        if cursorCell.character == " " {
            cursorCell.character = " "
        }
        cells[cursor.column] = cursorCell
        lines[cursor.row] = TerminalStyledLine(cells: cells)
        return lines
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

    public func clamped(_ point: TerminalGridPoint) -> TerminalGridPoint {
        TerminalGridPoint(
            row: max(0, min(rows - 1, point.row)),
            column: max(0, min(columns - 1, point.column))
        )
    }

    public func clamped(_ selection: TerminalSelection) -> TerminalSelection {
        TerminalSelection(
            anchor: clamped(selection.anchor),
            focus: clamped(selection.focus)
        )
    }

    public func contains(_ point: TerminalGridPoint, in selection: TerminalSelection) -> Bool {
        let normalized = clamped(selection).normalized
        let start = normalized.start
        let end = normalized.end

        guard point.row >= start.row, point.row <= end.row else {
            return false
        }

        if start.row == end.row {
            return point.column >= start.column && point.column <= end.column
        }

        if point.row == start.row {
            return point.column >= start.column
        }

        if point.row == end.row {
            return point.column <= end.column
        }

        return true
    }

    public func selectedText(for selection: TerminalSelection) -> String {
        let normalized = clamped(selection).normalized
        let start = normalized.start
        let end = normalized.end

        guard start.row < styledLines.count, end.row < styledLines.count else {
            return ""
        }

        var lines: [String] = []

        for row in start.row...end.row {
            let cells = styledLines[row].cells
            guard !cells.isEmpty else {
                lines.append("")
                continue
            }

            let lower: Int
            let upper: Int

            if start.row == end.row {
                lower = start.column
                upper = end.column
            } else if row == start.row {
                lower = start.column
                upper = cells.count - 1
            } else if row == end.row {
                lower = 0
                upper = end.column
            } else {
                lower = 0
                upper = cells.count - 1
            }

            let clampedLower = max(0, min(cells.count - 1, lower))
            let clampedUpper = max(0, min(cells.count - 1, upper))
            if clampedLower > clampedUpper {
                lines.append("")
                continue
            }

            lines.append(cells[clampedLower...clampedUpper].map(\.character).joined())
        }

        return lines.joined(separator: "\n")
    }
}

public struct TerminalSurfaceState: Codable, Equatable, Sendable {
    public static let maximumTranscriptLength = 12_000

    public var connectionTitle: String
    public var screenTitle: String?
    public var sessionState: TerminalConnectionState
    public var statusMessage: String
    public var transcript: String
    public var columns: Int
    public var rows: Int
    public var buffer: TerminalBufferSnapshot
    public var selection: TerminalSelection?

    public init(
        connectionTitle: String = "Terminal",
        screenTitle: String? = nil,
        sessionState: TerminalConnectionState = .idle,
        statusMessage: String = "Ready for SSH session",
        transcript: String = "No SSH session yet.\nUse the iPhone control scene to connect.\n",
        columns: Int = 120,
        rows: Int = 32,
        buffer: TerminalBufferSnapshot? = nil,
        selection: TerminalSelection? = nil
    ) {
        self.connectionTitle = connectionTitle
        self.screenTitle = screenTitle
        self.sessionState = sessionState
        self.statusMessage = statusMessage
        self.transcript = Self.trimmedTranscript(transcript)
        self.columns = columns
        self.rows = rows
        self.buffer = buffer ?? Self.defaultBuffer(columns: columns, rows: rows, transcript: transcript)
        self.selection = selection.map { self.buffer.clamped($0) }
    }

    public var displayTitle: String {
        if let screenTitle, !screenTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return screenTitle
        }

        return connectionTitle
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
        selection = selection.map { snapshot.clamped($0) }
    }

    public mutating func setSelection(_ selection: TerminalSelection?) {
        self.selection = selection.map { buffer.clamped($0) }
    }

    public func selectedText() -> String? {
        guard let selection else {
            return nil
        }

        let text = buffer.selectedText(for: selection)
        return text.isEmpty ? nil : text
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

public enum FilesEntryKind: String, Codable, CaseIterable, Sendable {
    case directory
    case file
}

public struct FilesEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var relativePath: String
    public var kind: FilesEntryKind
    public var byteSize: Int64?

    public init(
        id: String,
        name: String,
        relativePath: String,
        kind: FilesEntryKind,
        byteSize: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.byteSize = byteSize
    }
}

public struct FilesSurfaceState: Codable, Equatable, Sendable {
    public var workspaceName: String
    public var currentPath: String
    public var entries: [FilesEntry]
    public var selectedEntryID: String?
    public var statusMessage: String
    public var previewText: String
    public var canNavigateUp: Bool

    public init(
        workspaceName: String = "Workspace",
        currentPath: String = "/",
        entries: [FilesEntry] = [],
        selectedEntryID: String? = nil,
        statusMessage: String = "Preparing workspace",
        previewText: String = "Open the Files window on iPhone to browse the in-app workspace.",
        canNavigateUp: Bool = false
    ) {
        self.workspaceName = workspaceName
        self.currentPath = currentPath
        self.entries = entries
        self.selectedEntryID = selectedEntryID
        self.statusMessage = statusMessage
        self.previewText = previewText
        self.canNavigateUp = canNavigateUp
    }

    public static func idle(workspaceName: String = "Workspace") -> FilesSurfaceState {
        FilesSurfaceState(
            workspaceName: workspaceName,
            currentPath: "/",
            entries: [],
            selectedEntryID: nil,
            statusMessage: "Preparing workspace",
            previewText: "Open the Files window on iPhone to browse the in-app workspace.",
            canNavigateUp: false
        )
    }

    public var selectedEntry: FilesEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    public var displayTitle: String {
        let trimmedPath = currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else {
            return "Files"
        }

        let component = trimmedPath.split(separator: "/").last.map(String.init) ?? workspaceName
        return "Files - \(component)"
    }
}

public struct VNCFrameSnapshot: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var lines: [String]

    public init(columns: Int = 72, rows: Int = 20, lines: [String] = []) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        let normalizedLines = Array(lines.prefix(self.rows))
        self.lines = normalizedLines + Array(repeating: "", count: max(0, self.rows - normalizedLines.count))
    }

    public static func placeholder(
        columns: Int = 72,
        rows: Int = 20,
        title: String = "VNC spike",
        detail: String = "Connect from the iPhone control scene to start a remote desktop session."
    ) -> VNCFrameSnapshot {
        VNCFrameSnapshot(
            columns: columns,
            rows: rows,
            lines: [
                "+" + String(repeating: "-", count: max(1, columns - 2)) + "+",
                "| " + title.padding(toLength: max(1, columns - 4), withPad: " ", startingAt: 0) + " |",
                "| " + detail.padding(toLength: max(1, columns - 4), withPad: " ", startingAt: 0) + " |",
                "+" + String(repeating: "-", count: max(1, columns - 2)) + "+"
            ]
        )
    }

    public var renderedText: String {
        lines.joined(separator: "\n")
    }
}

public struct VNCSurfaceState: Codable, Equatable, Sendable {
    public static let maximumEventLogCount = 10

    public var connectionTitle: String
    public var sessionState: VNCConnectionState
    public var statusMessage: String
    public var frame: VNCFrameSnapshot
    public var remoteDesktopName: String
    public var qualityPreset: String
    public var isTrackpadModeEnabled: Bool
    public var remotePointer: CursorState
    public var recentEvents: [String]

    public init(
        connectionTitle: String = "VNC",
        sessionState: VNCConnectionState = .idle,
        statusMessage: String = "Ready for VNC session",
        frame: VNCFrameSnapshot = .placeholder(),
        remoteDesktopName: String = "Remote Desktop",
        qualityPreset: String = "balanced",
        isTrackpadModeEnabled: Bool = true,
        remotePointer: CursorState = CursorState(x: 0.32, y: 0.40),
        recentEvents: [String] = []
    ) {
        self.connectionTitle = connectionTitle
        self.sessionState = sessionState
        self.statusMessage = statusMessage
        self.frame = frame
        self.remoteDesktopName = remoteDesktopName
        self.qualityPreset = qualityPreset
        self.isTrackpadModeEnabled = isTrackpadModeEnabled
        self.remotePointer = remotePointer
        self.recentEvents = Array(recentEvents.suffix(Self.maximumEventLogCount))
    }

    public static func idle(title: String = "VNC") -> VNCSurfaceState {
        VNCSurfaceState(
            connectionTitle: title,
            sessionState: .idle,
            statusMessage: "Ready for VNC session",
            frame: .placeholder(title: "VNC spike", detail: "Use the iPhone control scene to connect and drive the remote desktop.")
        )
    }

    public var displayTitle: String {
        if remoteDesktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return connectionTitle
        }

        return remoteDesktopName
    }

    public mutating func appendEvent(_ event: String) {
        recentEvents.append(event)
        recentEvents = Array(recentEvents.suffix(Self.maximumEventLogCount))
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
    public var filesState: FilesSurfaceState?
    public var vncState: VNCSurfaceState?

    public init(
        id: WindowID = WindowID(),
        kind: DesktopWindowKind,
        title: String,
        frame: NormalizedRect = .defaultWindow,
        isFocused: Bool = false,
        terminalState: TerminalSurfaceState? = nil,
        filesState: FilesSurfaceState? = nil,
        vncState: VNCSurfaceState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.frame = frame
        self.isFocused = isFocused
        self.terminalState = terminalState
        self.filesState = filesState
        self.vncState = vncState
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
