import AppPlatform
import UIKit

final class DesktopSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        Task {
            await AppEnvironment.phaseZero.startIfNeeded()
            await AppEnvironment.phaseZero.setExternalDisplayConnected(
                true,
                size: windowScene.screen.bounds.size,
                scale: windowScene.screen.scale
            )
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DesktopRootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Task {
            await AppEnvironment.phaseZero.setExternalDisplayConnected(false)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        Task {
            await AppEnvironment.phaseZero.setExternalDisplayConnected(
                true,
                size: windowScene.screen.bounds.size,
                scale: windowScene.screen.scale
            )
        }
    }
}
