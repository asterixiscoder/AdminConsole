import AppPlatform
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task {
            await AppEnvironment.phaseZero.startIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        switch connectingSceneSession.role {
        case .windowExternalDisplay:
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
}

enum AppEnvironment {
    static let phaseZero = PhaseZeroCoordinator()
}
