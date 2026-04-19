import Foundation

public struct HostRecordID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }
}

public struct SavedHostRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: HostRecordID
    public var vaultName: String
    public var title: String
    public var subtitle: String
    public var host: String
    public var port: Int
    public var username: String
    public var isFavorite: Bool
    public var lastConnectedAt: Date?

    public init(
        id: HostRecordID = HostRecordID(),
        vaultName: String,
        title: String,
        subtitle: String,
        host: String,
        port: Int,
        username: String,
        isFavorite: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.vaultName = vaultName
        self.title = title
        self.subtitle = subtitle
        self.host = host
        self.port = max(1, port)
        self.username = username
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
    }

    public var uniqueConnectionKey: String {
        "\(username.lowercased())@\(host.lowercased()):\(port)"
    }
}

public struct HostCatalogSnapshot: Codable, Equatable, Sendable {
    public var hosts: [SavedHostRecord]
    public var recentHostIDs: [HostRecordID]

    public init(hosts: [SavedHostRecord] = [], recentHostIDs: [HostRecordID] = []) {
        self.hosts = hosts
        self.recentHostIDs = recentHostIDs
    }

    public static let empty = HostCatalogSnapshot()
}

public struct HostCatalogSection: Equatable, Sendable {
    public var title: String
    public var hosts: [SavedHostRecord]

    public init(title: String, hosts: [SavedHostRecord]) {
        self.title = title
        self.hosts = hosts
    }
}

public protocol HostCatalogPersistence: Sendable {
    func loadCatalog() async throws -> HostCatalogSnapshot
    func saveCatalog(_ snapshot: HostCatalogSnapshot) async throws
}

public actor InMemoryHostCatalogPersistence: HostCatalogPersistence {
    private var snapshot: HostCatalogSnapshot

    public init(snapshot: HostCatalogSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func loadCatalog() async throws -> HostCatalogSnapshot {
        snapshot
    }

    public func saveCatalog(_ snapshot: HostCatalogSnapshot) async throws {
        self.snapshot = snapshot
    }
}

public actor UserDefaultsHostCatalogPersistence: HostCatalogPersistence {
    public static let defaultStorageKey = "AdminConsole.HostCatalog"

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = UserDefaultsHostCatalogPersistence.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func loadCatalog() async throws -> HostCatalogSnapshot {
        guard let data = defaults.data(forKey: storageKey) else {
            return .empty
        }

        return try decoder.decode(HostCatalogSnapshot.self, from: data)
    }

    public func saveCatalog(_ snapshot: HostCatalogSnapshot) async throws {
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: storageKey)
    }
}

