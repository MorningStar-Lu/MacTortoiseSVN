import Foundation

public struct SVNUpdateResult: Sendable, Hashable, Codable {
    public var rootPath: String
    public var updatedPaths: [String]
    public var resultingRevision: Int64?
    public var hasConflicts: Bool
    public var rawOutput: String

    public init(
        rootPath: String,
        updatedPaths: [String],
        resultingRevision: Int64?,
        hasConflicts: Bool,
        rawOutput: String
    ) {
        self.rootPath = rootPath
        self.updatedPaths = updatedPaths
        self.resultingRevision = resultingRevision
        self.hasConflicts = hasConflicts
        self.rawOutput = rawOutput
    }
}

public struct SVNRevertResult: Sendable, Hashable, Codable {
    public var requestedPaths: [String]
    public var revertedPaths: [String]
    public var removeAdded: Bool
    public var rawOutput: String

    public init(
        requestedPaths: [String],
        revertedPaths: [String],
        removeAdded: Bool,
        rawOutput: String
    ) {
        self.requestedPaths = requestedPaths
        self.revertedPaths = revertedPaths
        self.removeAdded = removeAdded
        self.rawOutput = rawOutput
    }
}

public struct SVNCleanupResult: Sendable, Hashable, Codable {
    public var rootPath: String
    public var rawOutput: String

    public init(rootPath: String, rawOutput: String) {
        self.rootPath = rootPath
        self.rawOutput = rawOutput
    }
}

public struct SVNResolveResult: Sendable, Hashable, Codable {
    public var requestedPaths: [String]
    public var resolvedPaths: [String]
    public var acceptStrategy: String
    public var rawOutput: String

    public init(
        requestedPaths: [String],
        resolvedPaths: [String],
        acceptStrategy: String,
        rawOutput: String
    ) {
        self.requestedPaths = requestedPaths
        self.resolvedPaths = resolvedPaths
        self.acceptStrategy = acceptStrategy
        self.rawOutput = rawOutput
    }
}

