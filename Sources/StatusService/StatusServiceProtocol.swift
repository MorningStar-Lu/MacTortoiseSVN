import CoreTypes
import Foundation

public enum StatusServiceMethod: String, Sendable, Hashable, Codable {
    case startMonitoring
    case stopMonitoring
    case markDirty
    case refresh
    case refreshIfNeeded
    case snapshot
    case pendingRefreshRoots
    case evict
    case shutdown
}

public struct StatusServiceRequest: Sendable, Hashable, Codable {
    public var id: String
    public var method: StatusServiceMethod
    public var rootPath: String?
    public var paths: [String]
    public var forceFullRefresh: Bool

    public init(
        id: String = UUID().uuidString,
        method: StatusServiceMethod,
        rootPath: String? = nil,
        paths: [String] = [],
        forceFullRefresh: Bool = false
    ) {
        self.id = id
        self.method = method
        self.rootPath = rootPath
        self.paths = paths
        self.forceFullRefresh = forceFullRefresh
    }
}

public struct StatusServiceResponse: Sendable, Hashable, Codable {
    public var id: String
    public var ok: Bool
    public var acknowledged: Bool
    public var snapshot: BadgeSnapshot?
    public var dirtyRoots: [DirtyRefreshState]?
    public var error: String?
    public var shouldTerminate: Bool

    public init(
        id: String,
        ok: Bool,
        acknowledged: Bool = false,
        snapshot: BadgeSnapshot? = nil,
        dirtyRoots: [DirtyRefreshState]? = nil,
        error: String? = nil,
        shouldTerminate: Bool = false
    ) {
        self.id = id
        self.ok = ok
        self.acknowledged = acknowledged
        self.snapshot = snapshot
        self.dirtyRoots = dirtyRoots
        self.error = error
        self.shouldTerminate = shouldTerminate
    }
}

public actor StatusServiceCommandProcessor {
    private let host: StatusServiceHost

    public init(host: StatusServiceHost) {
        self.host = host
    }

    public func handle(_ request: StatusServiceRequest) async -> StatusServiceResponse {
        do {
            let rootPath: String
            if let explicitRootPath = request.rootPath {
                rootPath = explicitRootPath
            } else {
                rootPath = host.configuration.repositoryRoot
            }
            switch request.method {
            case .startMonitoring:
                try await host.startMonitoring(rootPath: rootPath)
                return StatusServiceResponse(id: request.id, ok: true, acknowledged: true)
            case .stopMonitoring:
                try await host.stopMonitoring(rootPath: rootPath)
                return StatusServiceResponse(id: request.id, ok: true, acknowledged: true)
            case .markDirty:
                try await host.markDirty(rootPath: rootPath, paths: request.paths)
                return StatusServiceResponse(id: request.id, ok: true, acknowledged: true)
            case .refresh:
                let snapshot = try await host.refresh(
                    rootPath: rootPath,
                    forceFullRefresh: request.forceFullRefresh
                )
                return StatusServiceResponse(id: request.id, ok: true, snapshot: snapshot)
            case .refreshIfNeeded:
                let snapshot = try await host.refreshIfNeeded(rootPath: rootPath)
                return StatusServiceResponse(id: request.id, ok: true, snapshot: snapshot)
            case .snapshot:
                let snapshot = try await host.snapshot(for: rootPath)
                return StatusServiceResponse(id: request.id, ok: true, snapshot: snapshot)
            case .pendingRefreshRoots:
                let dirtyRoots = try await host.pendingRefreshRoots()
                return StatusServiceResponse(id: request.id, ok: true, dirtyRoots: dirtyRoots)
            case .evict:
                try await host.evict(rootPath: rootPath)
                return StatusServiceResponse(id: request.id, ok: true, acknowledged: true)
            case .shutdown:
                try await host.stopMonitoring(rootPath: rootPath)
                return StatusServiceResponse(
                    id: request.id,
                    ok: true,
                    acknowledged: true,
                    shouldTerminate: true
                )
            }
        } catch {
            return StatusServiceResponse(
                id: request.id,
                ok: false,
                error: error.localizedDescription
            )
        }
    }
}
