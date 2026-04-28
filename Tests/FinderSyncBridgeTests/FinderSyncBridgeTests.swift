import CoreTypes
import FinderSyncBridge
import Foundation
import XCTest

final class FinderSyncBridgeTests: XCTestCase {
    func testBadgeResolverReturnsDirectBadgeForDirtyFile() {
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                "/repo/README.md": .modified,
            ]
        )

        let assignments = FinderBadgeResolver().assignments(
            for: ["/repo/README.md"],
            snapshot: snapshot
        )

        XCTAssertEqual(assignments, [
            FinderBadgeAssignment(path: "/repo/README.md", kind: .modified),
        ])
    }

    func testBadgeResolverPropagatesDirtyDescendantToVisibleDirectory() {
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                "/repo/Sources/App/main.swift": .modified,
            ]
        )

        let assignments = FinderBadgeResolver().assignments(
            for: ["/repo/Sources", "/repo/Docs"],
            snapshot: snapshot
        )

        XCTAssertEqual(assignments, [
            FinderBadgeAssignment(path: "/repo/Sources", kind: .descendantDirty),
        ])
    }

    func testContextMenuBuilderIncludesCommitAndDiffForDirtySelection() {
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                "/repo/README.md": .modified,
            ]
        )

        let actions = FinderContextMenuBuilder().actions(
            for: ["/repo/README.md"],
            snapshot: snapshot
        )

        XCTAssertEqual(actions.map(\.command), [
            .commitSelected,
            .diffSelected,
            .refreshNow,
            .openInWorkbench,
        ])
    }

    func testContextMenuBuilderShowsDisabledCommitAndDiffForCleanSelection() {
        let actions = FinderContextMenuBuilder().actions(
            for: ["/repo/Clean.txt"],
            snapshot: nil
        )

        XCTAssertEqual(actions.map(\.command), [
            .commitSelected,
            .diffSelected,
            .refreshNow,
            .openInWorkbench,
        ])
        XCTAssertEqual(actions.map(\.isEnabled), [
            false,
            false,
            true,
            true,
        ])
    }

    func testContextMenuBuilderEnablesCommitForDirtyDescendantInsideSelectedFolder() {
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                "/repo/Sources/App/main.swift": .modified,
            ]
        )

        let actions = FinderContextMenuBuilder().actions(
            for: ["/repo/Sources"],
            snapshot: snapshot
        )

        XCTAssertEqual(actions.map(\.isEnabled), [
            true,
            true,
            true,
            true,
        ])
    }

    func testContextMenuBuilderCanLocalizeChineseTitles() {
        let snapshot = BadgeSnapshot(
            rootPath: "/repo",
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                "/repo/README.md": .modified,
            ]
        )

        let actions = FinderContextMenuBuilder().actions(
            for: ["/repo/README.md"],
            snapshot: snapshot,
            language: .simplifiedChinese
        )

        XCTAssertEqual(actions.map(\.title), [
            "提交所选...",
            "比较所选",
            "刷新缓存状态",
            "在 MacSVN 工作台中打开",
        ])
    }

    func testWorkbenchCommandNormalizesRootAndSelectedPaths() {
        let command = MacSVNWorkbenchCommand(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            issuedAt: Date(timeIntervalSince1970: 123),
            command: .commitSelected,
            rootPath: "/repo/../repo/project",
            selectedPaths: [
                "/repo/project/src/../src/main.swift",
                "/repo/project/src/main.swift",
            ]
        )

        XCTAssertEqual(command.rootPath, "/repo/project")
        XCTAssertEqual(command.selectedPaths, [
            "/repo/project/src/main.swift",
        ])
    }
}
