import DesktopDomain
import Foundation

struct TerminalEmulator {
    private var parser = VT100Parser()
    private var screen: TerminalScreenBuffer
    private var transcript: String

    init(columns: Int, rows: Int, initialTranscript: String? = nil) {
        self.screen = TerminalScreenBuffer(columns: columns, rows: rows)
        self.transcript = ""

        if let initialTranscript, !initialTranscript.isEmpty {
            consume(initialTranscript)
        }
    }

    mutating func reset(columns: Int, rows: Int, initialTranscript: String? = nil) {
        parser = VT100Parser()
        screen = TerminalScreenBuffer(columns: columns, rows: rows)
        transcript = ""

        if let initialTranscript, !initialTranscript.isEmpty {
            consume(initialTranscript)
        }
    }

    mutating func resize(columns: Int, rows: Int) {
        screen.resize(columns: columns, rows: rows)
    }

    mutating func consume(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        let plainText = parser.consume(text, into: &screen)
        if !plainText.isEmpty {
            transcript = TerminalSurfaceState.trimmedTranscript(transcript + plainText)
        }
    }

    func makeBufferSnapshot() -> TerminalBufferSnapshot {
        screen.snapshot()
    }

    func makeTranscript() -> String {
        transcript
    }
}

struct TerminalScreenBuffer {
    private(set) var columns: Int
    private(set) var rows: Int
    private var lines: [[Character]]
    private(set) var cursorRow: Int
    private(set) var cursorColumn: Int
    private(set) var isCursorVisible = true
    private var savedCursor = TerminalCursorState()
    private(set) var scrollbackLineCount = 0

