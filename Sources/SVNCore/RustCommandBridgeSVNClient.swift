import CoreTypes
import Foundation

let macSVNPreferredExecutableSearchPaths = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/Applications/Xcode.app/Contents/Developer/usr/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
]

func macSVNExtendedExecutablePath(currentPath: String?) -> String {
    let existingPaths = currentPath?
        .split(separator: ":")
        .map(String.init) ?? []
    var mergedPaths: [String] = []

    for path in macSVNPreferredExecutableSearchPaths + existingPaths where !path.isEmpty {
        if !mergedPaths.contains(path) {
            mergedPaths.append(path)
        }
    }

    return mergedPaths.joined(separator: ":")
}

public struct RustBridgeConfiguration: Sendable, Hashable, Codable {
    public var repositoryRoot: String
    public var cargoExecutable: String
    public var rustWorkspaceRelativePath: String
    public var rustBinaryRelativePath: String
    public var preferBuiltBinary: Bool

    public init(
        repositoryRoot: String,
        cargoExecutable: String = "/opt/homebrew/bin/cargo",
        rustWorkspaceRelativePath: String = "rust",
        rustBinaryRelativePath: String = "rust/target/debug/mtsvn-rs",
        preferBuiltBinary: Bool = true
    ) {
        self.repositoryRoot = repositoryRoot
        self.cargoExecutable = cargoExecutable
        self.rustWorkspaceRelativePath = rustWorkspaceRelativePath
        self.rustBinaryRelativePath = rustBinaryRelativePath
        self.preferBuiltBinary = preferBuiltBinary
    }

    public static func development(repositoryRoot: String) -> RustBridgeConfiguration {
        RustBridgeConfiguration(repositoryRoot: repositoryRoot)
    }

    fileprivate func invocationRequest(for arguments: [String]) -> RustBridgeInvocationRequest {
        let fileManager = FileManager.default
        let repositoryURL = URL(fileURLWithPath: repositoryRoot)
        let builtBinaryPath = repositoryURL.appending(path: rustBinaryRelativePath).path

        if preferBuiltBinary, fileManager.isExecutableFile(atPath: builtBinaryPath) {
            return RustBridgeInvocationRequest(
                executablePath: builtBinaryPath,
                arguments: arguments,
                workingDirectory: repositoryRoot
            )
        }

        let rustWorkspacePath = repositoryURL.appending(path: rustWorkspaceRelativePath).path
        return RustBridgeInvocationRequest(
            executablePath: cargoExecutable,
            arguments: ["run", "-q", "-p", "mtsvn-rs", "--"] + arguments,
            workingDirectory: rustWorkspacePath
        )
    }
}

struct RustBridgeInvocationRequest: Sendable, Hashable {
    var executablePath: String
    var arguments: [String]
    var workingDirectory: String?
}

struct RustBridgeInvocationResult: Sendable, Hashable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

struct SubversionCLICommandRunner: SubversionCommandRunning {
    func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["svn"] + request.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = macSVNExtendedExecutablePath(currentPath: environment["PATH"])
        process.environment = environment

        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exitObserver = SVNProcessExitStatusObserver()
        exitObserver.install(on: process)

        try process.run()
        async let stdoutData = readDataToEnd(from: stdoutPipe.fileHandleForReading)
        async let stderrData = readDataToEnd(from: stderrPipe.fileHandleForReading)
        async let exitCode = exitObserver.waitForExit()
        let resolvedStdoutData = await stdoutData
        let resolvedStderrData = await stderrData
        process.terminationHandler = nil

        return SubversionCLIInvocationResult(
            stdout: String(decoding: resolvedStdoutData, as: UTF8.self),
            stderr: String(decoding: resolvedStderrData, as: UTF8.self),
            exitCode: await exitCode,
            stdoutData: resolvedStdoutData,
            stderrData: resolvedStderrData
        )
    }

    private func readDataToEnd(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                try? handle.close()
                continuation.resume(returning: data)
            }
        }
    }
}

protocol RustBridgeCommandRunning: Sendable {
    func run(_ request: RustBridgeInvocationRequest) async throws -> RustBridgeInvocationResult
}

struct ProcessRustBridgeRunner: RustBridgeCommandRunning {
    func run(_ request: RustBridgeInvocationRequest) async throws -> RustBridgeInvocationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = macSVNExtendedExecutablePath(currentPath: environment["PATH"])
        process.environment = environment

        if let workingDirectory = request.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exitObserver = SVNProcessExitStatusObserver()
        exitObserver.install(on: process)

