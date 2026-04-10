import Foundation

struct VT100Parser {
    struct ParseResult {
        var transcript: String = ""
        var screenTitle: String?
    }

    private enum State {
        case ground
        case escape
        case csi(String)
        case osc(String)
        case oscEscape(String)
    }

    private var state: State = .ground

    mutating func consume(_ text: String, into screen: inout TerminalScreenBuffer) -> ParseResult {
        var result = ParseResult()

        for scalar in text.unicodeScalars {
            switch state {
            case .ground:
                handleGround(scalar, screen: &screen, transcript: &result.transcript)
            case .escape:
                handleEscape(scalar, screen: &screen, transcript: &result.transcript)
            case .csi(let sequence):
                handleCSI(scalar, existing: sequence, screen: &screen)
            case .osc(let sequence):
                if scalar == "\u{0007}" {
                    finalizeOSC(sequence, result: &result)
                    state = .ground
                } else if scalar == "\u{001B}" {
                    state = .oscEscape(sequence)
                } else {
                    state = .osc(sequence + String(scalar))
                }
            case .oscEscape(let sequence):
                if scalar == "\\" {
                    finalizeOSC(sequence, result: &result)
                    state = .ground
                } else {
                    state = .osc(sequence)
                }
            }
        }

        result.transcript = result.transcript
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "")
        return result
    }

    private mutating func handleGround(
        _ scalar: UnicodeScalar,
        screen: inout TerminalScreenBuffer,
        transcript: inout String
    ) {
        switch scalar.value {
        case 0x1B:
            state = .escape
        case 0x0A:
            screen.lineFeed()
            transcript.append("\n")
        case 0x0D:
            screen.carriageReturn()
        case 0x08, 0x7F:
            screen.backspace()
        case 0x09:
            screen.tab()
            transcript.append("\t")
        case 0x0C:
            screen.lineFeed()
            screen.carriageReturn()
            transcript.append("\n")
        case 0x20...0x10FFFF:
            let character = Character(scalar)
            screen.put(character)
            transcript.append(String(character))
        default:
            break
        }
    }

    private mutating func handleEscape(
        _ scalar: UnicodeScalar,
        screen: inout TerminalScreenBuffer,
        transcript: inout String
    ) {
        switch scalar {
        case "[":
            state = .csi("")
        case "]":
            state = .osc("")
        case "7":
            screen.saveCursor()
            state = .ground
        case "8":
            screen.restoreCursor()
            state = .ground
        case "D":
            screen.lineFeed()
            transcript.append("\n")
            state = .ground
        case "E":
            screen.lineFeed()
            screen.carriageReturn()
            transcript.append("\n")
            state = .ground
        case "M":
            screen.moveCursor(rowDelta: -1, columnDelta: 0)
            state = .ground
        case "c":
            screen.resetStyle()
            screen.eraseInDisplay(mode: 2)
            state = .ground
        default:
            state = .ground
        }
    }

    private mutating func handleCSI(
        _ scalar: UnicodeScalar,
        existing sequence: String,
        screen: inout TerminalScreenBuffer
    ) {
        if scalar.value >= 0x40 && scalar.value <= 0x7E {
            executeCSI(sequence + String(scalar), screen: &screen)
            state = .ground
        } else {
            state = .csi(sequence + String(scalar))
        }
    }

    private func executeCSI(_ sequence: String, screen: inout TerminalScreenBuffer) {
        guard let final = sequence.last else {
            return
        }

        let body = String(sequence.dropLast())
        let isPrivate = body.hasPrefix("?")
        let params = parseParameters(isPrivate ? String(body.dropFirst()) : body)

        switch final {
        case "A":
            screen.moveCursor(rowDelta: -(params.first ?? 1))
        case "B":
            screen.moveCursor(rowDelta: params.first ?? 1)
        case "C":
            screen.moveCursor(columnDelta: params.first ?? 1)
        case "D":
            screen.moveCursor(columnDelta: -(params.first ?? 1))
        case "E":
            screen.moveCursor(rowDelta: params.first ?? 1)
            screen.carriageReturn()
        case "F":
            screen.moveCursor(rowDelta: -(params.first ?? 1))
            screen.carriageReturn()
        case "G":
            screen.moveCursorTo(row: screen.cursorRow, column: max(0, (params.first ?? 1) - 1))
        case "H", "f":
            screen.moveCursorTo(
                row: max(0, (params.first ?? 1) - 1),
                column: max(0, (params.dropFirst().first ?? 1) - 1)
            )
        case "J":
            screen.eraseInDisplay(mode: params.first ?? 0)
        case "K":
            screen.eraseInLine(mode: params.first ?? 0)
        case "L":
            screen.insertLines(params.first ?? 1)
        case "M":
            screen.deleteLines(params.first ?? 1)
        case "P":
            screen.deleteCharacters(params.first ?? 1)
        case "X":
            screen.eraseCharacters(params.first ?? 1)
        case "@":
            screen.insertBlankCharacters(params.first ?? 1)
        case "m":
            screen.applySGR(params)
        case "s":
            screen.saveCursor()
        case "u":
            screen.restoreCursor()
        case "h":
            if isPrivate, params == [25] {
                screen.setCursorVisibility(true)
            }
        case "l":
            if isPrivate, params == [25] {
                screen.setCursorVisibility(false)
            }
        default:
            break
        }
    }

    private func parseParameters(_ raw: String) -> [Int] {
        guard !raw.isEmpty else {
            return []
        }

        return raw
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }

    private func finalizeOSC(_ sequence: String, result: inout ParseResult) {
        let components = sequence.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let command = components.first.flatMap({ Int($0) }) else {
            return
        }

        let value = components.count > 1 ? String(components[1]) : ""
        guard !value.isEmpty else {
            return
        }

        switch command {
        case 0, 1, 2:
            result.screenTitle = value
        default:
            break
        }
    }
}
