@testable import SVNCore
import XCTest

actor RecordingSubversionRunner: SubversionCommandRunning {
    private var results: [SubversionCLIInvocationResult]
    private var recordedRequests: [SubversionCLIInvocationRequest] = []

    init(results: [SubversionCLIInvocationResult]) {
        self.results = results
    }

    func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
        recordedRequests.append(request)
        guard !results.isEmpty else {
            return SubversionCLIInvocationResult(stdout: "", stderr: "no mocked result", exitCode: 1)
        }

        return results.removeFirst()
    }

    func requests() -> [SubversionCLIInvocationRequest] {
        recordedRequests
    }
}

final class SubversionRepositoryInspectorTests: XCTestCase {
    func testSummaryParsesRepositoryMetadataFromInfoXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <info>
          <entry
             kind="dir"
             path="."
             revision="128">
            <url>https://svn.example.com/repos/project/trunk</url>
            <repository>
              <root>https://svn.example.com/repos/project</root>
              <uuid>1234-5678</uuid>
            </repository>
            <wc-info>
              <wcroot-abspath>/repo/project</wcroot-abspath>
            </wc-info>
            <commit revision="127">
              <author>alice</author>
              <date>2026-04-22T10:15:30.000000Z</date>
            </commit>
          </entry>
        </info>
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: xml, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let summary = try await inspector.summary(at: "/repo/project", context: .foreground)
        let requests = await runner.requests()