public actor SubversionWorkspaceOperator {
    private let runner: any SubversionCommandRunning

    public init() {
        self.runner = ProcessSubversionRunner()
    }

    init(runner: any SubversionCommandRunning) {
        self.runner = runner
    }

    public func update(
        rootPath: String,
        depth: SVNDepth = .infinity,
        accept: String = "postpone",
        context: SVNCommandContext
    ) async throws -> SVNUpdateResult {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: [
                "update",
                rootPath,
                "--depth",
                depth.rawValue,
                "--accept",
                accept,
            ],
            workingDirectory: rootPath
        )
        let result = try await run(request)
        return parseUpdateResult(result.stdout, rootPath: rootPath)
    }

    public func revert(
        paths: [String],
        recursive: Bool = true,
        removeAdded: Bool = false,
        context: SVNCommandContext
    ) async throws -> SVNRevertResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNRevertResult(
                requestedPaths: [],
                revertedPaths: [],
                removeAdded: removeAdded,
                rawOutput: ""
            )
        }

        var arguments = ["revert"] + normalizedPaths
        arguments += ["--depth", recursive ? "infinity" : "empty"]
        if removeAdded {
            arguments.append("--remove-added")
        }

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseRevertResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            removeAdded: removeAdded
        )
    }

    public func cleanup(
        rootPath: String,
        context: SVNCommandContext
    ) async throws -> SVNCleanupResult {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["cleanup", rootPath],
            workingDirectory: rootPath
        )
        let result = try await run(request)
        return SVNCleanupResult(rootPath: rootPath, rawOutput: result.stdout)
    }

    public func resolve(
        paths: [String],
        accept: String = "working",
        recursive: Bool = true,
        context: SVNCommandContext
    ) async throws -> SVNResolveResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNResolveResult(
                requestedPaths: [],
                resolvedPaths: [],
                acceptStrategy: accept,
                rawOutput: ""
            )
        }

        var arguments = ["resolve"] + normalizedPaths
        arguments += ["--accept", accept]
        arguments += ["--depth", recursive ? "infinity" : "empty"]

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseResolveResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            accept: accept
        )
    }

    private func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
        let result = try await runner.run(request)
        guard result.exitCode == 0 else {
            throw SubversionRepositoryInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    private func parseUpdateResult(_ stdout: String, rootPath: String) -> SVNUpdateResult {
        let lines = stdout.split(separator: "\n").map(String.init)
        var updatedPaths: [String] = []
        var hasConflicts = false
        var resultingRevision: Int64?

        for line in lines {
            if let parsedPath = parseUpdatedPath(from: line) {
                updatedPaths.append(parsedPath.path)
                hasConflicts = hasConflicts || parsedPath.hasConflict
                continue
            }

            if let parsedRevision = parseResultingRevision(from: line) {
                resultingRevision = parsedRevision
            }
        }

        return SVNUpdateResult(
            rootPath: rootPath,
            updatedPaths: updatedPaths,
            resultingRevision: resultingRevision,
            hasConflicts: hasConflicts,
            rawOutput: stdout
        )
    }

    private func parseRevertResult(
        _ stdout: String,
        requestedPaths: [String],
        removeAdded: Bool
    ) -> SVNRevertResult {
        let revertedPaths = stdout
            .split(separator: "\n")
            .compactMap { parseRevertedPath(from: String($0)) }

        return SVNRevertResult(
            requestedPaths: requestedPaths,
            revertedPaths: revertedPaths.isEmpty ? requestedPaths : revertedPaths,
            removeAdded: removeAdded,
            rawOutput: stdout
        )
    }

    private func parseUpdatedPath(from line: String) -> (path: String, hasConflict: Bool)? {
        guard line.count > 5 else {
            return nil
        }

        let prefix = String(line.prefix(4))
        let statusCharacters = Set(prefix.filter { !$0.isWhitespace })
        let supported = Set("ADUCGER")

        guard !statusCharacters.isEmpty, statusCharacters.isSubset(of: supported) else {
            return nil
        }

        let path = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }

        return (path, prefix.contains("C"))
    }

    private func parseResultingRevision(from line: String) -> Int64? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Updated to revision ",
            "At revision ",
        ]

        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }

        let revisionPortion = trimmed
            .dropFirst(prefix.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return Int64(revisionPortion)
    }

    private func parseRevertedPath(from line: String) -> String? {
        let prefix = "Reverted '"
        guard line.hasPrefix(prefix), line.hasSuffix("'") else {
            return nil
        }

        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func parseResolveResult(
        _ stdout: String,
        requestedPaths: [String],
        accept: String
    ) -> SVNResolveResult {
        let resolvedPaths = stdout
            .split(separator: "\n")
            .compactMap { parseResolvedPath(from: String($0)) }

        return SVNResolveResult(
            requestedPaths: requestedPaths,
            resolvedPaths: resolvedPaths.isEmpty ? requestedPaths : resolvedPaths,
            acceptStrategy: accept,
            rawOutput: stdout
        )
    }

    private func parseResolvedPath(from line: String) -> String? {
        guard
            let firstQuote = line.firstIndex(of: "'"),
            let lastQuote = line.lastIndex(of: "'"),
            firstQuote < lastQuote,
            line.contains("marked as resolved")
        else {
            return nil
        }

        return String(line[line.index(after: firstQuote)..<lastQuote])
    }

    public func rollback(
        paths: [String],
        revision: Int64,
        recursive: Bool = true,
        context: SVNCommandContext
    ) async throws -> SVNRevertResult {
        let normalizedPaths = Array(Set(paths)).sorted()
        guard let firstPath = normalizedPaths.first else {
            return SVNRevertResult(
                requestedPaths: [],
                revertedPaths: [],
                removeAdded: false,
                rawOutput: ""
            )
        }

        var arguments = ["revert", "-r", String(revision)] + normalizedPaths
        arguments += ["--depth", recursive ? "infinity" : "empty"]

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: (firstPath as NSString).deletingLastPathComponent
        )
        let result = try await run(request)
        return parseRevertResult(
            result.stdout,
            requestedPaths: normalizedPaths,
            removeAdded: false
        )
    }
}
