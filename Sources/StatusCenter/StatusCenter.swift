import CoreTypes
import Foundation
import SVNCore

public struct StatusCenterConfiguration: Sendable, Hashable, Codable {
    public var fullRefreshDebounceSeconds: Double
    public var changedPathBatchSize: Int
    public var badgeEntryLimit: Int
    public var maxConcurrentRoots: Int

    public init(
        fullRefreshDebounceSeconds: Double,
        changedPathBatchSize: Int,
        badgeEntryLimit: Int,
        maxConcurrentRoots: Int
    ) {
        self.fullRefreshDebounceSeconds = fullRefreshDebounceSeconds
        self.changedPathBatchSize = changedPathBatchSize
        self.badgeEntryLimit = badgeEntryLimit
        self.maxConcurrentRoots = maxConcurrentRoots
    }

    public static let recommended = StatusCenterConfiguration(
        fullRefreshDebounceSeconds: 0.75,
        changedPathBatchSize: 256,
        badgeEntryLimit: 4096,
        maxConcurrentRoots: 2
    )
}

public actor StatusCenter {
    private let client: SVNClient
    private let configuration: StatusCenterConfiguration
    private var snapshots: [String: BadgeSnapshot]

    public init(
        client: SVNClient,
        configuration: StatusCenterConfiguration = .recommended
    ) {
        self.client = client
        self.configuration = configuration
        self.snapshots = [:]
    }

    @discardableResult
    public func warmStatusIndex(
        for rootPath: String,
        changedPaths: [String] = [],
        context: SVNCommandContext = .background
    ) async throws -> BadgeSnapshot {
        let options = changedPaths.isEmpty || changedPaths.count > configuration.changedPathBatchSize
            ? StatusQueryOptions.badges
            : StatusQueryOptions.commitSheet

        let items = try await client.status(at: rootPath, options: options, context: context)

        var entries: [String: VersionControlStatus] = [:]
        for item in items where item.isDirty {
            let badgeStatus = item.propertyModified && !item.status.isDirty ? VersionControlStatus.modified : item.status
            entries[item.path] = badgeStatus
            if entries.count >= configuration.badgeEntryLimit {
                break
            }
        }

        let snapshot = BadgeSnapshot(
            rootPath: rootPath,
            generatedAt: Date(),
            entries: entries
        )
        snapshots[rootPath] = snapshot
        return snapshot
    }

    public func snapshot(for rootPath: String) -> BadgeSnapshot? {
        snapshots[rootPath]
    }

    public func remember(snapshot: BadgeSnapshot) {
        snapshots[snapshot.rootPath] = snapshot
    }

    public func evict(rootPath: String) {
        snapshots.removeValue(forKey: rootPath)
    }
}

public extension StatusCenter {
    static func rustPhaseOne(
        repositoryRoot: String,
        statusConfiguration: StatusCenterConfiguration = .recommended,
        clientConfiguration: SVNClientConfiguration = .recommended,
        bridgeConfiguration: RustBridgeConfiguration? = nil
    ) -> StatusCenter {
        let resolvedBridge = bridgeConfiguration ?? .development(repositoryRoot: repositoryRoot)
        let client = RustCommandBridgeSVNClient(
            configuration: clientConfiguration,
            bridgeConfiguration: resolvedBridge
        )
        return StatusCenter(client: client, configuration: statusConfiguration)
    }
}