        XCTAssertEqual(summary.workingCopyRoot, "/repo/project")
        XCTAssertEqual(summary.repositoryURL, "https://svn.example.com/repos/project/trunk")
        XCTAssertEqual(summary.repositoryRootURL, "https://svn.example.com/repos/project")
        XCTAssertEqual(summary.revision, 128)
        XCTAssertEqual(summary.lastChangedRevision, 127)
        XCTAssertEqual(summary.lastChangedAuthor, "alice")
        XCTAssertEqual(summary.workingCopyUUID, "1234-5678")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["info", "--xml", "/repo/project"])
    }

    func testRecentHistoryParsesLogEntriesFromXML() async throws {
        let infoXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <info>
          <entry
             kind="dir"
             path="."
             revision="128">
            <url>https://svn.example.com/repos/project/trunk</url>
            <repository>
              <root>https://svn.example.com/repos/project</root>
              <uuid>1234-5678</uuid>
            </repository>
            <wc-info>
              <wcroot-abspath>/repo/project</wcroot-abspath>
            </wc-info>
            <commit revision="127">
              <author>alice</author>
              <date>2026-04-22T10:15:30.000000Z</date>
            </commit>
          </entry>
        </info>
        """
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <log>
          <logentry revision="128">
            <author>alice</author>
            <date>2026-04-22T10:15:30.000000Z</date>
            <msg>Fix finder menu dispatch</msg>
          </logentry>
          <logentry revision="127">
            <author>bob</author>
            <date>2026-04-21T08:00:00Z</date>
            <msg></msg>
          </logentry>
        </log>
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: infoXML, stderr: "", exitCode: 0),
                SubversionCLIInvocationResult(stdout: xml, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let entries = try await inspector.recentHistory(
            at: "/repo/project",
            limit: 2,
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].revision, 128)
        XCTAssertEqual(entries[0].author, "alice")
        XCTAssertEqual(entries[0].message, "Fix finder menu dispatch")
        XCTAssertEqual(entries[1].revision, 127)
        XCTAssertEqual(entries[1].author, "bob")
        XCTAssertEqual(entries[1].message, "")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].arguments, ["info", "--xml", "/repo/project"])
        XCTAssertEqual(
            requests[1].arguments,
            ["log", "--xml", "-l", "2", "https://svn.example.com/repos/project/trunk"]
        )
        XCTAssertEqual(requests[1].workingDirectory, "/repo/project")
    }

    func testRecentHistoryUsesRepositoryURLDirectlyWhenCallerProvidesURL() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <log>
          <logentry revision="5">
            <author>alice</author>
            <date>2026-04-22T10:15:30.000000Z</date>
            <msg>Repository update</msg>
          </logentry>
        </log>
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: xml, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let entries = try await inspector.recentHistory(
            at: "https://svn.example.com/repos/project/trunk",
            limit: 1,
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].revision, 5)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["log", "--xml", "-l", "1", "https://svn.example.com/repos/project/trunk"]
        )
        XCTAssertNil(requests[0].workingDirectory)
    }

    func testLogDetailParsesChangedPathsFromVerboseXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <log>
          <logentry revision="128">
            <author>alice</author>
            <date>2026-04-22T10:15:30.000000Z</date>
            <paths>
              <path prop-mods="false" text-mods="true" kind="file" action="M">/trunk/README.md</path>
              <path prop-mods="false" text-mods="false" kind="dir" action="A">/branches/release</path>
            </paths>
            <msg>Prepare release</msg>
          </logentry>
        </log>
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: xml, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let detail = try await inspector.logDetail(
            at: "/repo/project",
            revision: 128,
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(detail.entry.revision, 128)
        XCTAssertEqual(detail.entry.author, "alice")
        XCTAssertEqual(detail.entry.message, "Prepare release")
        XCTAssertEqual(detail.changedPaths.count, 2)
        XCTAssertEqual(detail.changedPaths[0].path, "/trunk/README.md")
        XCTAssertEqual(detail.changedPaths[0].action, "M")
        XCTAssertEqual(detail.changedPaths[0].kind, "file")
        XCTAssertEqual(detail.changedPaths[0].textModified, true)
        XCTAssertEqual(detail.changedPaths[0].propertyModified, false)
        XCTAssertEqual(detail.changedPaths[1].path, "/branches/release")
        XCTAssertEqual(detail.changedPaths[1].action, "A")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["log", "--xml", "-v", "-r", "128", "/repo/project"])
    }

    func testBrowseParsesRepositoryListingFromXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <lists>
          <list path="https://svn.example.com/repos/project/trunk">
            <entry kind="dir">
              <name>docs</name>
              <commit revision="120">
                <author>alice</author>
                <date>2026-04-20T10:15:30.000000Z</date>
              </commit>
            </entry>
            <entry kind="file">
              <name>README.md</name>
              <size>128</size>
              <commit revision="128">
                <author>bob</author>
                <date>2026-04-22T10:15:30.000000Z</date>
              </commit>
            </entry>
          </list>
        </lists>
        """
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: xml, stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let listing = try await inspector.browse(
            url: "https://svn.example.com/repos/project/trunk",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(listing.baseURL, "https://svn.example.com/repos/project/trunk")
        XCTAssertEqual(listing.entries.count, 2)
        XCTAssertTrue(listing.entries[0].isDirectory)
        XCTAssertEqual(listing.entries[0].name, "docs")
        XCTAssertEqual(listing.entries[0].fullURL, "https://svn.example.com/repos/project/trunk/docs/")
        XCTAssertFalse(listing.entries[1].isDirectory)
        XCTAssertEqual(listing.entries[1].name, "README.md")
        XCTAssertEqual(listing.entries[1].size, 128)
        XCTAssertEqual(listing.entries[1].author, "bob")
        XCTAssertEqual(listing.entries[1].fullURL, "https://svn.example.com/repos/project/trunk/README.md")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["list", "--xml", "https://svn.example.com/repos/project/trunk"])
    }

    func testFileContentsUsesCatForRepositoryURL() async throws {
        let content = "# Readme\nhello\n"
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(
                    stdout: content,
                    stderr: "",
                    exitCode: 0,
                    stdoutData: Data(content.utf8)
                ),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let preview = try await inspector.fileContents(
            url: "https://svn.example.com/repos/project/trunk/README.md",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(preview.sourceIdentifier, "https://svn.example.com/repos/project/trunk/README.md")
        XCTAssertEqual(preview.text, content)
        XCTAssertFalse(preview.isBinary)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["cat", "https://svn.example.com/repos/project/trunk/README.md"]
        )
    }

    func testWorkingCopyBaseContentsUsesBaseRevision() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "base\n", stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let preview = try await inspector.workingCopyBaseContents(
            at: "/repo/project/README.md",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(preview.text, "base\n")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].arguments, ["cat", "-r", "BASE", "/repo/project/README.md"])
        XCTAssertEqual(requests[0].workingDirectory, "/repo/project")
    }

    func testExportWorkingCopyBaseUsesForceExportCommand() async throws {
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(stdout: "", stderr: "", exitCode: 0),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        try await inspector.exportWorkingCopyBase(
            at: "/repo/project/Docs",
            to: "/tmp/export/Docs",
            context: .foreground
        )
        let requests = await runner.requests()

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].arguments,
            ["export", "-r", "BASE", "/repo/project/Docs", "/tmp/export/Docs", "--force"]
        )
        XCTAssertEqual(requests[0].workingDirectory, "/repo/project")
    }

    func testFileContentsMarksBinaryDataAsBinary() async throws {
        let binaryData = Data([0x00, 0x01, 0x02, 0x03])
        let runner = RecordingSubversionRunner(
            results: [
                SubversionCLIInvocationResult(
                    stdout: String(decoding: binaryData, as: UTF8.self),
                    stderr: "",
                    exitCode: 0,
                    stdoutData: binaryData
                ),
            ]
        )
        let inspector = SubversionRepositoryInspector(runner: runner)

        let preview = try await inspector.fileContents(
            url: "https://svn.example.com/repos/project/trunk/logo.bin",
            context: .foreground
        )

        XCTAssertTrue(preview.isBinary)
        XCTAssertNil(preview.text)
        XCTAssertEqual(preview.byteCount, 4)
    }
}
