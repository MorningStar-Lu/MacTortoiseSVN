import CoreTypes
import Foundation
import StatusCenter
import SVNCore

public struct WorkingCopyFileSystemEvent: Sendable, Hashable, Codable {
    public enum Scope: String, Sendable, Hashable, Codable {
        case incremental
        case fullRefresh
    }

    public var rootPath: String
    public var changedPaths: [String]
    public var scope: Scope

    public init(rootPath: String, changedPaths: [String], scope: Scope) {
        self.rootPath = rootPath
        self.changedPaths = changedPaths
        self.scope = scope
    }

    public static func incremental(rootPath: String, changedPaths: [String]) -> WorkingCopyFileSystemEvent {
        WorkingCopyFileSystemEvent(rootPath: rootPath, changedPaths: changedPaths, scope: .incremental)
    }

    public static func fullRefresh(rootPath: String) -> WorkingCopyFileSystemEvent {
        WorkingCopyFileSystemEvent(rootPath: rootPath, changedPaths: [], scope: .fullRefresh)
    }
}

public protocol WorkingCopyEventHandling: Sendable {
    func handle(event: WorkingCopyFileSystemEvent) async
}

public protocol WorkingCopyEventWatching: Sendable {
    func setEventHandler(_ handler: (any WorkingCopyEventHandling)?) async
    func startMonitoring(rootPath: String) async throws
    func stopMonitoring(rootPath: String) async throws
}

public struct NoOpWorkingCopyWatcher: WorkingCopyEventWatching {
    public init() {
    }

    public func setEventHandler(_ handler: (any WorkingCopyEventHandling)?) async {
    }

    public func startMonitoring(rootPath: String) async throws {
    }

    public func stopMonitoring(rootPath: String) async throws {
    }
}

public struct StatusServiceConfiguration: Sendable, Hashable, Codable {
    public var repositoryRoot: String
    public var databaseURL: URL
    public var maxIncrementalDirtyPaths: Int
    public var bridgeConfiguration: RustBridgeConfiguration
    public var clientConfiguration: SVNClientConfiguration
    public var statusCenterConfiguration: StatusCenterConfiguration

    public init(
        repositoryRoot: String,
        databaseURL: URL,
        maxIncrementalDirtyPaths: Int,
        bridgeConfiguration: RustBridgeConfiguration,
        clientConfiguration: SVNClientConfiguration = .recommended,
        statusCenterConfiguration: StatusCenterConfiguration = .recommended
    ) {
        self.repositoryRoot = repositoryRoot
        self.databaseURL = databaseURL
        self.maxIncrementalDirtyPaths = maxIncrementalDirtyPaths
        self.bridgeConfiguration = bridgeConfiguration
        self.clientConfiguration = clientConfiguration
        self.statusCenterConfiguration = statusCenterConfiguration
    }

    public static func development(
        repositoryRoot: String,
        databaseURL: URL? = nil
    ) -> StatusServiceConfiguration {
        let resolvedURL = databaseURL
            ?? defaultDatabaseURL(for: repositoryRoot)

        return StatusServiceConfiguration(
            repositoryRoot: repositoryRoot,
            databaseURL: resolvedURL,
            maxIncrementalDirtyPaths: StatusCenterConfiguration.recommended.changedPathBatchSize,
            bridgeConfiguration: .development(repositoryRoot: repositoryRoot)
        )
    }

    private static func defaultDatabaseURL(for repositoryRoot: String) -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let sanitizedRoot = repositoryRoot
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return baseDirectory
            .appending(path: "MacTortoiseSVN")
            .appending(path: "StatusCache")
            .appending(path: "\(sanitizedRoot).sqlite3")
    }
}

