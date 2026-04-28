import Foundation

public enum VersionControlStatus: String, Sendable, CaseIterable, Codable {
    case unversioned
    case normal
    case modified
    case added
    case deleted
    case conflicted
    case ignored
    case external
    case locked
    case missing
    case replaced
    case incomplete
    case obstructed

    public var isDirty: Bool {
        switch self {
        case .modified, .added, .deleted, .conflicted, .missing, .replaced, .incomplete, .obstructed:
            return true
        case .unversioned, .normal, .ignored, .external, .locked:
            return false
        }
    }
}

public struct RepositoryLocation: Sendable, Hashable, Codable {
    public var workingCopyRoot: String
    public var repositoryURL: String
    public var displayName: String

    public init(workingCopyRoot: String, repositoryURL: String, displayName: String) {
        self.workingCopyRoot = workingCopyRoot
        self.repositoryURL = repositoryURL
        self.displayName = displayName
    }
}

public struct WorkingCopyItem: Sendable, Hashable, Codable, Identifiable {
    public var path: String
    public var isDirectory: Bool
    public var status: VersionControlStatus
    public var propertyModified: Bool

    public var id: String {
        path
    }

    public var displayName: String {
        (path as NSString).lastPathComponent
    }

    public var isDirty: Bool {
        status.isDirty || propertyModified
    }

    public init(
        path: String,
        isDirectory: Bool,
        status: VersionControlStatus,
        propertyModified: Bool = false
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.status = status
        self.propertyModified = propertyModified
    }
}

public struct CommitCandidate: Sendable, Hashable, Codable {
    public var path: String
    public var status: VersionControlStatus
    public var isExplicitlySelected: Bool

    public init(path: String, status: VersionControlStatus, isExplicitlySelected: Bool) {
        self.path = path
        self.status = status
        self.isExplicitlySelected = isExplicitlySelected
    }
}

public struct BadgeSnapshot: Sendable, Hashable, Codable {
    public var rootPath: String
    public var generatedAt: Date
    public var entries: [String: VersionControlStatus]

    public init(rootPath: String, generatedAt: Date, entries: [String: VersionControlStatus]) {
        self.rootPath = rootPath
        self.generatedAt = generatedAt
        self.entries = entries
    }
}
