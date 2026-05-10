import DesktopDomain
import Foundation

struct TerminalEmulator {
    private var parser = VT100Parser()
    private var screen: TerminalScreenBuffer
    private var transcript: String
    private var screenTitle: String?

    init(columns: Int, rows: Int, initialTranscript: String? = nil) {
        self.screen = TerminalScreenBuffer(columns: columns, rows: rows)
        self.transcript = ""
        self.screenTitle = nil

        if let initialTranscript, !initialTranscript.isEmpty {
            consume(initialTranscript)
        }
    }

    mutating func reset(columns: Int, rows: Int, initialTranscript: String? = nil) {
        parser = VT100Parser()
        screen = TerminalScreenBuffer(columns: columns, rows: rows)
        transcript = ""
        screenTitle = nil

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

        screen.repairInvariants()
        let result = parser.consume(text, into: &screen)
        screen.repairInvariants()
        transcript = TerminalSurfaceState.trimmedTranscript(screen.fullText())
        if let screenTitle = result.screenTitle {
            self.screenTitle = screenTitle
        }
    }

    func makeBufferSnapshot() -> TerminalBufferSnapshot {
        screen.snapshot()
    }

    func makeTranscript() -> String {
        transcript
    }

    func currentScreenTitle() -> String? {
        screenTitle
    }
}

struct TerminalScreenBuffer {
    private static let maxScrollbackLines = 2_000
    private enum Charset {
        case ascii
        case lineDrawing
    }
    private struct ScreenStateSnapshot {
        var lines: [[TerminalCell]]
        var scrollback: [[TerminalCell]]
        var cursorRow: Int
        var cursorColumn: Int
        var isCursorVisible: Bool
        var savedCursor: TerminalCursorState
        var scrollbackLineCount: Int
        var scrollRegionTop: Int
        var scrollRegionBottom: Int
        var g0Charset: Charset
        var isShiftOut: Bool
        var isAutowrapEnabled: Bool
        var isBracketedPasteEnabled: Bool
        var isApplicationCursorKeysEnabled: Bool
        var mouseTrackingMode: TerminalMouseTrackingMode
        var isSgrMouseModeEnabled: Bool
    }

    private(set) var columns: Int
    private(set) var rows: Int
    private var lines: [[TerminalCell]]
    private var scrollback: [[TerminalCell]]
    private(set) var cursorRow: Int
    private(set) var cursorColumn: Int
    private(set) var isCursorVisible = true
    private var savedCursor = TerminalCursorState()
    private(set) var scrollbackLineCount = 0
    private var activeStyle = TerminalTextStyle.default
    private var isAlternateScreenActive = false
    private var mainScreenSnapshot: ScreenStateSnapshot?
    private var scrollRegionTop = 0
    private var scrollRegionBottom = 0
    private var g0Charset: Charset = .ascii
    private var isShiftOut = false
    private var isAutowrapEnabled = true
    private var isBracketedPasteEnabled = false
    private var isApplicationCursorKeysEnabled = false
    private var mouseTrackingMode: TerminalMouseTrackingMode = .none
    private var isSgrMouseModeEnabled = false

