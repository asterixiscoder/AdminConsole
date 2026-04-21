@preconcurrency import AppIntents
import UIKit
import PersistenceKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task {
            await AppEnvironment.hostCatalog.startIfNeeded()
        }
        if #available(iOS 16.0, *) {
            AdminConsoleShortcutsProvider.updateAppShortcutParameters()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configurationName: String
        let delegateClass: AnyClass

        switch connectingSceneSession.role {
        case .windowExternalDisplay:
            configurationName = "Desktop External Configuration"
            delegateClass = DesktopSceneDelegate.self
        default:
            configurationName = "Phone Control Configuration"
            delegateClass = ControlSceneDelegate.self
        }

        let configuration = UISceneConfiguration(
            name: configurationName,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = delegateClass
        configuration.sceneClass = UIWindowScene.self
        configuration.storyboard = nil
        return configuration
    }
}

@MainActor
enum AppEnvironment {
    static let phaseZero = PhaseZeroCoordinator()
    static let rebootModel = RebootAppModel()
    static let hostCatalog = HostCatalogStore(
        persistence: UserDefaultsHostCatalogPersistence()
    )
}

enum AppIntentRouteTarget: String, Codable {
    case vaults
    case connections
    case profile
    case terminal
    case connectHost
}

struct AppIntentRoute: Codable {
    let target: AppIntentRouteTarget
    let hostID: UUID?
}

enum AppIntentRouteStore {
    private static let storageKey = "TermiusReboot.AppIntentRoute.v1"

    static func enqueue(_ route: AppIntentRoute) {
        guard let encoded = try? JSONEncoder().encode(route) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    static func dequeue() -> AppIntentRoute? {
        guard let encoded = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        return try? JSONDecoder().decode(AppIntentRoute.self, from: encoded)
    }
}

private struct StoredHost: Codable {
    let id: UUID
    let vault: String
    let name: String
    let note: String
    let hostname: String
    let port: Int
    let username: String
    let isFavorite: Bool
    let lastConnectedAt: Date?
}

private struct StoredHostSnapshot: Codable {
    let hosts: [StoredHost]
    let recents: [UUID]
}

private enum StoredHostRepository {
    private static let storageKey = "TermiusReboot.HostStore.v1"

    static func allHosts() -> [StoredHostEntity] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(StoredHostSnapshot.self, from: data) else {
            return []
        }

        return snapshot.hosts.map { host in
            StoredHostEntity(
                id: host.id,
                name: host.name,
                hostname: host.hostname,
                username: host.username,
                port: host.port,
                vault: host.vault,
                isFavorite: host.isFavorite
            )
        }.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

struct StoredHostEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Host")
    static let defaultQuery = StoredHostEntityQuery()

    let id: UUID
    var name: String
    var hostname: String
    var username: String
    var port: Int
    var vault: String
    var isFavorite: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(username)@\(hostname):\(port)"
        )
    }
}

struct StoredHostEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [StoredHostEntity.ID]) async throws -> [StoredHostEntity] {
        let allHosts = StoredHostRepository.allHosts()
        let map = Dictionary(uniqueKeysWithValues: allHosts.map { ($0.id, $0) })
        return identifiers.compactMap { map[$0] }
    }

    func suggestedEntities() async throws -> [StoredHostEntity] {
        StoredHostRepository.allHosts()
    }

    func entities(matching string: String) async throws -> [StoredHostEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return StoredHostRepository.allHosts()
        }

        return StoredHostRepository.allHosts().filter { host in
            host.name.lowercased().contains(needle)
                || host.hostname.lowercased().contains(needle)
                || host.username.lowercased().contains(needle)
                || host.vault.lowercased().contains(needle)
        }
    }
}

enum WorkspaceDestination: String, AppEnum {
    case vaults
    case connections
    case profile
    case terminal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
    static let caseDisplayRepresentations: [WorkspaceDestination: DisplayRepresentation] = [
        .vaults: "Vaults",
        .connections: "Connections",
        .profile: "Profile",
        .terminal: "Terminal"
    ]

    var routeTarget: AppIntentRouteTarget {
        switch self {
        case .vaults:
            return .vaults
        case .connections:
            return .connections
        case .profile:
            return .profile
        case .terminal:
            return .terminal
        }
    }
}

struct OpenWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Workspace"
    static let description = IntentDescription("Open a destination in AdminConsole.")

    @Parameter(title: "Destination")
    var destination: WorkspaceDestination

    static var openAppWhenRun: Bool { true }

    init() {
        destination = .terminal
    }

    func perform() async throws -> some IntentResult {
        AppIntentRouteStore.enqueue(
            AppIntentRoute(target: destination.routeTarget, hostID: nil)
        )
        return .result()
    }
}

struct ConnectSavedHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Saved Host"
    static let description = IntentDescription("Open AdminConsole and prefill a saved host for connection.")

    @Parameter(title: "Host")
    var host: StoredHostEntity

    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        AppIntentRouteStore.enqueue(
            AppIntentRoute(target: .connectHost, hostID: host.id)
        )
        return .result()
    }
}

struct AdminConsoleShortcutsProvider: AppShortcutsProvider {
    static let appShortcuts: [AppShortcut] = [
        AppShortcut(
            intent: OpenWorkspaceIntent(),
            phrases: [
                "Open \(.applicationName) terminal",
                "Show workspace in \(.applicationName)"
            ],
            shortTitle: "Open Workspace",
            systemImageName: "rectangle.3.group.bubble.left.fill"
        ),
        AppShortcut(
            intent: ConnectSavedHostIntent(),
            phrases: [
                "Connect to \(\.$host) in \(.applicationName)",
                "Start session to \(\.$host) in \(.applicationName)"
            ],
            shortTitle: "Connect Host",
            systemImageName: "bolt.horizontal.circle.fill"
        )
    ]

    static let shortcutTileColor: ShortcutTileColor = .blue
}
