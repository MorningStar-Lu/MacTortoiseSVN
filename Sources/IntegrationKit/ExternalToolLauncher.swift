import Foundation

private final class ExternalToolProcessExitStatusObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Never>?
    private var exitCode: Int32?

    func install(on process: Process) {
        process.terminationHandler = { [weak self] process in
            self?.finish(with: process.terminationStatus)
        }
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitCode {
                lock.unlock()
                continuation.resume(returning: exitCode)
                return
            }

            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(with exitCode: Int32) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: exitCode)
            return
        }

        self.exitCode = exitCode
        lock.unlock()
    }
}

public struct ExternalToolInvocationRequest: Sendable, Hashable {
    public var launchPath: String
    public var arguments: [String]

    public init(launchPath: String, arguments: [String]) {
        self.launchPath = launchPath
        self.arguments = arguments
    }
}

public struct ExternalToolInvocationResult: Sendable, Hashable {
    public var exitCode: Int32
    public var stderr: String

    public init(exitCode: Int32, stderr: String) {
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

protocol ExternalToolCommandRunning: Sendable {
    func run(_ request: ExternalToolInvocationRequest) async throws -> ExternalToolInvocationResult
}

struct ProcessExternalToolRunner: ExternalToolCommandRunning {
    func run(_ request: ExternalToolInvocationRequest) async throws -> ExternalToolInvocationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.launchPath)
        process.arguments = request.arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        let exitObserver = ExternalToolProcessExitStatusObserver()
        exitObserver.install(on: process)

        try process.run()
        let stderrData = try await readDataToEnd(from: stderrPipe.fileHandleForReading)
        let exitCode = await exitObserver.waitForExit()
        process.terminationHandler = nil

        return ExternalToolInvocationResult(
            exitCode: exitCode,
            stderr: String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func readDataToEnd(from handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                try? handle.close()
                continuation.resume(returning: data)
            }
        }
    }
}

public enum ExternalToolLauncherError: Error, Sendable, LocalizedError, Equatable {
    case missingRightHandPath(String)
    case directoryDiffUnsupported(String)
    case launchFailed(launchPath: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .missingRightHandPath(displayName):
            return "The external diff profile '\(displayName)' requires both left and right paths."
        case let .directoryDiffUnsupported(displayName):
            return "The external diff profile '\(displayName)' does not support directory comparisons."
        case let .launchFailed(launchPath, exitCode, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ", stderr: \(stderr)"
            return "External tool launch failed: \(launchPath) (exit: \(exitCode))\(stderrSuffix)"
        }
    }
}

public actor ExternalToolLauncher {
    private let runner: any ExternalToolCommandRunning

    public init() {
        self.runner = ProcessExternalToolRunner()
    }

    init(runner: any ExternalToolCommandRunning) {
        self.runner = runner
    }

    public func launch(
        profile: ExternalToolProfile,
        leftPath: String,
        rightPath: String? = nil,
        isDirectory: Bool = false
    ) async throws {
        guard !isDirectory || profile.supportsDirectoryDiff else {
            throw ExternalToolLauncherError.directoryDiffUnsupported(profile.displayName)
        }

        let request = try invocationRequest(
            profile: profile,
            leftPath: leftPath,
            rightPath: rightPath
        )
        let result = try await runner.run(request)

        guard result.exitCode == 0 else {
            throw ExternalToolLauncherError.launchFailed(
                launchPath: request.launchPath,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    func invocationRequest(
        profile: ExternalToolProfile,
        leftPath: String,
        rightPath: String? = nil
    ) throws -> ExternalToolInvocationRequest {
        if profile.arguments.contains(where: { $0.contains("$RIGHT") }), rightPath == nil {
            throw ExternalToolLauncherError.missingRightHandPath(profile.displayName)
        }

        let resolvedArguments = profile.arguments.compactMap { argument -> String? in
            if argument == "$RIGHT", rightPath == nil {
                return nil
            }

            return argument
                .replacingOccurrences(of: "$LEFT", with: leftPath)
                .replacingOccurrences(of: "$RIGHT", with: rightPath ?? "")
        }

        return ExternalToolInvocationRequest(
            launchPath: profile.launchPath,
            arguments: resolvedArguments
        )
    }
}
