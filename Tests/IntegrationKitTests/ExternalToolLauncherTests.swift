@testable import IntegrationKit
import XCTest

actor RecordingExternalToolRunner: ExternalToolCommandRunning {
    private var results: [ExternalToolInvocationResult]
    private var recordedRequests: [ExternalToolInvocationRequest] = []

    init(results: [ExternalToolInvocationResult]) {
        self.results = results
    }

    func run(_ request: ExternalToolInvocationRequest) async throws -> ExternalToolInvocationResult {
        recordedRequests.append(request)
        guard !results.isEmpty else {
            return ExternalToolInvocationResult(exitCode: 1, stderr: "no mocked result")
        }
        return results.removeFirst()
    }

    func requests() -> [ExternalToolInvocationRequest] {
        recordedRequests
    }
}

final class ExternalToolLauncherTests: XCTestCase {
    func testInvocationRequestReplacesPlaceholders() async throws {
        let runner = RecordingExternalToolRunner(results: [])
        let launcher = ExternalToolLauncher(runner: runner)
        let profile = ExternalToolProfile(
            kind: .beyondCompare,
            displayName: "Beyond Compare",
            launchPath: "/usr/bin/open",
            arguments: ["-a", "Beyond Compare", "$LEFT", "$RIGHT"],
            supportsDirectoryDiff: true
        )

        let request = try await launcher.invocationRequest(
            profile: profile,
            leftPath: "/tmp/base.txt",
            rightPath: "/tmp/working.txt"
        )

        XCTAssertEqual(request.launchPath, "/usr/bin/open")
        XCTAssertEqual(
            request.arguments,
            ["-a", "Beyond Compare", "/tmp/base.txt", "/tmp/working.txt"]
        )
    }

    func testLaunchThrowsWhenDirectoryDiffIsUnsupported() async throws {
        let runner = RecordingExternalToolRunner(results: [])
        let launcher = ExternalToolLauncher(runner: runner)
        let profile = ExternalToolProfile(
            kind: .bbedit,
            displayName: "BBEdit",
            launchPath: "/usr/bin/open",
            arguments: ["-a", "BBEdit", "$LEFT", "$RIGHT"],
            supportsDirectoryDiff: false
        )

        do {
            try await launcher.launch(
                profile: profile,
                leftPath: "/tmp/base",
                rightPath: "/tmp/working",
                isDirectory: true
            )
            XCTFail("Expected directory diff launch to throw.")
        } catch let error as ExternalToolLauncherError {
            XCTAssertEqual(error, .directoryDiffUnsupported("BBEdit"))
        }
    }

    func testLaunchRunsProfileCommand() async throws {
        let runner = RecordingExternalToolRunner(
            results: [
                ExternalToolInvocationResult(exitCode: 0, stderr: ""),
            ]
        )
        let launcher = ExternalToolLauncher(runner: runner)
        let profile = ExternalToolProfile(
            kind: .systemDefault,
            displayName: "System Default",
            launchPath: "/usr/bin/open",
            arguments: ["$LEFT"],
            supportsDirectoryDiff: false
        )

        try await launcher.launch(
            profile: profile,
            leftPath: "/tmp/file.txt"
        )
        let requests = await runner.requests()

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].launchPath, "/usr/bin/open")
        XCTAssertEqual(requests[0].arguments, ["/tmp/file.txt"])
    }
}
