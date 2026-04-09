import DesktopDomain

public struct FilesWorkspace: Sendable, Equatable {
    public var rootPath: String
    public var activeWindow: DesktopWindow

    public init(rootPath: String, activeWindow: DesktopWindow) {
        self.rootPath = rootPath
        self.activeWindow = activeWindow
    }
}
