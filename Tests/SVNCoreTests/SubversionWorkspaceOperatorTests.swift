@testable import SVNCore
import XCTest

final class SubversionWorkspaceOperatorTests: XCTestCase {
    func testUpdateParsesChangedPathsRevisionAndConflictFlag() async throws {
        let output = """
        Updating '/repo':
        U    /repo/README.md
        C    /repo/Docs/Guide.md
        Updated to revision 42.
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.update(
            rootPath: "/repo",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.rootPath, "/repo")
        XCTAssertEqual(result.updatedPaths, ["/repo/README.md", "/repo/Docs/Guide.md"])
        XCTAssertEqual(result.resultingRevision, 42)
        XCTAssertTrue(result.hasConflicts)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["update", "/repo", "--depth", "infinity", "--accept", "postpone"]
        )
    }

    func testRevertParsesRevertedPaths() async throws {
        let output = """
        Reverted '/repo/README.md'
        Reverted '/repo/Docs/Guide.md'
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.revert(
            paths: ["/repo/Docs/Guide.md", "/repo/README.md"],
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.requestedPaths, ["/repo/Docs/Guide.md", "/repo/README.md"])
        XCTAssertEqual(result.revertedPaths, ["/repo/README.md", "/repo/Docs/Guide.md"])
        XCTAssertFalse(result.removeAdded)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["revert", "/repo/Docs/Guide.md", "/repo/README.md", "--depth", "infinity"]
        )
    }

    func testCleanupUsesCleanupCommand() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.cleanup(
            rootPath: "/repo",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.rootPath, "/repo")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["cleanup", "/repo"])
    }

    func testResolveParsesResolvedPathsAndAcceptStrategy() async throws {
        let output = """
        Merge conflicts in '/repo/README.md' marked as resolved.
        Tree conflicts in '/repo/Docs' marked as resolved.
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: output, stderr: "", exitCode: 0),
            ]
        )
        let workspaceOperator = SubversionWorkspaceOperator(runner: runner)

        let result = try await workspaceOperator.resolve(
            paths: ["/repo/Docs", "/repo/README.md"],
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(result.requestedPaths, ["/repo/Docs", "/repo/README.md"])
        XCTAssertEqual(result.resolvedPaths, ["/repo/README.md", "/repo/Docs"])
        XCTAssertEqual(result.acceptStrategy, "working")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["resolve", "/repo/Docs", "/repo/README.md", "--accept", "working", "--depth", "infinity"]
        )
    }
}
