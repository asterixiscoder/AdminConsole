import DesktopDomain
import Foundation

public struct BrowserWindowModel: Sendable, Equatable {
    public var window: DesktopWindow
    public var currentURL: URL?

    public init(window: DesktopWindow, currentURL: URL? = nil) {
        self.window = window
        self.currentURL = currentURL
    }
}
