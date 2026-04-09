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
}
