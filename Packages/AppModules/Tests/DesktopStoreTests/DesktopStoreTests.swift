import DesktopDomain
import DesktopStore
import XCTest

final class DesktopStoreTests: XCTestCase {
    func testOpenWindowIncreasesRevision() async {
        let store = DesktopStore()

        let snapshot = await store.dispatch(.openWindow(.terminal))

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.revision, 1)
        XCTAssertEqual(snapshot.focusedWindowID, snapshot.windows.first?.id)
    }

    func testUpdateTerminalSurfaceStoresTranscriptAndTitle() async throws {
        let store = DesktopStore()
        let initial = await store.dispatch(.openWindow(.terminal))
        let windowID = try XCTUnwrap(initial.windows.first?.id)

        let updatedSurface = TerminalSurfaceState(
            connectionTitle: "root@example.com:22",
            sessionState: .connected,
            statusMessage: "Connected",
            transcript: "uname -a\nDarwin\n",
            columns: 132,
            rows: 40
        )

        let snapshot = await store.dispatch(.updateTerminalSurface(windowID: windowID, surface: updatedSurface))
        let terminalWindow = try XCTUnwrap(snapshot.windows.first(where: { $0.id == windowID }))

        XCTAssertEqual(terminalWindow.title, "root@example.com:22")
        XCTAssertEqual(terminalWindow.terminalState, updatedSurface)
        XCTAssertEqual(snapshot.revision, 2)
    }

    func testUpdateTerminalSurfaceUsesScreenTitleForWindowChrome() async throws {
        let store = DesktopStore()
        let initial = await store.dispatch(.openWindow(.terminal))
        let windowID = try XCTUnwrap(initial.windows.first?.id)

        let updatedSurface = TerminalSurfaceState(
            connectionTitle: "root@example.com:22",
            screenTitle: "htop",
            sessionState: .connected,
            statusMessage: "Connected",
            transcript: "",
            columns: 120,
            rows: 32
        )

        let snapshot = await store.dispatch(.updateTerminalSurface(windowID: windowID, surface: updatedSurface))
        let terminalWindow = try XCTUnwrap(snapshot.windows.first(where: { $0.id == windowID }))

        XCTAssertEqual(terminalWindow.title, "htop")
        XCTAssertEqual(terminalWindow.terminalState?.connectionTitle, "root@example.com:22")
        XCTAssertEqual(terminalWindow.terminalState?.screenTitle, "htop")
    }

    func testTerminalBufferSelectedTextSpansMultipleRows() {
        let buffer = TerminalBufferSnapshot(
            columns: 5,
            rows: 3,
            viewportLines: ["abcde", "fghij", "klmno"]
        )

        let selection = TerminalSelection(
            anchor: TerminalGridPoint(row: 0, column: 2),
            focus: TerminalGridPoint(row: 1, column: 1)
        )

        XCTAssertEqual(buffer.selectedText(for: selection), "cde\nfg")
    }

    func testTerminalSurfaceClampsSelectionWhenBufferChanges() {
        var state = TerminalSurfaceState(
            connectionTitle: "Terminal",
            sessionState: .connected,
            transcript: "",
            columns: 5,
            rows: 3,
            buffer: TerminalBufferSnapshot(columns: 5, rows: 3, viewportLines: ["abcde", "fghij", "klmno"]),
            selection: TerminalSelection(
                anchor: TerminalGridPoint(row: 2, column: 4),
                focus: TerminalGridPoint(row: 2, column: 4)
            )
        )

        state.replaceBuffer(
            TerminalBufferSnapshot(columns: 3, rows: 2, viewportLines: ["abc", "def"])
        )

        XCTAssertEqual(
            state.selection,
            TerminalSelection(
                anchor: TerminalGridPoint(row: 1, column: 2),
                focus: TerminalGridPoint(row: 1, column: 2)
            )
        )
    }
}
