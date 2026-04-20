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
        let rootViewController = RebootRootTabBarController()
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.backgroundColor = .systemBackground
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        self.window = window
    }
}
