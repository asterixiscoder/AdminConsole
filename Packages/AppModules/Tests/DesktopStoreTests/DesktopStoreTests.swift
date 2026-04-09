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
}
