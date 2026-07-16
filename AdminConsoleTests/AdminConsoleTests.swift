import Foundation
import XCTest
@testable import AdminConsoleApp
import PersistenceKit

final class AdminConsoleTests: XCTestCase {
    func testStoredHostEntityQueryReadsFromCatalogStore() async throws {
        let suiteName = "AdminConsoleTests.HostCatalog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsHostCatalogPersistence(defaults: defaults, storageKey: suiteName)
        let store = HostCatalogStore(persistence: persistence, seedHosts: [])

        let createdWeb = await store.createHost(
            vaultName: "Production",
            title: "web-01",
            subtitle: "",
            host: "web-01.internal",
            port: 22,
            username: "ops",
            isFavorite: true
        )
        XCTAssertNotNil(createdWeb)

        let createdDb = await store.createHost(
            vaultName: "Production",
            title: "db-01",
            subtitle: "",
            host: "db-01.internal",
            port: 22,
            username: "dba",
            isFavorite: false
        )
        XCTAssertNotNil(createdDb)

        let query = StoredHostEntityQuery(repository: StoredHostRepository(store: store))
        let hosts = try await query.suggestedEntities()

        XCTAssertEqual(hosts.map(\.name), ["db-01", "web-01"])
        XCTAssertEqual(hosts.map(\.hostname), ["db-01.internal", "web-01.internal"])
        XCTAssertEqual(hosts.map(\.vault), ["Production", "Production"])
    }

    func testStoredHostEntityQueryFiltersAndResolvesIdentifiers() async throws {
        let suiteName = "AdminConsoleTests.HostCatalog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsHostCatalogPersistence(defaults: defaults, storageKey: suiteName)
        let store = HostCatalogStore(persistence: persistence, seedHosts: [])

        let created = await store.createHost(
            vaultName: "Lab",
            title: "stage-bastion",
            subtitle: "",
            host: "stage-bastion.internal",
            port: 22,
            username: "qa",
            isFavorite: false
        )
        XCTAssertNotNil(created)

        guard let created else {
            return
        }

        let query = StoredHostEntityQuery(repository: StoredHostRepository(store: store))
        let filtered = try await query.entities(matching: "bastion")
        XCTAssertEqual(filtered.map(\.name), ["stage-bastion"])

        let resolved = try await query.entities(for: [created.id.rawValue])
        XCTAssertEqual(resolved.map(\.name), ["stage-bastion"])
        XCTAssertEqual(resolved.first?.username, "qa")
    }
}
