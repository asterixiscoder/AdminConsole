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
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Phone Control Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}

enum AppEnvironment {
    static let phaseZero = PhaseZeroCoordinator()
    static let hostCatalog = HostCatalogStore(
        persistence: UserDefaultsHostCatalogPersistence()
    )
}
