import Foundation
import PersistenceKit
import XCTest

final class HostCatalogStoreTests: XCTestCase {
    func testSeedsDefaultHostsWhenStorageEmpty() async {
        let persistence = InMemoryHostCatalogPersistence()
        let store = HostCatalogStore(persistence: persistence)

        let hosts = await store.allHosts()

        XCTAssertGreaterThanOrEqual(hosts.count, 6)
        XCTAssertTrue(hosts.contains(where: { $0.vaultName == "Production" }))
    }

    func testRecordConnectionAddsRecentAndUpsertsHost() async {
        let persistence = InMemoryHostCatalogPersistence()
        let store = HostCatalogStore(persistence: persistence, seedHosts: [])

        await store.recordConnection(
            host: "demo.internal",
            port: 22,
            username: "ops",
            title: "demo",
            subtitle: "initial",
            vaultName: "Personal"
        )

        await store.recordConnection(
            host: "demo.internal",
            port: 22,
            username: "ops",
            title: "demo-updated",
            subtitle: "updated",
            vaultName: "Favorites"
        )

        let sections = await store.sections()
        let allHosts = await store.allHosts()

        XCTAssertEqual(allHosts.count, 1)
        XCTAssertEqual(allHosts.first?.title, "demo-updated")
        XCTAssertEqual(allHosts.first?.vaultName, "Favorites")

        let recents = sections.first(where: { $0.title == "Recents" })?.hosts ?? []
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.host, "demo.internal")
    }

    func testToggleFavoriteMovesHostIntoFavoritesSection() async throws {
        let seed = SavedHostRecord(
            vaultName: "Personal",
            title: "edge-box",
            subtitle: "lab",
            host: "edge.local",
            port: 22,
            username: "pi"
        )
        let persistence = InMemoryHostCatalogPersistence()
        let store = HostCatalogStore(persistence: persistence, seedHosts: [seed])

        let initial = await store.allHosts()
        let hostID = try XCTUnwrap(initial.first?.id)

        _ = await store.toggleFavorite(hostID: hostID)
        let sections = await store.sections()

        let favorites = sections.first(where: { $0.title == "Favorites" })?.hosts ?? []
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.host, "edge.local")
        XCTAssertEqual(favorites.first?.isFavorite, true)
    }
}
