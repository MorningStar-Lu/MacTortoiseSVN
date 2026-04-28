import CoreTypes
import StatusCenter
import SVNCore
import XCTest

private actor MockSVNClient: SVNClient {
    let items: [WorkingCopyItem]

    init(items: [WorkingCopyItem]) {
        self.items = items
    }

    func status(
        at rootPath: String,
        options: StatusQueryOptions,
        context: SVNCommandContext
    ) async throws -> [WorkingCopyItem] {
        items
    }

    func commit(
        candidates: [CommitCandidate],
        message: String,
        context: SVNCommandContext
    ) async throws -> Int64 {
        1
    }

    func add(
        paths: [String],
        depth: SVNDepth,
        force: Bool,
        context: SVNCommandContext
    ) async throws {
    }

    func shelve(
        paths: [String],
        name: String,
        context: SVNCommandContext
    ) async throws {
    }

    func unshelve(
        name: String,
        context: SVNCommandContext
    ) async throws {
    }
}

final class StatusCenterTests: XCTestCase {
    func testWarmStatusIndexKeepsOnlyDirtyEntries() async throws {
        let client = MockSVNClient(
            items: [
                WorkingCopyItem(path: "/repo/README.md", isDirectory: false, status: .modified),
                WorkingCopyItem(path: "/repo/Docs", isDirectory: true, status: .normal),
                WorkingCopyItem(path: "/repo/ignored.tmp", isDirectory: false, status: .ignored),
            ]
        )

        let center = StatusCenter(client: client, configuration: .recommended)
        let snapshot = try await center.warmStatusIndex(for: "/repo")

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries["/repo/README.md"], .modified)
        XCTAssertNil(snapshot.entries["/repo/Docs"])
    }

    func testWarmStatusIndexTreatsPropertyOnlyChangesAsModifiedBadges() async throws {
        let client = MockSVNClient(
            items: [
                WorkingCopyItem(
                    path: "/repo/project.xcodeproj",
                    isDirectory: true,
                    status: .normal,
                    propertyModified: true
                ),
            ]
        )

        let center = StatusCenter(client: client, configuration: .recommended)
        let snapshot = try await center.warmStatusIndex(for: "/repo")

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries["/repo/project.xcodeproj"], .modified)
    }
}