        try process.run()
        async let stdoutData = readDataToEnd(
            from: stdoutPipe.fileHandleForReading
        )
        async let stderrData = readDataToEnd(
            from: stderrPipe.fileHandleForReading
        )
        async let exitCode = exitObserver.waitForExit()
        defer {
            process.terminationHandler = nil
        }

        return RustBridgeInvocationResult(
            stdout: String(decoding: await stdoutData, as: UTF8.self),
            stderr: String(decoding: await stderrData, as: UTF8.self),
            exitCode: await exitCode
        )
    }

    private func readDataToEnd(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                try? handle.close()
                continuation.resume(returning: data)
            }
        }
    }
}

public enum RustBridgeError: Error, Sendable, LocalizedError, Equatable {
    case commandFailed(executablePath: String, arguments: [String], exitCode: Int32, stderr: String)
    case invalidResponse(String)
    case unsupportedOperation(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(executablePath, arguments, exitCode, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ", stderr: \(stderr)"
            return "Rust bridge command failed: \(executablePath) \(arguments.joined(separator: " ")) (exit: \(exitCode))\(stderrSuffix)"
        case let .invalidResponse(message):
            return "Rust bridge returned an invalid response: \(message)"
        case let .unsupportedOperation(message):
            return message
        }
    }
}

private struct RustBridgeStatusPayload: Decodable {
    struct Entry: Decodable {
        let path: String
        let status: String
        let propsModified: Bool
        let isDirectory: Bool

        enum CodingKeys: String, CodingKey {
            case path
            case status
            case propsModified = "props_modified"
            case isDirectory = "is_directory"
        }
    }

    let kind: String
    let root: String
    let entries: [Entry]
}

private struct RustBridgeAddPayload: Decodable {
    let kind: String
    let pathCount: Int

    enum CodingKeys: String, CodingKey {
        case kind
        case pathCount = "path_count"
    }
}

private struct RustBridgeCommitPayload: Decodable {
    let kind: String
    let revision: Int64?
}

private struct RustBridgeLogPayload: Decodable {
    let kind: String
    let entries: [SVNHistoryEntry]
}

