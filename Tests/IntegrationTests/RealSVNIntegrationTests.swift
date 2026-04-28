import CoreTypes
import Foundation
import StatusService
import SVNCore
import XCTest

final class RealSVNIntegrationTests: XCTestCase {
    func testStatusServiceRefreshesRealWorkingCopy() async throws {
        try requireSVNToolchain()
        let packageRoot = packageRootURL()
        try buildRustBridgeBinary(packageRoot: packageRoot)
        let fixture = try LocalSVNFixture()
        defer { fixture.cleanup() }

        let modifiedFile = fixture.workingCopyURL.appending(path: "README.md")
        let unversionedFile = fixture.workingCopyURL.appending(path: "notes.txt")
        let modifiedPath = modifiedFile.standardizedFileURL.path
        let unversionedPath = unversionedFile.standardizedFileURL.path
        try "hello from integration test\n".appendLine(to: modifiedFile)
        try "new file\n".write(to: unversionedFile, atomically: true, encoding: .utf8)

        let configuration = StatusServiceConfiguration(
            repositoryRoot: fixture.workingCopyURL.path,
            databaseURL: fixture.databaseURL,
            maxIncrementalDirtyPaths: 8,
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: packageRoot.path,
                preferBuiltBinary: true
            )
        )
        let host = try StatusServiceHost(
            configuration: configuration,
            watcher: NoOpWorkingCopyWatcher()
        )

        try await host.markDirty(
            rootPath: fixture.workingCopyURL.path,
            paths: [modifiedPath, unversionedPath]
        )
        let snapshot = try await host.refresh(rootPath: fixture.workingCopyURL.path)
        let cachedSnapshot = try await host.snapshot(for: fixture.workingCopyURL.path)

        XCTAssertEqual(snapshot.entries[modifiedPath], .modified)
        XCTAssertNil(snapshot.entries[unversionedPath])
        XCTAssertEqual(cachedSnapshot?.entries[modifiedPath], .modified)
    }

    func testRustBridgeCanAddAndCommitInRealWorkingCopy() async throws {
        try requireSVNToolchain()
        let packageRoot = packageRootURL()
        try buildRustBridgeBinary(packageRoot: packageRoot)
        let fixture = try LocalSVNFixture()
        defer { fixture.cleanup() }

        let client = RustCommandBridgeSVNClient(
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: packageRoot.path,
                preferBuiltBinary: true
            )
        )

        let newFile = fixture.workingCopyURL.appending(path: "tracked.txt")
        let newFilePath = newFile.standardizedFileURL.path
        try "tracked\n".write(to: newFile, atomically: true, encoding: .utf8)

        let beforeAdd = try await client.status(
            at: fixture.workingCopyURL.path,
            options: .commitSheet,
            context: .foreground
        )
        XCTAssertEqual(status(for: newFilePath, in: beforeAdd), .unversioned)

        try await client.add(
            paths: [newFilePath],
            depth: .files,
            force: false,
            context: .foreground
        )

        let afterAdd = try await client.status(
            at: fixture.workingCopyURL.path,
            options: .commitSheet,
            context: .foreground
        )
        XCTAssertEqual(status(for: newFilePath, in: afterAdd), .added)

        let revision = try await client.commit(
            candidates: [
                CommitCandidate(path: newFilePath, status: .added, isExplicitlySelected: true),
            ],
            message: "Add tracked file",
            context: .foreground
        )
        XCTAssertGreaterThanOrEqual(revision, 2)

        let afterCommit = try await client.status(
            at: fixture.workingCopyURL.path,
            options: .commitSheet,
            context: .foreground
        )
        XCTAssertNil(afterCommit.first(where: { normalizedPath(for: $0.path) == newFilePath && $0.isDirty }))
    }

    func testRepositoryInspectorAndDiffInspectorSupportHistoryPreviewAndBaseExport() async throws {
        try requireSVNToolchain()
        let fixture = try LocalSVNFixture()
        defer { fixture.cleanup() }

        let readmeURL = fixture.workingCopyURL.appending(path: "README.md")
        try "updated line\n".appendLine(to: readmeURL)
        _ = try runTool(
            "svn",
            ["commit", fixture.workingCopyURL.path, "-m", "Update README"]
        )

        let repositoryInspector = SubversionRepositoryInspector()
        let diffInspector = SubversionDiffInspector()

        let history = try await repositoryInspector.recentHistory(
            at: fixture.workingCopyURL.path,
            limit: 2,
            context: .foreground
        )
        guard let latestRevision = history.first?.revision else {
            XCTFail("Expected at least one history entry.")
            return
        }
        XCTAssertEqual(latestRevision, 2)

        let revisionDiff = try await diffInspector.revisionDiff(
            at: fixture.workingCopyURL.path,
            revision: latestRevision,
            context: .foreground
        )
        XCTAssertTrue(revisionDiff.rawText.contains("updated line"))

        let preview = try await repositoryInspector.fileContents(
            url: fixture.repositoryURL.absoluteURL.absoluteString + "/README.md",
            context: .foreground
        )
        XCTAssertEqual(preview.text, "initial\nupdated line\n")

        let exportURL = fixture.rootURL.appending(path: "base-export")
        try await repositoryInspector.exportWorkingCopyBase(
            at: fixture.workingCopyURL.path,
            to: exportURL.path,
            context: .foreground
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.appending(path: "README.md").path))
    }
}

