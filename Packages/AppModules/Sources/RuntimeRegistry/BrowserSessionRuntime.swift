import DesktopDomain
import Foundation

public actor BrowserSessionRuntime {
    private let onSurfaceUpdate: @Sendable (BrowserSurfaceState) async -> Void

    private var surface: BrowserSurfaceState

    public init(
        windowID: WindowID,
        initialHomeURLString: String = "https://developer.apple.com",
        onSurfaceUpdate: @escaping @Sendable (BrowserSurfaceState) async -> Void
    ) {
        _ = windowID
        self.onSurfaceUpdate = onSurfaceUpdate
        self.surface = .idle(homeURLString: initialHomeURLString)
    }

    public func snapshot() -> BrowserSurfaceState {
        surface
    }

    public func start() async {
        await publish()
    }

    public func navigate(to rawAddress: String) async {
        let formatted = normalizeAddress(rawAddress.isEmpty ? surface.homeURLString : rawAddress)
        guard let parsedURL = URL(string: formatted) else {
            surface.statusMessage = "Invalid URL"
            surface.appendEvent("Navigation failed")
            await publish()
            return
        }

        guard isAllowedScheme(parsedURL) else {
            await noteBlockedNavigation(
                urlString: parsedURL.absoluteString,
                reason: "Scheme \(parsedURL.scheme?.lowercased() ?? "unknown") is not allowed"
            )
            return
        }

        surface.navigationCommand = nil
        surface.isLoading = true
        surface.statusMessage = "Loading \(formatted)"
        surface.pageTitle = nil
        surface.currentURLString = formatted
        surface.appendEvent("Navigate -> \(formatted)")
        await publish()
    }

    public func reload() async {
        guard surface.currentURLString != nil else {
            await navigate(to: surface.homeURLString)
            return
        }

        let current = surface.currentURLString ?? surface.homeURLString
        surface.navigationCommand = .reload
        surface.navigationCommandID += 1
        surface.isLoading = true
        surface.statusMessage = "Reloading \(current)"
        surface.appendEvent("Reload")
        await publish()
    }

    public func goBack() async {
        guard surface.canGoBack else {
            surface.statusMessage = "No back history"
            await publish()
            return
        }

        surface.navigationCommand = .goBack
        surface.navigationCommandID += 1
        surface.isLoading = true
        surface.statusMessage = "Navigating back"
        surface.appendEvent("Back")
        await publish()
    }

    public func goForward() async {
        guard surface.canGoForward else {
            surface.statusMessage = "No forward history"
            await publish()
            return
        }

        surface.navigationCommand = .goForward
        surface.navigationCommandID += 1
        surface.isLoading = true
        surface.statusMessage = "Navigating forward"
        surface.appendEvent("Forward")
        await publish()
    }

    public func syncWebViewState(
        urlString: String?,
        title: String?,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool
    ) async {
        let previousSurface = surface
        let previousURL = surface.currentURLString
        let wasLoading = surface.isLoading

        if let urlString, !urlString.isEmpty {
            surface.currentURLString = urlString
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        surface.pageTitle = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        surface.isLoading = isLoading
        surface.canGoBack = canGoBack
        surface.canGoForward = canGoForward

        let current = surface.currentURLString ?? surface.homeURLString
        if isLoading {
            surface.statusMessage = "Loading \(current)"
        } else {
            surface.statusMessage = "Page loaded"
            if wasLoading || previousURL != surface.currentURLString {
                surface.appendEvent("Loaded \(current)")
            }
        }

        guard surface != previousSurface else {
            return
        }

        await publish()
    }

    public func noteNavigationFailure(message: String) async {
        surface.isLoading = false
        surface.statusMessage = "Load failed: \(message)"
        surface.appendEvent("Error: \(message)")
        await publish()
    }

    public func noteBlockedNavigation(urlString: String?, reason: String) async {
        surface.isLoading = false
        if let urlString, !urlString.isEmpty {
            surface.statusMessage = "Blocked: \(reason)"
            surface.appendEvent("Blocked \(urlString)")
        } else {
            surface.statusMessage = "Blocked: \(reason)"
            surface.appendEvent("Blocked navigation")
        }
        await publish()
    }

    public func acknowledgeNavigationCommand(id: Int) async {
        guard surface.navigationCommandID == id else {
            return
        }

        guard surface.navigationCommand != nil else {
            return
        }

        surface.navigationCommand = nil
        await publish()
    }

    private func normalizeAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return surface.homeURLString
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        return "https://\(trimmed)"
    }

    private func isAllowedScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private func publish() async {
        await onSurfaceUpdate(surface)
    }
}