public actor RustCommandBridgeSVNClient: SVNClient {
    public let configuration: SVNClientConfiguration

    private let bridgeConfiguration: RustBridgeConfiguration
    private let rustBridgeRunner: any RustBridgeCommandRunning
    private let subversionCLIRunner: any SubversionCommandRunning

    public init(
        configuration: SVNClientConfiguration = .recommended,
        bridgeConfiguration: RustBridgeConfiguration
    ) {
        self.configuration = configuration
        self.bridgeConfiguration = bridgeConfiguration
        self.rustBridgeRunner = ProcessRustBridgeRunner()
        self.subversionCLIRunner = SubversionCLICommandRunner()
    }

    init(
        configuration: SVNClientConfiguration = .recommended,
        bridgeConfiguration: RustBridgeConfiguration,
        rustBridgeRunner: any RustBridgeCommandRunning,
        subversionCLIRunner: any SubversionCommandRunning
    ) {
        self.configuration = configuration
        self.bridgeConfiguration = bridgeConfiguration
        self.rustBridgeRunner = rustBridgeRunner
        self.subversionCLIRunner = subversionCLIRunner
    }

    public func status(
        at rootPath: String,
        options: StatusQueryOptions,
        context: SVNCommandContext
    ) async throws -> [WorkingCopyItem] {
        let mode = options.prefersSnapshotBridge ? "bridge-snapshot" : "bridge-status"
        let payload: RustBridgeStatusPayload = try await runBridgeCommand(
            for: [mode, rootPath] + options.bridgeArguments
        )
        return payload.entries.map { entry in
            WorkingCopyItem(
                path: entry.path,
                isDirectory: entry.isDirectory,
                status: VersionControlStatus(bridgeValue: entry.status),
                propertyModified: entry.propsModified
            )
        }
    }

    public func commit(
        candidates: [CommitCandidate],
        message: String,
        context: SVNCommandContext
    ) async throws -> Int64 {
        let paths = candidates.map(\.path)
        guard !paths.isEmpty else {
            throw RustBridgeError.unsupportedOperation("Commit requires at least one selected path.")
        }

        let payload: RustBridgeCommitPayload = try await runBridgeCommand(
            for: ["bridge-commit"] + paths.bridgePathArguments + ["--message", message]
        )
        guard let revision = payload.revision else {
            throw RustBridgeError.invalidResponse("Commit did not return a revision.")
        }
        return revision
    }

    public func add(
        paths: [String],
        depth: SVNDepth,
        force: Bool,
        context: SVNCommandContext
    ) async throws {
        guard !paths.isEmpty else {
            throw RustBridgeError.unsupportedOperation("Add requires at least one path.")
        }

        var arguments = ["bridge-add"] + paths.bridgePathArguments + ["--depth", depth.bridgeValue]
        if force {
            arguments.append("--force")
        }

        let _: RustBridgeAddPayload = try await runBridgeCommand(for: arguments)
    }

    public func shelve(
        paths: [String],
        name: String,
        context: SVNCommandContext
    ) async throws {
        throw RustBridgeError.unsupportedOperation(
            "Shelve is not wired through the phase-one Rust bridge yet."
        )
    }

    public func unshelve(
        name: String,
        context: SVNCommandContext
    ) async throws {
        throw RustBridgeError.unsupportedOperation(
            "Unshelve is not wired through the phase-one Rust bridge yet."
        )
    }

    public func log(
        path: String,
        revision: Int64,
        limit: Int,
        context: SVNCommandContext
    ) async throws -> [SVNHistoryEntry] {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["log", "--xml", "-l", String(limit), "-r", String(revision), path],
            workingDirectory: (path as NSString).deletingLastPathComponent
        )
        let result = try await subversionCLIRunner.run(request)

        guard result.exitCode == 0 else {
            throw RustBridgeError.commandFailed(
                executablePath: "svn",
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return parseSVNLogOutput(result.stdout)
    }

    private func parseSVNLogOutput(_ xml: String) -> [SVNHistoryEntry] {
        // Simple XML parsing for SVN log output
        let entries: [SVNHistoryEntry] = xml
            .components(separatedBy: "<logentry")
            .compactMap { component in
                guard component.count > 10 else { return nil }
                let inner = String(component.dropFirst(9))
                guard let firstClose = inner.firstIndex(of: ">"),
                      let revMatch = inner.prefix(upTo: firstClose).split(separator: "revision=")
                          .last?
                          .split(separator: "\"")
                          .first else { return nil }

                guard let rev = Int64(revMatch) else { return nil }

                let messageMatch = inner.components(separatedBy: "<msg>").last?
                    .components(separatedBy: "</msg>").first
                let message = messageMatch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let authorMatch = inner.components(separatedBy: "<author>").last?
                    .components(separatedBy: "</author>").first
                let author = authorMatch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let dateMatch = inner.components(separatedBy: "<date>").last?
                    .components(separatedBy: "</date>").first
                let dateString = dateMatch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let date = parseSVNDate(dateString)

                return SVNHistoryEntry(
                    revision: rev,
                    author: author,
                    date: date,
                    message: message
                )
            }

        return entries
    }

    private func parseSVNDate(_ dateString: String) -> Date {
        // SVN date format: YYYY-MM-DDTHH:MM:SS.ssssZ
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString) ?? Date()
    }

    private func decodePayload(from stdout: String) throws -> RustBridgeStatusPayload {
        let data = Data(stdout.utf8)
        do {
            return try JSONDecoder().decode(RustBridgeStatusPayload.self, from: data)
        } catch {
            throw RustBridgeError.invalidResponse(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func runBridgeCommand<T: Decodable>(for arguments: [String]) async throws -> T {
        let request = bridgeConfiguration.invocationRequest(for: arguments)
        let result = try await rustBridgeRunner.run(request)

        guard result.exitCode == 0 else {
            throw RustBridgeError.commandFailed(
                executablePath: request.executablePath,
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let data = Data(result.stdout.utf8)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RustBridgeError.invalidResponse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private extension StatusQueryOptions {
    var prefersSnapshotBridge: Bool {
        recursive && !includeIgnored && !includeUnversioned
    }

    var bridgeArguments: [String] {
        var arguments: [String] = []
        arguments.append(includeIgnored ? "--include-ignored" : "--exclude-ignored")
        arguments.append(includeUnversioned ? "--include-unversioned" : "--exclude-unversioned")
        arguments.append("--depth")
        arguments.append(recursive ? "infinity" : "files")
        return arguments
    }
}

private extension Array where Element == String {
    var bridgePathArguments: [String] {
        flatMap { ["--path", $0] }
    }
}

private extension SVNDepth {
    var bridgeValue: String {
        rawValue
    }
}

private extension VersionControlStatus {
    init(bridgeValue: String) {
        switch bridgeValue.lowercased() {
        case "none", "normal":
            self = .normal
        case "modified":
            self = .modified
        case "added":
            self = .added
        case "deleted":
            self = .deleted
        case "conflicted":
            self = .conflicted
        case "ignored":
            self = .ignored
        case "external":
            self = .external
        case "locked":
            self = .locked
        case "missing":
            self = .missing
        case "unversioned":
            self = .unversioned
        case "replaced":
            self = .replaced
        case "incomplete":
            self = .incomplete
        case "obstructed":
            self = .obstructed
        default:
            self = .modified
        }
    }
}
