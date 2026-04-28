import CoreTypes
import Foundation

public enum ExternalToolKind: String, Sendable, Hashable, Codable, CaseIterable {
    case systemDefault
    case bbedit
    case beyondCompare
    case custom
}

public struct ExternalToolProfile: Sendable, Hashable, Codable, Identifiable {
    public var kind: ExternalToolKind
    public var displayName: String
    public var launchPath: String
    public var arguments: [String]
    public var supportsDirectoryDiff: Bool

    public var id: String {
        "\(kind.rawValue):\(displayName)"
    }

    public init(
        kind: ExternalToolKind,
        displayName: String,
        launchPath: String,
        arguments: [String],
        supportsDirectoryDiff: Bool
    ) {
        self.kind = kind
        self.displayName = displayName
        self.launchPath = launchPath
        self.arguments = arguments
        self.supportsDirectoryDiff = supportsDirectoryDiff
    }
}

public struct TimestampPreservationPolicy: Sendable, Hashable, Codable {
    public var preserveCheckoutModificationTimes: Bool
    public var preserveUpdateModificationTimes: Bool
    public var preferCommitTimesWhenAvailable: Bool

    public init(
        preserveCheckoutModificationTimes: Bool,
        preserveUpdateModificationTimes: Bool,
        preferCommitTimesWhenAvailable: Bool
    ) {
        self.preserveCheckoutModificationTimes = preserveCheckoutModificationTimes
        self.preserveUpdateModificationTimes = preserveUpdateModificationTimes
        self.preferCommitTimesWhenAvailable = preferCommitTimesWhenAvailable
    }

    public static let recommended = TimestampPreservationPolicy(
        preserveCheckoutModificationTimes: true,
        preserveUpdateModificationTimes: true,
        preferCommitTimesWhenAvailable: true
    )
}

public enum FinderCommand: String, Sendable, Hashable, Codable, CaseIterable {
    case commit
    case update
    case diff
    case log
    case shelve
    case add
    case revert
}

public struct FinderMenuItem: Sendable, Hashable, Codable, Identifiable {
    public var command: FinderCommand
    public var title: String

    public var id: String {
        command.rawValue
    }

    public init(command: FinderCommand, title: String) {
        self.command = command
        self.title = title
    }
}

public actor ExternalToolRegistry {
    public private(set) var profiles: [ExternalToolProfile]

    public init(profiles: [ExternalToolProfile] = []) {
        self.profiles = profiles
    }

    @discardableResult
    public func bootstrapDefaultProfiles() -> [ExternalToolProfile] {
        if profiles.isEmpty {
            profiles = [
                ExternalToolProfile(
                    kind: .systemDefault,
                    displayName: "System Default",
                    launchPath: "/usr/bin/open",
                    arguments: ["$LEFT"],
                    supportsDirectoryDiff: false
                ),
                ExternalToolProfile(
                    kind: .bbedit,
                    displayName: "BBEdit",
                    launchPath: "/usr/bin/open",
                    arguments: ["-a", "BBEdit", "$LEFT", "$RIGHT"],
                    supportsDirectoryDiff: false
                ),
                ExternalToolProfile(
                    kind: .beyondCompare,
                    displayName: "Beyond Compare",
                    launchPath: "/usr/bin/open",
                    arguments: ["-a", "Beyond Compare", "$LEFT", "$RIGHT"],
                    supportsDirectoryDiff: true
                ),
            ]
        }

        return profiles
    }
}
