import UIKit

final class ControlSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        let rootViewController = RebootRootViewController()
        let window = UIWindow(windowScene: windowScene)
        SceneWindowConfiguration.apply(
            to: window,
            backgroundColor: .systemBackground,
            rootViewController: rootViewController
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? RebootRootViewController)?.sceneDidEnterBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        (window?.rootViewController as? RebootRootViewController)?.sceneWillEnterForeground()
    }
}
