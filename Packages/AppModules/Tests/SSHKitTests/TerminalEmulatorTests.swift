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
}
