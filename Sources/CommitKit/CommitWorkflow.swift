import CoreTypes
import Foundation
import SVNCore

public enum CommitSelectionStrategy: String, Sendable, Hashable, Codable {
    case modifiedOnly
    case explicitPathsOnly
    case includeParentFoldersForContext
}

public struct CommitPlan: Sendable, Hashable, Codable {
    public var includedPaths: [String]
    public var excludedPaths: [String]
    public var warnings: [String]

    public var canCommit: Bool {
        !includedPaths.isEmpty
    }

    public init(includedPaths: [String], excludedPaths: [String], warnings: [String]) {
        self.includedPaths = includedPaths
        self.excludedPaths = excludedPaths
        self.warnings = warnings
    }
}

public struct AddPreviewPlan: Sendable, Hashable, Codable {
    public var addablePaths: [String]
    public var skippedPaths: [String]
    public var requiresConfirmationForDirectories: [String]

    public init(
        addablePaths: [String],
        skippedPaths: [String],
        requiresConfirmationForDirectories: [String]
    ) {
        self.addablePaths = addablePaths
        self.skippedPaths = skippedPaths
        self.requiresConfirmationForDirectories = requiresConfirmationForDirectories
    }
}

public struct ShelveRequest: Sendable, Hashable, Codable {
    public var name: String
    public var paths: [String]

    public init(name: String, paths: [String]) {
        self.name = name
        self.paths = paths
    }
}

public actor CommitPlanner {
    public init() {
    }

    public func plan(
        from items: [WorkingCopyItem],
        explicitSelection: Set<String>,
        strategy: CommitSelectionStrategy = .modifiedOnly
    ) -> CommitPlan {
        let dirtyPaths = Set(items.filter(\.isDirty).map(\.path))
        let normalPaths = Set(items.filter { !$0.isDirty }.map(\.path))

        let includedSet: Set<String>
        switch strategy {
        case .modifiedOnly:
            if explicitSelection.isEmpty {
                includedSet = dirtyPaths
            } else {
                includedSet = dirtyPaths.intersection(explicitSelection)
            }
        case .explicitPathsOnly:
            includedSet = explicitSelection
        case .includeParentFoldersForContext:
            includedSet = dirtyPaths.union(explicitSelection)
        }

        var warnings: [String] = []
        if includedSet.isEmpty {
            warnings.append("No changed paths are currently selected.")
        }
        if !explicitSelection.intersection(normalPaths).isEmpty {
            warnings.append("Unchanged paths were dropped from the commit plan.")
        }

        let includedPaths = Array(includedSet).sorted()
        let excludedPaths = Array(Set(items.map(\.path)).subtracting(includedSet)).sorted()

        return CommitPlan(
            includedPaths: includedPaths,
            excludedPaths: excludedPaths,
            warnings: warnings
        )
    }

    public func previewAdd(for candidates: [WorkingCopyItem]) -> AddPreviewPlan {
        let unversioned = candidates.filter { $0.status == .unversioned }
        let addablePaths = unversioned.map(\.path).sorted()
        let skippedPaths = candidates.filter { $0.status != .unversioned }.map(\.path).sorted()
        let directories = unversioned.filter(\.isDirectory).map(\.path).sorted()

        return AddPreviewPlan(
            addablePaths: addablePaths,
            skippedPaths: skippedPaths,
            requiresConfirmationForDirectories: directories
        )
    }
}

public actor ShelveCoordinator {
    private let client: SVNClient

    public init(client: SVNClient) {
        self.client = client
    }

    public func shelve(
        _ request: ShelveRequest,
        context: SVNCommandContext = .foreground
    ) async throws {
        try await client.shelve(paths: request.paths, name: request.name, context: context)
    }

    public func unshelve(
        named name: String,
        context: SVNCommandContext = .foreground
    ) async throws {
        try await client.unshelve(name: name, context: context)
    }
}
