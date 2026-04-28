import CoreTypes
import Foundation

public enum SVNBackendKind: String, Sendable, Hashable, Codable {
    case libsvn
    case commandLine
    case xcodeBundled
}

public enum SVNDepth: String, Sendable, Hashable, Codable {
    case empty
    case files
    case immediates
    case infinity
}

public struct SVNClientConfiguration: Sendable, Hashable, Codable {
    public var preferredBackend: SVNBackendKind
    public var preserveModificationTimes: Bool
    public var maxConcurrentOperations: Int
    public var enableLargeWorkingCopyOptimizations: Bool

    public init(
        preferredBackend: SVNBackendKind,
        preserveModificationTimes: Bool,
        maxConcurrentOperations: Int,
        enableLargeWorkingCopyOptimizations: Bool
    ) {
        self.preferredBackend = preferredBackend
        self.preserveModificationTimes = preserveModificationTimes
        self.maxConcurrentOperations = maxConcurrentOperations
        self.enableLargeWorkingCopyOptimizations = enableLargeWorkingCopyOptimizations
    }

    public static let recommended = SVNClientConfiguration(
        preferredBackend: .libsvn,
        preserveModificationTimes: true,
        maxConcurrentOperations: 2,
        enableLargeWorkingCopyOptimizations: true
    )
}

public struct SVNCommandContext: Sendable, Hashable, Codable {
    public var initiatedBy: String
    public var isInteractive: Bool

    public init(initiatedBy: String, isInteractive: Bool) {
        self.initiatedBy = initiatedBy
        self.isInteractive = isInteractive
    }

    public static let background = SVNCommandContext(initiatedBy: "status-service", isInteractive: false)
    public static let foreground = SVNCommandContext(initiatedBy: "main-app", isInteractive: true)
}

public struct StatusQueryOptions: Sendable, Hashable, Codable {
    public var recursive: Bool
    public var includeIgnored: Bool
    public var includeUnversioned: Bool

    public init(recursive: Bool, includeIgnored: Bool, includeUnversioned: Bool) {
        self.recursive = recursive
        self.includeIgnored = includeIgnored
        self.includeUnversioned = includeUnversioned
    }

    public static let badges = StatusQueryOptions(
        recursive: true,
        includeIgnored: false,
        includeUnversioned: false
    )

    public static let commitSheet = StatusQueryOptions(
        recursive: true,
        includeIgnored: false,
        includeUnversioned: true
    )
}

public protocol SVNClient: Sendable {
    func status(
        at rootPath: String,
        options: StatusQueryOptions,
        context: SVNCommandContext
    ) async throws -> [WorkingCopyItem]

    func commit(
        candidates: [CommitCandidate],
        message: String,
        context: SVNCommandContext
    ) async throws -> Int64

    func add(
        paths: [String],
        depth: SVNDepth,
        force: Bool,
        context: SVNCommandContext
    ) async throws

    func shelve(
        paths: [String],
        name: String,
        context: SVNCommandContext
    ) async throws

    func unshelve(
        name: String,
        context: SVNCommandContext
    ) async throws

    func log(
        path: String,
        revision: Int64,
        limit: Int,
        context: SVNCommandContext
    ) async throws -> [SVNHistoryEntry]
}

public actor NullSVNClient: SVNClient {
    public let configuration: SVNClientConfiguration

    public init(configuration: SVNClientConfiguration) {
        self.configuration = configuration
    }

    public func status(
        at rootPath: String,
        options: StatusQueryOptions,
        context: SVNCommandContext
    ) async throws -> [WorkingCopyItem] {
        []
    }

    public func commit(
        candidates: [CommitCandidate],
        message: String,
        context: SVNCommandContext
    ) async throws -> Int64 {
        0
    }

    public func add(
        paths: [String],
        depth: SVNDepth,
        force: Bool,
        context: SVNCommandContext
    ) async throws {
    }

    public func shelve(
        paths: [String],
        name: String,
        context: SVNCommandContext
    ) async throws {
    }

    public func unshelve(
        name: String,
        context: SVNCommandContext
    ) async throws {
    }

    public func log(
        path: String,
        revision: Int64,
        limit: Int,
        context: SVNCommandContext
    ) async throws -> [SVNHistoryEntry] {
        []
    }
}
