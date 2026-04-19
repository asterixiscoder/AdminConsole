import DesktopDomain
import DesktopStore
import WindowManager
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

    func testUpdateBrowserSurfaceStoresMetadataAndTitle() async throws {
        let store = DesktopStore()
        let initial = await store.dispatch(.openWindow(.browser))
        let windowID = try XCTUnwrap(initial.windows.first?.id)

        var surface = BrowserSurfaceState.idle()
        surface.currentURLString = "https://example.com/docs"
        surface.pageTitle = "Example Docs"
        surface.statusMessage = "Page loaded"
        surface.canGoBack = true

        let snapshot = await store.dispatch(.updateBrowserSurface(windowID: windowID, surface: surface))
        let browserWindow = try XCTUnwrap(snapshot.windows.first(where: { $0.id == windowID }))

        XCTAssertEqual(browserWindow.browserState, surface)
        XCTAssertEqual(browserWindow.title, "Example Docs")
    }

    func testToggleWindowMaximizedStoresAndRestoresFrame() async throws {
        let store = DesktopStore()
        let initial = await store.dispatch(.openWindow(.vnc))
        let windowID = try XCTUnwrap(initial.windows.first?.id)
        let originalFrame = try XCTUnwrap(initial.windows.first?.frame)

        let maximized = await store.dispatch(.toggleWindowMaximized(windowID))
        let maximizedWindow = try XCTUnwrap(maximized.windows.first(where: { $0.id == windowID }))
        XCTAssertTrue(maximizedWindow.isMaximized)
        XCTAssertEqual(maximizedWindow.frame, WindowManager.maximizedFrame())
        XCTAssertEqual(maximizedWindow.restoredFrame, WindowManager.fit(originalFrame))

        let restored = await store.dispatch(.toggleWindowMaximized(windowID))
        let restoredWindow = try XCTUnwrap(restored.windows.first(where: { $0.id == windowID }))
        XCTAssertFalse(restoredWindow.isMaximized)
        XCTAssertNil(restoredWindow.restoredFrame)
        XCTAssertEqual(restoredWindow.frame, WindowManager.fit(originalFrame))
    }

    func testUpdateWindowFrameClearsMaximizedState() async throws {
        let store = DesktopStore()
        let initial = await store.dispatch(.openWindow(.browser))
        let windowID = try XCTUnwrap(initial.windows.first?.id)
        _ = await store.dispatch(.toggleWindowMaximized(windowID))

        let movedFrame = NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.5)
        let snapshot = await store.dispatch(.updateWindowFrame(windowID: windowID, frame: movedFrame))
        let window = try XCTUnwrap(snapshot.windows.first(where: { $0.id == windowID }))

        XCTAssertFalse(window.isMaximized)
        XCTAssertNil(window.restoredFrame)
        XCTAssertEqual(window.frame, WindowManager.fit(movedFrame))
    }

    func testSetInputCaptureModePersistsInSnapshot() async {
        let store = DesktopStore()

        let updated = await store.dispatch(.setInputCaptureMode(.vnc))

        XCTAssertEqual(updated.inputCaptureMode, .vnc)
        XCTAssertEqual(updated.revision, 1)
    }

    func testSetActiveWorkModeFocusesMatchingWindowKind() async {
        let store = DesktopStore()

        _ = await store.dispatch(.openWindow(.terminal))
        _ = await store.dispatch(.openWindow(.browser))
        _ = await store.dispatch(.openWindow(.vnc))

        let updated = await store.dispatch(.setActiveWorkMode(.browser))
        let focused = updated.windows.first(where: { $0.id == updated.focusedWindowID })

        XCTAssertEqual(updated.activeWorkMode, .browser)
        XCTAssertEqual(focused?.kind, .browser)
    }
}