private func status(for path: String, in items: [WorkingCopyItem]) -> VersionControlStatus? {
    items.first(where: { normalizedPath(for: $0.path) == path })?.status
}

private func normalizedPath(for path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

private struct LocalSVNFixture {
    let rootURL: URL
    let repositoryURL: URL
    let workingCopyURL: URL
    let databaseURL: URL

    init() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "MacTortoiseSVN-Integration")
            .appending(path: UUID().uuidString)
        let repositoryURL = baseURL.appending(path: "repo")
        let importURL = baseURL.appending(path: "import")
        let workingCopyURL = baseURL.appending(path: "wc")
        let databaseURL = baseURL.appending(path: "status-cache.sqlite3")

        try FileManager.default.createDirectory(at: importURL, withIntermediateDirectories: true)
        try "initial\n".write(
            to: importURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        try runTool("svnadmin", ["create", repositoryURL.path])
        let repositoryFileURL = repositoryURL.absoluteURL.absoluteString
        try runTool(
            "svn",
            ["import", importURL.path, repositoryFileURL, "-m", "Initial import"]
        )
        try runTool(
            "svn",
            ["checkout", repositoryFileURL, workingCopyURL.path]
        )

        self.rootURL = baseURL
        self.repositoryURL = repositoryURL
        self.workingCopyURL = workingCopyURL
        self.databaseURL = databaseURL
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func requireSVNToolchain() throws {
    guard commandExists("svn"), commandExists("svnadmin") else {
        throw XCTSkip("svn and svnadmin are required for integration tests.")
    }
}

private func commandExists(_ command: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command, "--version", "--quiet"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

private func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func buildRustBridgeBinary(packageRoot: URL) throws {
    try runTool(
        "/opt/homebrew/bin/cargo",
        ["build", "-q", "-p", "mtsvn-rs"],
        currentDirectoryURL: packageRoot.appending(path: "rust")
    )
}

@discardableResult
private func runTool(
    _ executable: String,
    _ arguments: [String],
    currentDirectoryURL: URL? = nil
) throws -> String {
    let process = Process()
    if executable.hasPrefix("/") {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
    }
    process.currentDirectoryURL = currentDirectoryURL

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "RealSVNIntegrationTests",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Command failed: \(executable) \(arguments.joined(separator: " "))\n\(errorOutput)"
            ]
        )
    }

    return output
}

private extension String {
    func appendLine(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(utf8))
    }
}
