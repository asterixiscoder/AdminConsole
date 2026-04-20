@testable import SSHKit
import DesktopDomain
import XCTest

final class TerminalEmulatorTests: XCTestCase {
    func testParsesCursorMovesAndLineErase() {
        var emulator = TerminalEmulator(columns: 8, rows: 3)

        emulator.consume("hello")
        emulator.consume("\u{001B}[2;1H")
        emulator.consume("row2")
        emulator.consume("\u{001B}[2;3H")
        emulator.consume("\u{001B}[K")

        let snapshot = emulator.makeBufferSnapshot()

        XCTAssertEqual(snapshot.viewportLines[0], "hello")
        XCTAssertEqual(snapshot.viewportLines[1], "ro")
        XCTAssertEqual(snapshot.cursor.row, 1)
        XCTAssertEqual(snapshot.cursor.column, 2)
    }

    func testHandlesPartialCSISequencesAcrossChunks() {
        var emulator = TerminalEmulator(columns: 12, rows: 2)

        emulator.consume("status: old")
        emulator.consume("\u{001B}[2")
        emulator.consume("K\rstatus: ok")

        let snapshot = emulator.makeBufferSnapshot()

        XCTAssertEqual(snapshot.viewportLines[0], "status: ok")
        XCTAssertEqual(snapshot.cursor.column, 10)
    }

    func testScrollbackAndCursorVisibility() {
        var emulator = TerminalEmulator(columns: 6, rows: 2)

        emulator.consume("one\r\n")
        emulator.consume("two\r\n")
        emulator.consume("three")
        emulator.consume("\u{001B}[?25l")

        let snapshot = emulator.makeBufferSnapshot()

        XCTAssertEqual(snapshot.viewportLines, ["two", "three"])
        XCTAssertEqual(snapshot.scrollbackLineCount, 1)
        XCTAssertFalse(snapshot.cursor.isVisible)
    }

    func testBufferSnapshotRendersCursorOverlay() {
        let snapshot = TerminalBufferSnapshot(
            columns: 4,
            rows: 2,
            viewportLines: ["abc", ""],
            cursor: TerminalCursorState(row: 0, column: 1, isVisible: true)
        )

        XCTAssertEqual(snapshot.viewportText(insertingCursor: true), "a█c\n")
    }

    func testParsesBasicSGRAttributesAndColors() {
        var emulator = TerminalEmulator(columns: 12, rows: 2)

        emulator.consume("\u{001B}[31;44;1mA")
        emulator.consume("\u{001B}[4;7mB")
        emulator.consume("\u{001B}[0mC")

        let snapshot = emulator.makeBufferSnapshot()
        let firstLine = snapshot.styledLines[0].cells

        XCTAssertEqual(firstLine[0].character, "A")
        XCTAssertEqual(firstLine[0].style.foreground, .ansi256(1))
        XCTAssertEqual(firstLine[0].style.background, .ansi256(4))
        XCTAssertTrue(firstLine[0].style.isBold)

        XCTAssertEqual(firstLine[1].character, "B")
        XCTAssertTrue(firstLine[1].style.isUnderlined)
        XCTAssertTrue(firstLine[1].style.isInverse)

        XCTAssertEqual(firstLine[2].character, "C")
        XCTAssertEqual(firstLine[2].style, .default)
    }

    func testParsesExtendedAnsiAndTrueColorSequences() {
        var emulator = TerminalEmulator(columns: 12, rows: 1)

        emulator.consume("\u{001B}[38;5;202;48;2;10;20;30mZ")

        let cell = emulator.makeBufferSnapshot().styledLines[0].cells[0]
        XCTAssertEqual(cell.style.foreground, .ansi256(202))
        XCTAssertEqual(cell.style.background, .rgb(red: 10, green: 20, blue: 30))
    }

    func testParsesOSCTitleUpdatesAcrossChunks() {
        var emulator = TerminalEmulator(columns: 12, rows: 1)

        emulator.consume("\u{001B}]0;build")
        emulator.consume(" host\u{0007}")

        XCTAssertEqual(emulator.currentScreenTitle(), "build host")
    }

    func testTranscriptAppliesBackspaceToCurrentLine() {
        var emulator = TerminalEmulator(columns: 12, rows: 2)

        emulator.consume("nn")
        emulator.consume("\u{0008}")
        emulator.consume("m")

        XCTAssertEqual(emulator.makeTranscript(), "nm")
        XCTAssertEqual(emulator.makeBufferSnapshot().viewportLines[0], "nm")
    }

    func testTranscriptHandlesCarriageReturnRedrawWithoutDuplication() {
        var emulator = TerminalEmulator(columns: 12, rows: 2)

        emulator.consume("l")
        emulator.consume("\r")
        emulator.consume("ls")

        XCTAssertEqual(emulator.makeTranscript(), "ls")
        XCTAssertEqual(emulator.makeBufferSnapshot().viewportLines[0], "ls")
    }
}
