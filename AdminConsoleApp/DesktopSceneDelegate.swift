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
            await updateDisplayMetrics(for: windowScene)
        }

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = DesktopRootViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Task {
            await AppEnvironment.phaseZero.setExternalDisplayConnected(false)
        }
    }

    func sceneDidActivate(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        Task {
            await updateDisplayMetrics(for: windowScene)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        Task {
            await updateDisplayMetrics(for: windowScene)
        }
    }

    private func updateDisplayMetrics(for windowScene: UIWindowScene) async {
        let sceneBounds = windowScene.coordinateSpace.bounds
        window?.frame = sceneBounds
        let windowBounds = window?.bounds ?? sceneBounds
        let pointSize = CGSize(
            width: max(sceneBounds.width, windowBounds.width),
            height: max(sceneBounds.height, windowBounds.height)
        )

        // Prefer physical-ish pixel mapping for better SSH/VNC sizing on external monitors.
        let effectiveScale = max(windowScene.screen.nativeScale, windowScene.screen.scale)

        await AppEnvironment.phaseZero.setExternalDisplayConnected(
            true,
            size: pointSize,
            scale: effectiveScale
        )
    }
}