public actor HostCatalogStore {
    private let persistence: HostCatalogPersistence
    private let seedHosts: [SavedHostRecord]
    private var snapshot: HostCatalogSnapshot
    private var didLoad = false

    public init(
        persistence: HostCatalogPersistence = InMemoryHostCatalogPersistence(),
        seedHosts: [SavedHostRecord] = HostCatalogStore.defaultSeedHosts
    ) {
        self.persistence = persistence
        self.seedHosts = seedHosts
        self.snapshot = .empty
    }

    public func startIfNeeded() async {
        guard !didLoad else {
            return
        }

        didLoad = true

        do {
            snapshot = try await persistence.loadCatalog()
        } catch {
            snapshot = .empty
        }

        if snapshot.hosts.isEmpty {
            snapshot.hosts = seedHosts
            snapshot.recentHostIDs = []
            try? await persistence.saveCatalog(snapshot)
        }
    }

    public func allHosts() async -> [SavedHostRecord] {
        await startIfNeeded()
        return snapshot.hosts.sorted(by: hostSort)
    }

    public func sections() async -> [HostCatalogSection] {
        await startIfNeeded()

        let hostsByID = Dictionary(uniqueKeysWithValues: snapshot.hosts.map { ($0.id, $0) })
        var output: [HostCatalogSection] = []

        let favorites = snapshot.hosts
            .filter(\.isFavorite)
            .sorted(by: hostSort)
        if !favorites.isEmpty {
            output.append(HostCatalogSection(title: "Favorites", hosts: favorites))
        }

        let recentHosts = snapshot.recentHostIDs
            .compactMap { hostsByID[$0] }
            .sorted { lhs, rhs in
                let left = lhs.lastConnectedAt ?? .distantPast
                let right = rhs.lastConnectedAt ?? .distantPast
                return left > right
            }
        if !recentHosts.isEmpty {
            output.append(HostCatalogSection(title: "Recents", hosts: recentHosts))
        }

        let grouped = Dictionary(grouping: snapshot.hosts, by: \.vaultName)
        for vaultName in grouped.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard let hosts = grouped[vaultName]?.sorted(by: hostSort), !hosts.isEmpty else {
                continue
            }
            output.append(HostCatalogSection(title: vaultName, hosts: hosts))
        }

        return output
    }

    @discardableResult
    public func toggleFavorite(hostID: HostRecordID) async -> SavedHostRecord? {
        await startIfNeeded()
        guard let index = snapshot.hosts.firstIndex(where: { $0.id == hostID }) else {
            return nil
        }

        snapshot.hosts[index].isFavorite.toggle()
        try? await persistence.saveCatalog(snapshot)
        return snapshot.hosts[index]
    }

    public func recordConnection(
        host: String,
        port: Int,
        username: String,
        title: String,
        subtitle: String,
        vaultName: String
    ) async {
        await startIfNeeded()

        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedUser.isEmpty else {
            return
        }

        let normalizedPort = max(1, port)
        let now = Date()

        let matchIndex = snapshot.hosts.firstIndex(where: {
            $0.host.caseInsensitiveCompare(normalizedHost) == .orderedSame
                && $0.port == normalizedPort
                && $0.username.caseInsensitiveCompare(normalizedUser) == .orderedSame
        })

        let recordID: HostRecordID
        if let matchIndex {
            snapshot.hosts[matchIndex].title = title
            snapshot.hosts[matchIndex].subtitle = subtitle
            snapshot.hosts[matchIndex].vaultName = vaultName
            snapshot.hosts[matchIndex].lastConnectedAt = now
            recordID = snapshot.hosts[matchIndex].id
        } else {
            let newRecord = SavedHostRecord(
                vaultName: vaultName,
                title: title,
                subtitle: subtitle,
                host: normalizedHost,
                port: normalizedPort,
                username: normalizedUser,
                isFavorite: false,
                lastConnectedAt: now
            )
            snapshot.hosts.append(newRecord)
            recordID = newRecord.id
        }

        snapshot.recentHostIDs.removeAll(where: { $0 == recordID })
        snapshot.recentHostIDs.insert(recordID, at: 0)
        snapshot.recentHostIDs = Array(snapshot.recentHostIDs.prefix(12))

        try? await persistence.saveCatalog(snapshot)
    }

    private func hostSort(_ lhs: SavedHostRecord, _ rhs: SavedHostRecord) -> Bool {
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) != .orderedSame {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        if lhs.host.localizedCaseInsensitiveCompare(rhs.host) != .orderedSame {
            return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
        }

        if lhs.username.localizedCaseInsensitiveCompare(rhs.username) != .orderedSame {
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }

        return lhs.port < rhs.port
    }

    public static let defaultSeedHosts: [SavedHostRecord] = [
        SavedHostRecord(
            vaultName: "Production",
            title: "web-eu-01",
            subtitle: "Nginx + API",
            host: "web-eu-01.internal",
            port: 22,
            username: "ops"
        ),
        SavedHostRecord(
            vaultName: "Production",
            title: "db-eu-01",
            subtitle: "PostgreSQL Primary",
            host: "db-eu-01.internal",
            port: 22,
            username: "dba"
        ),
        SavedHostRecord(
            vaultName: "Staging",
            title: "stage-web-01",
            subtitle: "Integration Tests",
            host: "stage-web-01.internal",
            port: 22,
            username: "qa"
        ),
        SavedHostRecord(
            vaultName: "Staging",
            title: "stage-bastion",
            subtitle: "Jump Host",
            host: "stage-bastion.internal",
            port: 22,
            username: "qa"
        ),
        SavedHostRecord(
            vaultName: "Lab",
            title: "raspi-k3s",
            subtitle: "Edge Cluster Node",
            host: "raspi-k3s.local",
            port: 22,
            username: "pi"
        ),
        SavedHostRecord(
            vaultName: "Lab",
            title: "nas-storage",
            subtitle: "Backups",
            host: "nas-storage.local",
            port: 22,
            username: "backup"
        )
    ]
}