    init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.lines = Array(
            repeating: Array(repeating: " ", count: max(1, columns)),
            count: max(1, rows)
        )
        self.cursorRow = 0
        self.cursorColumn = 0
    }

    mutating func resize(columns: Int, rows: Int) {
        let nextColumns = max(1, columns)
        let nextRows = max(1, rows)
        guard nextColumns != self.columns || nextRows != self.rows else {
            return
        }

        var resized: [[Character]] = Array(
            repeating: Array(repeating: Character(" "), count: nextColumns),
            count: nextRows
        )
        let rowsToCopy = min(nextRows, lines.count)
        let columnsToCopy = min(nextColumns, self.columns)

        for rowIndex in 0..<rowsToCopy {
            for columnIndex in 0..<columnsToCopy {
                resized[rowIndex][columnIndex] = lines[rowIndex][columnIndex]
            }
        }

        self.columns = nextColumns
        self.rows = nextRows
        self.lines = resized
        self.cursorRow = min(cursorRow, nextRows - 1)
        self.cursorColumn = min(cursorColumn, nextColumns - 1)
        self.savedCursor = TerminalCursorState(
            row: min(savedCursor.row, nextRows - 1),
            column: min(savedCursor.column, nextColumns - 1),
            isVisible: savedCursor.isVisible
        )
    }

    mutating func put(_ character: Character) {
        if cursorColumn >= columns {
            lineFeed()
            carriageReturn()
        }

        guard cursorRow >= 0, cursorRow < rows, cursorColumn >= 0, cursorColumn < columns else {
            return
        }

        lines[cursorRow][cursorColumn] = character
        cursorColumn += 1
        if cursorColumn > columns {
            cursorColumn = columns
        }
    }

    mutating func lineFeed() {
        if cursorRow == rows - 1 {
            scrollUp(by: 1)
        } else {
            cursorRow += 1
        }
    }

    mutating func carriageReturn() {
        cursorColumn = 0
    }

    mutating func backspace() {
        cursorColumn = max(0, cursorColumn - 1)
    }

    mutating func tab() {
        let nextStop = min(columns - 1, ((cursorColumn / 8) + 1) * 8)
        while cursorColumn < nextStop {
            put(" ")
        }
    }

    mutating func moveCursor(rowDelta: Int = 0, columnDelta: Int = 0) {
        cursorRow = min(max(cursorRow + rowDelta, 0), rows - 1)
        cursorColumn = min(max(cursorColumn + columnDelta, 0), columns - 1)
    }

    mutating func moveCursorTo(row: Int, column: Int) {
        cursorRow = min(max(row, 0), rows - 1)
        cursorColumn = min(max(column, 0), columns - 1)
    }

    mutating func saveCursor() {
        savedCursor = TerminalCursorState(row: cursorRow, column: cursorColumn, isVisible: isCursorVisible)
    }

    mutating func restoreCursor() {
        cursorRow = min(max(savedCursor.row, 0), rows - 1)
        cursorColumn = min(max(savedCursor.column, 0), columns - 1)
        isCursorVisible = savedCursor.isVisible
    }

    mutating func setCursorVisibility(_ isVisible: Bool) {
        isCursorVisible = isVisible
    }

    mutating func eraseInDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in 0...cursorRow {
                if row == cursorRow {
                    fill(row: row, from: 0, to: cursorColumn)
                } else {
                    clearRow(row)
                }
            }
        case 2:
            for row in 0..<rows {
                clearRow(row)
            }
            moveCursorTo(row: 0, column: 0)
        default:
            for row in cursorRow..<rows {
                if row == cursorRow {
                    fill(row: row, from: cursorColumn, to: columns - 1)
                } else {
                    clearRow(row)
                }
            }
        }
    }

    mutating func eraseInLine(mode: Int) {
        switch mode {
        case 1:
            fill(row: cursorRow, from: 0, to: cursorColumn)
        case 2:
            clearRow(cursorRow)
        default:
            fill(row: cursorRow, from: cursorColumn, to: columns - 1)
        }
    }

    mutating func eraseCharacters(_ count: Int) {
        guard count > 0 else {
            return
        }

        let upperBound = min(columns - 1, cursorColumn + count - 1)
        fill(row: cursorRow, from: cursorColumn, to: upperBound)
    }

    mutating func deleteCharacters(_ count: Int) {
        guard count > 0, cursorColumn < columns else {
            return
        }

        let clampedCount = min(count, columns - cursorColumn)
        let tailStart = cursorColumn + clampedCount
        if tailStart < columns {
            for index in cursorColumn..<(columns - clampedCount) {
                lines[cursorRow][index] = lines[cursorRow][index + clampedCount]
            }
        }
        fill(row: cursorRow, from: columns - clampedCount, to: columns - 1)
    }

    mutating func insertBlankCharacters(_ count: Int) {
        guard count > 0, cursorColumn < columns else {
            return
        }

        let clampedCount = min(count, columns - cursorColumn)
        for index in stride(from: columns - 1, through: cursorColumn + clampedCount, by: -1) {
            lines[cursorRow][index] = lines[cursorRow][index - clampedCount]
        }
        fill(row: cursorRow, from: cursorColumn, to: min(columns - 1, cursorColumn + clampedCount - 1))
    }

    mutating func insertLines(_ count: Int) {
        guard count > 0 else {
            return
        }

        let clampedCount = min(count, rows - cursorRow)
        for _ in 0..<clampedCount {
            lines.insert(Array(repeating: " ", count: columns), at: cursorRow)
            lines.removeLast()
        }
    }

    mutating func deleteLines(_ count: Int) {
        guard count > 0 else {
            return
        }

        let clampedCount = min(count, rows - cursorRow)
        for _ in 0..<clampedCount {
            lines.remove(at: cursorRow)
            lines.append(Array(repeating: " ", count: columns))
        }
    }

    func snapshot() -> TerminalBufferSnapshot {
        TerminalBufferSnapshot(
            columns: columns,
            rows: rows,
            viewportLines: lines.map(Self.trimmedLine),
            cursor: TerminalCursorState(row: cursorRow, column: cursorColumn, isVisible: isCursorVisible),
            scrollbackLineCount: scrollbackLineCount
        )
    }

    private mutating func clearRow(_ row: Int) {
        fill(row: row, from: 0, to: columns - 1)
    }

    private mutating func fill(row: Int, from lower: Int, to upper: Int) {
        guard row >= 0, row < rows, lower <= upper else {
            return
        }

        let start = max(0, lower)
        let end = min(columns - 1, upper)
        guard start <= end else {
            return
        }

        for index in start...end {
            lines[row][index] = " "
        }
    }

    private mutating func scrollUp(by count: Int) {
        for _ in 0..<count {
            lines.removeFirst()
            lines.append(Array(repeating: " ", count: columns))
            scrollbackLineCount += 1
        }
    }

    private static func trimmedLine(_ characters: [Character]) -> String {
        var buffer = characters
        while let last = buffer.last, last == " " {
            buffer.removeLast()
        }
        return String(buffer)
    }
}
