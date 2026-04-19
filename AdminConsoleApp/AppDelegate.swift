import UIKit
import PersistenceKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task {
            await AppEnvironment.phaseZero.startIfNeeded()
            await AppEnvironment.hostCatalog.startIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        switch connectingSceneSession.role {
        case .windowExternalDisplayNonInteractive:
            return UISceneConfiguration(
                name: "External Desktop Configuration",
                sessionRole: connectingSceneSession.role
            )
        case .windowApplication:
            fallthrough
        default:
            return UISceneConfiguration(
                name: "Phone Control Configuration",
                sessionRole: connectingSceneSession.role
            )
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task {
            await AppEnvironment.phaseZero.applicationDidEnterBackground()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task {
            await AppEnvironment.phaseZero.applicationWillEnterForeground()
        }
    }
}

enum AppEnvironment {
    static let phaseZero = PhaseZeroCoordinator()
    static let hostCatalog = HostCatalogStore(
        persistence: UserDefaultsHostCatalogPersistence()
    )
}