    init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.lines = Array(
            repeating: Array(repeating: TerminalCell(), count: max(1, columns)),
            count: max(1, rows)
        )
        self.scrollback = []
        self.cursorRow = 0
        self.cursorColumn = 0
        self.scrollRegionBottom = self.rows - 1
    }

    mutating func resize(columns: Int, rows: Int) {
        let nextColumns = max(1, columns)
        let nextRows = max(1, rows)
        guard nextColumns != self.columns || nextRows != self.rows else {
            return
        }

        var resized: [[TerminalCell]] = Array(
            repeating: Array(repeating: TerminalCell(), count: nextColumns),
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
        self.scrollRegionTop = 0
        self.scrollRegionBottom = nextRows - 1
        self.savedCursor = TerminalCursorState(
            row: min(savedCursor.row, nextRows - 1),
            column: min(savedCursor.column, nextColumns - 1),
            isVisible: savedCursor.isVisible
        )
        repairInvariants()
    }

    mutating func put(_ character: Character) {
        // Keep buffer shape and cursor always consistent before write.
        repairInvariants()

        if cursorColumn >= columns {
            if isAutowrapEnabled {
                lineFeed()
                carriageReturn()
            } else {
                cursorColumn = columns - 1
            }
        }

        guard cursorRow >= 0, cursorRow < rows, cursorColumn >= 0, cursorColumn < columns else {
            return
        }
        if cursorRow >= lines.count || cursorColumn >= lines[cursorRow].count {
            repairInvariants()
            guard cursorRow >= 0,
                  cursorRow < rows,
                  cursorColumn >= 0,
                  cursorColumn < columns,
                  cursorRow < lines.count,
                  cursorColumn < lines[cursorRow].count else {
                return
            }
        }

        let mappedCharacter = mapCharacterForActiveCharset(character)
        if cursorRow < 0 ||
            cursorRow >= lines.count ||
            cursorColumn < 0 ||
            cursorColumn >= lines[cursorRow].count {
            repairInvariants()
            guard cursorRow >= 0,
                  cursorRow < lines.count,
                  cursorColumn >= 0,
                  cursorColumn < lines[cursorRow].count else {
                return
            }
        }
        lines[cursorRow][cursorColumn] = TerminalCell(character: String(mappedCharacter), style: activeStyle)
        if cursorColumn < columns - 1 {
            cursorColumn += 1
        } else if isAutowrapEnabled {
            cursorColumn += 1
        } else {
            cursorColumn = columns - 1
        }
    }

    mutating func lineFeed() {
        if cursorRow == scrollRegionBottom {
            let tracksScrollback = scrollRegionTop == 0 && scrollRegionBottom == rows - 1
            scrollUp(
                from: scrollRegionTop,
                to: scrollRegionBottom,
                by: 1,
                appendToScrollback: tracksScrollback
            )
        } else {
            cursorRow = min(cursorRow + 1, rows - 1)
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

    mutating func resetStyle() {
        activeStyle = .default
    }

    mutating func setScrollRegion(top: Int?, bottom: Int?) {
        let defaultBottom = rows
        let rawTop = max(1, top ?? 1)
        let rawBottom = max(1, bottom ?? defaultBottom)
        guard rawTop < rawBottom, rawBottom <= rows else {
            scrollRegionTop = 0
            scrollRegionBottom = rows - 1
            moveCursorTo(row: 0, column: 0)
            return
        }

        scrollRegionTop = rawTop - 1
        scrollRegionBottom = rawBottom - 1
        moveCursorTo(row: 0, column: 0)
    }

    mutating func setPrivateModes(_ params: [Int], enabled: Bool) {
        guard !params.isEmpty else {
            return
        }

        for mode in params {
            switch mode {
            case 25:
                setCursorVisibility(enabled)
            case 7:
                isAutowrapEnabled = enabled
            case 1:
                isApplicationCursorKeysEnabled = enabled
            case 2004:
                isBracketedPasteEnabled = enabled
            case 1000:
                if enabled {
                    mouseTrackingMode = .x10
                } else if mouseTrackingMode == .x10 {
                    mouseTrackingMode = .none
                }
            case 1002:
                if enabled {
                    mouseTrackingMode = .buttonEvent
                } else if mouseTrackingMode == .buttonEvent {
                    mouseTrackingMode = .none
                }
            case 1003:
                if enabled {
                    mouseTrackingMode = .anyEvent
                } else if mouseTrackingMode == .anyEvent {
                    mouseTrackingMode = .none
                }
            case 1006:
                isSgrMouseModeEnabled = enabled
            case 47, 1047:
                setAlternateScreen(enabled: enabled, saveAndRestoreCursor: false)
            case 1048:
                if enabled {
                    saveCursor()
                } else {
                    restoreCursor()
                }
            case 1049:
                setAlternateScreen(enabled: enabled, saveAndRestoreCursor: true)
            default:
                break
            }
        }
    }

    mutating func setG0CharacterSet(_ designator: UnicodeScalar) {
        switch designator {
        case "0":
            g0Charset = .lineDrawing
        default:
            g0Charset = .ascii
        }
    }

    mutating func setShiftOut(_ enabled: Bool) {
        isShiftOut = enabled
    }

    mutating func applySGR(_ params: [Int]) {
        let effectiveParams = params.isEmpty ? [0] : params
        var index = 0

        while index < effectiveParams.count {
            let code = effectiveParams[index]
            switch code {
            case 0:
                activeStyle = .default
            case 1:
                activeStyle.isBold = true
            case 3:
                activeStyle.isItalic = true
            case 4:
                activeStyle.isUnderlined = true
            case 7:
                activeStyle.isInverse = true
            case 22:
                activeStyle.isBold = false
            case 23:
                activeStyle.isItalic = false
            case 24:
                activeStyle.isUnderlined = false
            case 27:
                activeStyle.isInverse = false
            case 30...37:
                activeStyle.foreground = .ansi256(code - 30)
            case 39:
                activeStyle.foreground = .default
            case 40...47:
                activeStyle.background = .ansi256(code - 40)
            case 49:
                activeStyle.background = .default
            case 90...97:
                activeStyle.foreground = .ansi256(code - 90 + 8)
            case 100...107:
                activeStyle.background = .ansi256(code - 100 + 8)
            case 38, 48:
                let isForeground = code == 38
                let remaining = Array(effectiveParams.suffix(from: index + 1))
                if let (color, consumedCount) = parseExtendedColor(from: remaining) {
                    if isForeground {
                        activeStyle.foreground = color
                    } else {
                        activeStyle.background = color
                    }
                    index += consumedCount
                }
            default:
                break
            }

            index += 1
        }
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

        guard cursorRow >= scrollRegionTop, cursorRow <= scrollRegionBottom else {
            return
        }

        let clampedCount = min(count, scrollRegionBottom - cursorRow + 1)
        for _ in 0..<clampedCount {
            lines.insert(Array(repeating: TerminalCell(style: activeStyle), count: columns), at: cursorRow)
            lines.remove(at: scrollRegionBottom + 1)
        }
    }

    mutating func deleteLines(_ count: Int) {
        guard count > 0 else {
            return
        }

        guard cursorRow >= scrollRegionTop, cursorRow <= scrollRegionBottom else {
            return
        }

        let clampedCount = min(count, scrollRegionBottom - cursorRow + 1)
        for _ in 0..<clampedCount {
            lines.remove(at: cursorRow)
            lines.insert(
                Array(repeating: TerminalCell(style: activeStyle), count: columns),
                at: scrollRegionBottom
            )
        }
    }

    func snapshot() -> TerminalBufferSnapshot {
        TerminalBufferSnapshot(
            columns: columns,
            rows: rows,
            styledLines: lines.map { TerminalStyledLine(cells: $0) },
            cursor: TerminalCursorState(row: cursorRow, column: cursorColumn, isVisible: isCursorVisible),
            scrollbackLineCount: scrollbackLineCount,
            isBracketedPasteEnabled: isBracketedPasteEnabled,
            isApplicationCursorKeysEnabled: isApplicationCursorKeysEnabled,
            mouseTrackingMode: mouseTrackingMode,
            isSgrMouseModeEnabled: isSgrMouseModeEnabled,
            isAlternateScreenActive: isAlternateScreenActive
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
            lines[row][index] = TerminalCell(style: activeStyle)
        }
    }

    private mutating func scrollUp(from topRow: Int, to bottomRow: Int, by count: Int, appendToScrollback: Bool) {
        guard topRow >= 0,
              bottomRow < rows,
              topRow <= bottomRow,
              count > 0 else {
            return
        }

        for _ in 0..<count {
            let scrolledLine = lines.remove(at: topRow)
            if appendToScrollback, !isAlternateScreenActive {
                scrollback.append(scrolledLine)
                if scrollback.count > Self.maxScrollbackLines {
                    scrollback.removeFirst(scrollback.count - Self.maxScrollbackLines)
                }
                scrollbackLineCount += 1
            }
            lines.insert(Array(repeating: TerminalCell(style: activeStyle), count: columns), at: bottomRow)
        }
    }

    func fullText() -> String {
        var renderedLines = (scrollback + lines).map { row in
            renderLine(row)
        }

        while renderedLines.last?.isEmpty == true {
            renderedLines.removeLast()
        }

        return renderedLines.joined(separator: "\n")
    }

    private func renderLine(_ row: [TerminalCell]) -> String {
        var characters = row.map(\.character)
        while let last = characters.last, last == " " {
            characters.removeLast()
        }
        return characters.joined()
    }

    private func parseExtendedColor(from params: [Int]) -> (TerminalColor, Int)? {
        guard let mode = params.first else {
            return nil
        }

        switch mode {
        case 5:
            guard params.count >= 2 else {
                return nil
            }
            return (.ansi256(max(0, min(255, params[1]))), 2)
        case 2:
            guard params.count >= 4 else {
                return nil
            }
            return (
                .rgb(
                    red: max(0, min(255, params[1])),
                    green: max(0, min(255, params[2])),
                    blue: max(0, min(255, params[3]))
                ),
                4
            )
        default:
            return nil
        }
    }

    private func mapCharacterForActiveCharset(_ character: Character) -> Character {
        guard isShiftOut, g0Charset == .lineDrawing else {
            return character
        }

        switch character {
        case "j": return "┘"
        case "k": return "┐"
        case "l": return "┌"
        case "m": return "└"
        case "n": return "┼"
        case "q": return "─"
        case "t": return "├"
        case "u": return "┤"
        case "v": return "┴"
        case "w": return "┬"
        case "x": return "│"
        default: return character
        }
    }

    private mutating func setAlternateScreen(enabled: Bool, saveAndRestoreCursor: Bool) {
        if enabled {
            if saveAndRestoreCursor {
                saveCursor()
            }
            if !isAlternateScreenActive {
                mainScreenSnapshot = captureCurrentState()
                isAlternateScreenActive = true
            }
            clearActiveScreenForAlternateMode()
            return
        }

        guard isAlternateScreenActive else {
            if saveAndRestoreCursor {
                restoreCursor()
            }
            return
        }

        if let snapshot = mainScreenSnapshot {
            restore(from: snapshot)
        }
        isAlternateScreenActive = false
        mainScreenSnapshot = nil
        if saveAndRestoreCursor {
            restoreCursor()
        }
    }

    private func captureCurrentState() -> ScreenStateSnapshot {
        ScreenStateSnapshot(
            lines: lines,
            scrollback: scrollback,
            cursorRow: cursorRow,
            cursorColumn: cursorColumn,
            isCursorVisible: isCursorVisible,
            savedCursor: savedCursor,
            scrollbackLineCount: scrollbackLineCount,
            scrollRegionTop: scrollRegionTop,
            scrollRegionBottom: scrollRegionBottom,
            g0Charset: g0Charset,
            isShiftOut: isShiftOut,
            isAutowrapEnabled: isAutowrapEnabled,
            isBracketedPasteEnabled: isBracketedPasteEnabled,
            isApplicationCursorKeysEnabled: isApplicationCursorKeysEnabled,
            mouseTrackingMode: mouseTrackingMode,
            isSgrMouseModeEnabled: isSgrMouseModeEnabled
        )
    }

    private mutating func restore(from snapshot: ScreenStateSnapshot) {
        lines = snapshot.lines
        scrollback = snapshot.scrollback
        cursorRow = snapshot.cursorRow
        cursorColumn = snapshot.cursorColumn
        isCursorVisible = snapshot.isCursorVisible
        savedCursor = snapshot.savedCursor
        scrollbackLineCount = snapshot.scrollbackLineCount
        scrollRegionTop = snapshot.scrollRegionTop
        scrollRegionBottom = snapshot.scrollRegionBottom
        g0Charset = snapshot.g0Charset
        isShiftOut = snapshot.isShiftOut
        isAutowrapEnabled = snapshot.isAutowrapEnabled
        isBracketedPasteEnabled = snapshot.isBracketedPasteEnabled
        isApplicationCursorKeysEnabled = snapshot.isApplicationCursorKeysEnabled
        mouseTrackingMode = snapshot.mouseTrackingMode
        isSgrMouseModeEnabled = snapshot.isSgrMouseModeEnabled
        repairInvariants()
    }

    private mutating func clearActiveScreenForAlternateMode() {
        lines = Array(
            repeating: Array(repeating: TerminalCell(style: activeStyle), count: columns),
            count: rows
        )
        scrollback = []
        scrollbackLineCount = 0
        cursorRow = 0
        cursorColumn = 0
        scrollRegionTop = 0
        scrollRegionBottom = rows - 1
        g0Charset = .ascii
        isShiftOut = false
        isAutowrapEnabled = true
        isBracketedPasteEnabled = false
        isApplicationCursorKeysEnabled = false
        mouseTrackingMode = .none
        isSgrMouseModeEnabled = false
        repairInvariants()
    }

    mutating func repairInvariants() {
        columns = max(1, columns)
        rows = max(1, rows)

        if lines.count < rows {
            lines.append(
                contentsOf: Array(
                    repeating: Array(repeating: TerminalCell(style: activeStyle), count: columns),
                    count: rows - lines.count
                )
            )
        } else if lines.count > rows {
            lines.removeLast(lines.count - rows)
        }

        for index in lines.indices {
            if lines[index].count < columns {
                lines[index].append(
                    contentsOf: Array(repeating: TerminalCell(style: activeStyle), count: columns - lines[index].count)
                )
            } else if lines[index].count > columns {
                lines[index].removeLast(lines[index].count - columns)
            }
        }

        for index in scrollback.indices {
            if scrollback[index].count < columns {
                scrollback[index].append(
                    contentsOf: Array(repeating: TerminalCell(style: activeStyle), count: columns - scrollback[index].count)
                )
            } else if scrollback[index].count > columns {
                scrollback[index].removeLast(scrollback[index].count - columns)
            }
        }

        cursorRow = min(max(cursorRow, 0), rows - 1)
        cursorColumn = min(max(cursorColumn, 0), columns - 1)
        savedCursor = TerminalCursorState(
            row: min(max(savedCursor.row, 0), rows - 1),
            column: min(max(savedCursor.column, 0), columns - 1),
            isVisible: savedCursor.isVisible
        )
        scrollRegionTop = min(max(scrollRegionTop, 0), rows - 1)
        scrollRegionBottom = min(max(scrollRegionBottom, scrollRegionTop), rows - 1)
        scrollbackLineCount = max(0, scrollbackLineCount)
    }
}
