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
