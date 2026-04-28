@testable import SVNCore
import XCTest

final class SubversionDiffInspectorTests: XCTestCase {
    func testWorkingCopyDiffReturnsRawDiffTextUsingProvidedWorkingCopyRoot() async throws {
        let diff = """
        Index: README.md
        ===================================================================
        --- README.md    (revision 12)
        +++ README.md    (working copy)
        @@ -1 +1 @@
        -old
        +new
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: diff, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionDiffInspector(runner: runner)

        let preview = try await inspector.workingCopyDiff(
            at: "/repo/project/README.md",
            workingCopyRoot: "/repo/project",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(preview.targetPath, "/repo/project/README.md")
        XCTAssertEqual(preview.rawText, diff)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["diff", "/repo/project/README.md"])
        XCTAssertEqual(requests[0].workingDirectory, "/repo/project")
    }

    func testWorkingCopyDiffFallsBackToParentDirectoryWhenRootIsNotProvided() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionDiffInspector(runner: runner)

        let preview = try await inspector.workingCopyDiff(
            at: "/repo/project/Docs/Guide.md",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertTrue(preview.isEmpty)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].workingDirectory, "/repo/project/Docs")
    }

    func testWorkingCopyDiffThrowsCommandFailureForSVNError() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(
                    stdout: "",
                    stderr: "svn: E155010: The node was not found.",
                    exitCode: 1
                ),
            ]
        )
        let inspector = SubversionDiffInspector(runner: runner)

        do {
            _ = try await inspector.workingCopyDiff(
                at: "/repo/project/README.md",
                workingCopyRoot: "/repo/project",
                context: .foreground
            )
            XCTFail("Expected workingCopyDiff to throw.")
        } catch let error as SubversionDiffInspectorError {
            XCTAssertEqual(
                error,
                .commandFailed(
                    arguments: ["diff", "/repo/project/README.md"],
                    exitCode: 1,
                    stderr: "svn: E155010: The node was not found."
                )
            )
        }
    }

    func testRevisionDiffUsesChangeRevisionInvocation() async throws {
        let diff = """
        Index: README.md
        ===================================================================
        --- README.md    (revision 12)
        +++ README.md    (revision 13)
        @@ -1 +1 @@
        -before
        +after
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: diff, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionDiffInspector(runner: runner)

        let preview = try await inspector.revisionDiff(
            at: "/repo/project",
            revision: 13,
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(preview.targetPath, "r13")
        XCTAssertEqual(preview.rawText, diff)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["diff", "-c", "13", "/repo/project"])
        XCTAssertEqual(requests[0].workingDirectory, "/repo/project")
    }
}
