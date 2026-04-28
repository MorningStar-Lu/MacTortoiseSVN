@testable import SVNCore
import CoreTypes
import StatusCenter
import XCTest

actor RecordingRunner: RustBridgeCommandRunning {
    private var results: [RustBridgeInvocationResult]
    private var recordedRequests: [RustBridgeInvocationRequest] = []

    init(results: [RustBridgeInvocationResult]) {
        self.results = results
    }

    func run(_ request: RustBridgeInvocationRequest) async throws -> RustBridgeInvocationResult {
        recordedRequests.append(request)
        guard !results.isEmpty else {
            return RustBridgeInvocationResult(stdout: "", stderr: "no mocked result", exitCode: 1)
        }

        return results.removeFirst()
    }

    func requests() -> [RustBridgeInvocationRequest] {
        recordedRequests
    }
}

final class RustCommandBridgeSVNClientTests: XCTestCase {
    func testExtendedExecutablePathPrependsPreferredToolLocationsWithoutDuplicates() {
        let path = macSVNExtendedExecutablePath(
            currentPath: "/usr/bin:/custom/bin:/opt/homebrew/bin"
        )

        XCTAssertEqual(
            path,
            "/opt/homebrew/bin:/usr/local/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/custom/bin"
        )
    }

    func testBadgeStatusUsesSnapshotBridgeAndStatusCenterStoresSnapshot() async throws {
        let json = """
        {"kind":"snapshot","root":"/repo","entries":[{"path":"/repo/README.md","status":"modified","props_modified":false,"is_directory":false},{"path":"/repo/project.xcodeproj","status":"normal","props_modified":true,"is_directory":true}]}
        """
        let runner = RecordingRunner(
            results: [
                RustBridgeInvocationResult(stdout: json, stderr: "", exitCode: 0),
            ]
        )
        let client = RustCommandBridgeSVNClient(
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: "/repo",
                preferBuiltBinary: false
            ),
            runner: runner
        )
        let center = StatusCenter(client: client, configuration: .recommended)

        let snapshot = try await center.warmStatusIndex(for: "/repo")
        let requests = await runner.requests()

        XCTAssertEqual(snapshot.entries["/repo/README.md"], .modified)
        XCTAssertEqual(snapshot.entries["/repo/project.xcodeproj"], .modified)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].arguments.contains("bridge-snapshot"))
    }

    func testCommitSheetStatusUsesRawStatusBridge() async throws {
        let json = """
        {"kind":"status","root":"/repo","entries":[{"path":"/repo/new-file.txt","status":"unversioned","props_modified":false,"is_directory":false}]}
        """
        let runner = RecordingRunner(
            results: [
                RustBridgeInvocationResult(stdout: json, stderr: "", exitCode: 0),
            ]
        )
        let client = RustCommandBridgeSVNClient(
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: "/repo",
                preferBuiltBinary: false
            ),
            runner: runner
        )

        let items = try await client.status(at: "/repo", options: .commitSheet, context: .foreground)
        let requests = await runner.requests()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].status, .unversioned)
        XCTAssertTrue(requests[0].arguments.contains("bridge-status"))
    }

    func testAddUsesBridgeAddCommand() async throws {
        let json = """
        {"kind":"add","path_count":1}
        """
        let runner = RecordingRunner(
            results: [
                RustBridgeInvocationResult(stdout: json, stderr: "", exitCode: 0),
            ]
        )
        let client = RustCommandBridgeSVNClient(
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: "/repo",
                preferBuiltBinary: false
            ),
            runner: runner
        )

        try await client.add(
            paths: ["/repo/new-file.txt"],
            depth: .files,
            force: false,
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].arguments.contains("bridge-add"))
        XCTAssertTrue(requests[0].arguments.contains("--path"))
        XCTAssertTrue(requests[0].arguments.contains("--depth"))
        XCTAssertTrue(requests[0].arguments.contains("files"))
    }

    func testCommitUsesBridgeCommitCommandAndReturnsRevision() async throws {
        let json = """
        {"kind":"commit","revision":42}
        """
        let runner = RecordingRunner(
            results: [
                RustBridgeInvocationResult(stdout: json, stderr: "", exitCode: 0),
            ]
        )
        let client = RustCommandBridgeSVNClient(
            bridgeConfiguration: RustBridgeConfiguration(
                repositoryRoot: "/repo",
                preferBuiltBinary: false
            ),
            runner: runner
        )

        let revision = try await client.commit(
            candidates: [
                CommitCandidate(path: "/repo/new-file.txt", status: .added, isExplicitlySelected: true),
            ],
            message: "Add new file",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(revision, 42)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].arguments.contains("bridge-commit"))
        XCTAssertTrue(requests[0].arguments.contains("--message"))
        XCTAssertTrue(requests[0].arguments.contains("Add new file"))
    }
}
