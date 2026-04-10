import DesktopDomain
import Foundation

public actor FilesWorkspaceRuntime {
    public typealias StateSink = @Sendable (FilesSurfaceState) async -> Void

    private let windowID: WindowID
    private let fileManager: FileManager
    private let stateSink: StateSink
    private let rootURL: URL
    private var currentDirectoryURL: URL
    private var state: FilesSurfaceState

    public init(
        windowID: WindowID,
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        initialState: FilesSurfaceState = .idle(),
        stateSink: @escaping StateSink
    ) {
        let workspaceURL = rootURL ?? Self.defaultWorkspaceURL(fileManager: fileManager)

        self.windowID = windowID
        self.fileManager = fileManager
        self.stateSink = stateSink
        self.rootURL = workspaceURL
        self.currentDirectoryURL = workspaceURL
        self.state = initialState
    }

    public func snapshot() -> FilesSurfaceState {
        state
    }

    public func start() async {
        do {
            try prepareWorkspaceIfNeeded()
            try reloadState(selecting: state.selectedEntryID)
        } catch {
            state.statusMessage = "Workspace error: \(error.localizedDescription)"
            state.previewText = "The in-app workspace could not be prepared."
        }

        await publishState()
    }

    public func refresh() async {
        do {
            try reloadState(selecting: state.selectedEntryID)
        } catch {
            state.statusMessage = "Refresh failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func selectEntry(id: String) async {
        state.selectedEntryID = id
        state.previewText = makePreviewText(for: state.selectedEntry)
        await publishState()
    }

    public func openSelectedEntry() async {
        guard let entry = state.selectedEntry else {
            state.statusMessage = "Select a file or folder first."
            await publishState()
            return
        }

        switch entry.kind {
        case .directory:
            currentDirectoryURL = currentDirectoryURL.appendingPathComponent(entry.name, isDirectory: true)
            do {
                try reloadState(selecting: nil)
            } catch {
                state.statusMessage = "Open failed: \(error.localizedDescription)"
            }
        case .file:
            state.statusMessage = "Previewing \(entry.name)"
            state.previewText = makePreviewText(for: entry)
        }

        await publishState()
    }

    public func navigateUp() async {
        guard currentDirectoryURL.standardizedFileURL != rootURL.standardizedFileURL else {
            state.statusMessage = "Already at workspace root."
            await publishState()
            return
        }

        currentDirectoryURL.deleteLastPathComponent()
        do {
            try reloadState(selecting: nil)
        } catch {
            state.statusMessage = "Navigate up failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func createFolder(named proposedName: String) async {
        let name = sanitizeEntryName(proposedName)
        guard !name.isEmpty else {
            state.statusMessage = "Folder name cannot be empty."
            await publishState()
            return
        }

        let targetURL = currentDirectoryURL.appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            state.statusMessage = "A folder named \(name) already exists."
            await publishState()
            return
        }

        do {
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false, attributes: nil)
            try reloadState(selecting: relativePath(for: targetURL))
            state.statusMessage = "Created folder \(name)."
        } catch {
            state.statusMessage = "Create folder failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func renameSelectedEntry(to proposedName: String) async {
        guard let entry = state.selectedEntry else {
            state.statusMessage = "Select a file or folder first."
            await publishState()
            return
        }

        let name = sanitizeEntryName(proposedName)
        guard !name.isEmpty else {
            state.statusMessage = "New name cannot be empty."
            await publishState()
            return
        }

        guard name != entry.name else {
            state.statusMessage = "Rename skipped: name is unchanged."
            await publishState()
            return
        }

        let sourceURL = url(for: entry)
        let destinationURL = currentDirectoryURL.appendingPathComponent(name, isDirectory: entry.kind == .directory)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            state.statusMessage = "An item named \(name) already exists."
            await publishState()
            return
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            try reloadState(selecting: relativePath(for: destinationURL))
            state.statusMessage = "Renamed \(entry.name) to \(name)."
        } catch {
            state.statusMessage = "Rename failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func deleteSelectedEntry() async {
        guard let entry = state.selectedEntry else {
            state.statusMessage = "Select a file or folder first."
            await publishState()
            return
        }

        do {
            try fileManager.removeItem(at: url(for: entry))
            try reloadState(selecting: nil)
            state.statusMessage = "Deleted \(entry.name)."
        } catch {
            state.statusMessage = "Delete failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func importItems(from urls: [URL]) async {
        guard !urls.isEmpty else {
            state.statusMessage = "Import skipped: no files selected."
            await publishState()
            return
        }

        var importedCount = 0

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let targetURL = uniqueDestinationURL(forProposedName: url.lastPathComponent, isDirectory: isDirectory(at: url))
                try copyItem(at: url, to: targetURL)
                importedCount += 1
            } catch {
                state.statusMessage = "Import failed for \(url.lastPathComponent): \(error.localizedDescription)"
                await publishState()
                return
            }
        }

        do {
            try reloadState(selecting: state.selectedEntryID)
            state.statusMessage = "Imported \(importedCount) item(s)."
        } catch {
            state.statusMessage = "Import refresh failed: \(error.localizedDescription)"
        }

        await publishState()
    }

    public func exportSelectedEntryURL() async -> URL? {
        guard let entry = state.selectedEntry else {
            state.statusMessage = "Select a file or folder first."
            await publishState()
            return nil
        }

        let exportedURL = url(for: entry)
        state.statusMessage = "Preparing export for \(entry.name)."
        await publishState()
        return exportedURL
    }

    private func prepareWorkspaceIfNeeded() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)

        let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil)
        if enumerator?.nextObject() != nil {
            return
        }

        let directories = ["Projects", "Downloads", "Notes"]
        for directory in directories {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let welcomeURL = rootURL.appendingPathComponent("Welcome.txt")
        let welcomeText = """
        AdminConsole Workspace

        This file browser is fully inside the app sandbox.
        Use the iPhone control scene to select entries, open folders, and keep both scenes in sync.
        """
        try welcomeText.write(to: welcomeURL, atomically: true, encoding: .utf8)

        let notesURL = rootURL.appendingPathComponent("Notes", isDirectory: true).appendingPathComponent("todo.txt")
        let todoText = """
        - Bring Files MVP online
        - Add VNC runtime
        - Polish browser windows
        """
        try todoText.write(to: notesURL, atomically: true, encoding: .utf8)
    }

    private func reloadState(selecting selectedEntryID: String?) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: currentDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let entries = try urls.map(makeEntry(for:)).sorted(by: Self.entrySortComparator)
        let selection = entries.contains(where: { $0.id == selectedEntryID }) ? selectedEntryID : entries.first?.id

        state.workspaceName = rootURL.lastPathComponent
        state.currentPath = relativePath(for: currentDirectoryURL)
        state.entries = entries
        state.selectedEntryID = selection
        state.canNavigateUp = currentDirectoryURL.standardizedFileURL != rootURL.standardizedFileURL
        state.statusMessage = entries.isEmpty ? "Folder is empty." : "\(entries.count) items"
        state.previewText = makePreviewText(for: state.selectedEntry)
    }

    private func makeEntry(for url: URL) throws -> FilesEntry {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = values.isDirectory ?? false

        return FilesEntry(
            id: relativePath(for: url),
            name: url.lastPathComponent,
            relativePath: relativePath(for: url),
            kind: isDirectory ? .directory : .file,
            byteSize: isDirectory ? nil : values.fileSize.map(Int64.init)
        )
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path

        guard fullPath.hasPrefix(rootPath) else {
            return fullPath
        }

        let suffix = fullPath.dropFirst(rootPath.count)
        let trimmed = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }

    private func makePreviewText(for entry: FilesEntry?) -> String {
        guard let entry else {
            return "Select a folder or file to inspect it."
        }

        let entryURL = url(for: entry)

        switch entry.kind {
        case .directory:
            let count = ((try? fileManager.contentsOfDirectory(at: entryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).count
            return """
            Directory: \(entry.name)
            Path: \(entry.relativePath)
            Items: \(count)
            """
        case .file:
            if let data = try? Data(contentsOf: entryURL),
               let text = String(data: data.prefix(2_048), encoding: .utf8) {
                let sizeDescription = entry.byteSize.map { "\($0) bytes" } ?? "size unknown"
                return """
                File: \(entry.name)
                Path: \(entry.relativePath)
                Size: \(sizeDescription)

                \(text)
                """
            }

            return """
            File: \(entry.name)
            Path: \(entry.relativePath)
            Binary or unsupported preview.
            """
        }
    }

    private func publishState() async {
        await stateSink(state)
    }

    private func url(for entry: FilesEntry) -> URL {
        if entry.relativePath == "/" {
            return rootURL
        }

        return rootURL.appendingPathComponent(
            String(entry.relativePath.dropFirst()),
            isDirectory: entry.kind == .directory
        )
    }

    private func sanitizeEntryName(_ proposedName: String) -> String {
        proposedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }

    private func uniqueDestinationURL(forProposedName proposedName: String, isDirectory: Bool) -> URL {
        let sanitizedName = sanitizeEntryName(proposedName)
        let fallbackName = sanitizedName.isEmpty ? (isDirectory ? "Imported Folder" : "Imported File") : sanitizedName

        let baseName: String
        let pathExtension: String

        if isDirectory {
            baseName = fallbackName
            pathExtension = ""
        } else {
            let url = URL(fileURLWithPath: fallbackName)
            let ext = url.pathExtension
            pathExtension = ext
            baseName = ext.isEmpty ? fallbackName : url.deletingPathExtension().lastPathComponent
        }

        var candidateIndex = 0
        while true {
            let candidateName: String
            if candidateIndex == 0 {
                candidateName = fallbackName
            } else if pathExtension.isEmpty {
                candidateName = "\(baseName) \(candidateIndex + 1)"
            } else {
                candidateName = "\(baseName) \(candidateIndex + 1).\(pathExtension)"
            }

            let candidateURL = currentDirectoryURL.appendingPathComponent(candidateName, isDirectory: isDirectory)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            candidateIndex += 1
        }
    }

    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        if isDirectory(at: sourceURL) {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func defaultWorkspaceURL(fileManager: FileManager) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("AdminConsoleWorkspace", isDirectory: true)
    }

    private static func entrySortComparator(_ lhs: FilesEntry, _ rhs: FilesEntry) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == .directory
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
