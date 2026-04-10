@testable import FilesFeature
import DesktopDomain
import Foundation
import XCTest

final class FilesWorkspaceRuntimeTests: XCTestCase {
    func testStartLoadsWorkspaceAndPrefersDirectories() async throws {
        let rootURL = try makeTemporaryWorkspace()
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Folder", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try "hello".write(
            to: rootURL.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = FilesWorkspaceRuntime(windowID: WindowID(), rootURL: rootURL) { _ in }
        await runtime.start()
        let snapshot = await runtime.snapshot()

        XCTAssertEqual(snapshot.currentPath, "/")
        XCTAssertEqual(snapshot.entries.first?.kind, .directory)
        XCTAssertEqual(snapshot.entries.first?.name, "Folder")
        XCTAssertEqual(snapshot.entries.dropFirst().first?.name, "note.txt")
    }

    func testNavigationIntoDirectoryAndPreviewingFile() async throws {
        let rootURL = try makeTemporaryWorkspace()
        let folderURL = rootURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try "inside".write(
            to: folderURL.appendingPathComponent("readme.txt"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = FilesWorkspaceRuntime(windowID: WindowID(), rootURL: rootURL) { _ in }
        await runtime.start()
        await runtime.selectEntry(id: "/Folder")
        await runtime.openSelectedEntry()

        let folderSnapshot = await runtime.snapshot()
        XCTAssertEqual(folderSnapshot.currentPath, "/Folder")
        XCTAssertTrue(folderSnapshot.canNavigateUp)
        XCTAssertEqual(folderSnapshot.selectedEntry?.name, "readme.txt")

        if let selectedID = folderSnapshot.selectedEntryID {
            await runtime.selectEntry(id: selectedID)
        }
        await runtime.openSelectedEntry()

        let fileSnapshot = await runtime.snapshot()
        XCTAssertTrue(fileSnapshot.previewText.contains("inside"))

        await runtime.navigateUp()
        let rootSnapshot = await runtime.snapshot()
        XCTAssertEqual(rootSnapshot.currentPath, "/")
    }

    func testCreateRenameAndDeleteEntry() async throws {
        let rootURL = try makeTemporaryWorkspace()
        let runtime = FilesWorkspaceRuntime(windowID: WindowID(), rootURL: rootURL) { _ in }

        await runtime.start()
        await runtime.createFolder(named: "Drafts")

        var snapshot = await runtime.snapshot()
        XCTAssertTrue(snapshot.entries.contains(where: { $0.name == "Drafts" && $0.kind == .directory }))
        XCTAssertEqual(snapshot.selectedEntry?.name, "Drafts")

        await runtime.renameSelectedEntry(to: "Archive")
        snapshot = await runtime.snapshot()
        XCTAssertTrue(snapshot.entries.contains(where: { $0.name == "Archive" && $0.kind == .directory }))
        XCTAssertFalse(snapshot.entries.contains(where: { $0.name == "Drafts" }))
        XCTAssertEqual(snapshot.selectedEntry?.name, "Archive")

        await runtime.deleteSelectedEntry()
        snapshot = await runtime.snapshot()
        XCTAssertFalse(snapshot.entries.contains(where: { $0.name == "Archive" }))
    }

    func testImportAndExportSelectedEntry() async throws {
        let rootURL = try makeTemporaryWorkspace()
        let importURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "imported text".write(to: importURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: importURL)
        }

        let runtime = FilesWorkspaceRuntime(windowID: WindowID(), rootURL: rootURL) { _ in }
        await runtime.start()
        await runtime.importItems(from: [importURL])

        var snapshot = await runtime.snapshot()
        XCTAssertTrue(snapshot.entries.contains(where: { $0.name == importURL.lastPathComponent }))

        await runtime.selectEntry(id: "/\(importURL.lastPathComponent)")
        let exportURL = await runtime.exportSelectedEntryURL()
        snapshot = await runtime.snapshot()

        XCTAssertEqual(exportURL?.lastPathComponent, importURL.lastPathComponent)
        XCTAssertEqual(snapshot.selectedEntry?.name, importURL.lastPathComponent)
    }

    private func makeTemporaryWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