public actor StatusServiceHost: WorkingCopyEventHandling {
    public let configuration: StatusServiceConfiguration

    private let center: StatusCenter
    private let store: SQLiteStatusCacheStore
    private let watcher: any WorkingCopyEventWatching

    public init(
        configuration: StatusServiceConfiguration,
        watcher: any WorkingCopyEventWatching = FSEventsWorkingCopyWatcher()
    ) throws {
        let client = RustCommandBridgeSVNClient(
            configuration: configuration.clientConfiguration,
            bridgeConfiguration: configuration.bridgeConfiguration
        )
        let store = try SQLiteStatusCacheStore(databaseURL: configuration.databaseURL)
        self.init(
            configuration: configuration,
            client: client,
            store: store,
            watcher: watcher
        )
    }

    init(
        configuration: StatusServiceConfiguration,
        client: any SVNClient,
        store: SQLiteStatusCacheStore,
        watcher: any WorkingCopyEventWatching = NoOpWorkingCopyWatcher()
    ) {
        self.configuration = configuration
        self.center = StatusCenter(
            client: client,
            configuration: configuration.statusCenterConfiguration
        )
        self.store = store
        self.watcher = watcher
    }

    public func startMonitoring(rootPath: String? = nil) async throws {
        let resolvedRoot = rootPath ?? configuration.repositoryRoot
        await watcher.setEventHandler(self)
        try await watcher.startMonitoring(rootPath: resolvedRoot)
        try await store.scheduleFullRefresh(rootPath: resolvedRoot)
    }

    public func stopMonitoring(rootPath: String? = nil) async throws {
        let resolvedRoot = rootPath ?? configuration.repositoryRoot
        try await watcher.stopMonitoring(rootPath: resolvedRoot)
    }

    public func markDirty(rootPath: String, paths: [String]) async throws {
        if paths.isEmpty {
            try await store.scheduleFullRefresh(rootPath: rootPath)
            return
        }

        try await store.markDirty(rootPath: rootPath, paths: paths)
        let pathCount = try await store.dirtyPathCount(for: rootPath)
        if pathCount > configuration.maxIncrementalDirtyPaths {
            try await store.scheduleFullRefresh(rootPath: rootPath)
        }
    }

    public func acceptFileSystemEvent(rootPath: String, changedPaths: [String]) async throws {
        try await markDirty(rootPath: rootPath, paths: changedPaths)
    }

    public func handle(event: WorkingCopyFileSystemEvent) async {
        do {
            switch event.scope {
            case .fullRefresh:
                try await store.scheduleFullRefresh(rootPath: event.rootPath)
            case .incremental:
                let filteredPaths = filteredChangedPaths(for: event)
                guard !filteredPaths.isEmpty else {
                    return
                }
                try await markDirty(rootPath: event.rootPath, paths: filteredPaths)
            }
        } catch {
            // Keep the event path resilient; the service can recover on the next refresh cycle.
        }
    }

    @discardableResult
    public func refresh(
        rootPath: String,
        forceFullRefresh: Bool = false
    ) async throws -> BadgeSnapshot {
        if forceFullRefresh {
            try await store.scheduleFullRefresh(rootPath: rootPath)
        }

        let dirtyState = try await store.loadDirtyState(for: rootPath)
        let shouldRunFullRefresh = forceFullRefresh || dirtyState?.requiresFullRefresh == true
        let changedPaths = shouldRunFullRefresh ? [] : (dirtyState?.paths ?? [])

        let snapshot = try await center.warmStatusIndex(
            for: rootPath,
            changedPaths: changedPaths,
            context: .background
        )
        try await store.save(snapshot: snapshot)
        try await store.clearDirtyState(for: rootPath)
        return snapshot
    }

    public func refreshIfNeeded(rootPath: String) async throws -> BadgeSnapshot {
        if let dirtyState = try await store.loadDirtyState(for: rootPath) {
            return try await refresh(
                rootPath: rootPath,
                forceFullRefresh: dirtyState.requiresFullRefresh
            )
        }

        if let snapshot = await center.snapshot(for: rootPath) {
            return snapshot
        }

        if let cachedSnapshot = try await store.loadSnapshot(for: rootPath) {
            await center.remember(snapshot: cachedSnapshot)
            return cachedSnapshot
        }

        try await store.scheduleFullRefresh(rootPath: rootPath)
        return try await refresh(rootPath: rootPath, forceFullRefresh: true)
    }

    public func snapshot(for rootPath: String) async throws -> BadgeSnapshot? {
        if let snapshot = await center.snapshot(for: rootPath) {
            return snapshot
        }

        guard let cachedSnapshot = try await store.loadSnapshot(for: rootPath) else {
            return nil
        }

        await center.remember(snapshot: cachedSnapshot)
        return cachedSnapshot
    }

    public func pendingRefreshRoots() async throws -> [DirtyRefreshState] {
        try await store.loadDirtyRoots()
    }

    public func evict(rootPath: String) async throws {
        await center.evict(rootPath: rootPath)
        try await store.deleteSnapshot(for: rootPath)
        try await store.clearDirtyState(for: rootPath)
    }

    private func filteredChangedPaths(for event: WorkingCopyFileSystemEvent) -> [String] {
        let ignoredPaths = Set([
            configuration.databaseURL.standardizedFileURL.path,
            configuration.databaseURL.standardizedFileURL.path + "-shm",
            configuration.databaseURL.standardizedFileURL.path + "-wal",
        ])

        return Array(
            Set(
                event.changedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                    .filter { !ignoredPaths.contains($0) }
            )
        ).sorted()
    }
}
