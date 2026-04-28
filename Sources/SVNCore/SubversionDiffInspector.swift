import Foundation

public struct SVNDiffPreview: Sendable, Hashable, Codable {
    public var targetPath: String
    public var rawText: String

    public var isEmpty: Bool {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(targetPath: String, rawText: String) {
        self.targetPath = targetPath
        self.rawText = rawText
    }
}

public enum SubversionDiffInspectorError: Error, Sendable, LocalizedError, Equatable {
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, exitCode, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ", stderr: \(stderr)"
            return "svn command failed: svn \(arguments.joined(separator: " ")) (exit: \(exitCode))\(stderrSuffix)"
        }
    }
}

public actor SubversionDiffInspector {
    private let runner: any SubversionCommandRunning

    public init() {
        self.runner = ProcessSubversionRunner()
    }

    init(runner: any SubversionCommandRunning) {
        self.runner = runner
    }

    public func workingCopyDiff(
        at path: String,
        workingCopyRoot: String? = nil,
        context: SVNCommandContext
    ) async throws -> SVNDiffPreview {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["diff", path],
            workingDirectory: workingCopyRoot ?? fallbackWorkingDirectory(for: path)
        )
        let result = try await runner.run(request)

        guard result.exitCode == 0 else {
            throw SubversionDiffInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return SVNDiffPreview(targetPath: path, rawText: result.stdout)
    }

    public func revisionDiff(
        at rootPath: String,
        revision: Int64,
        context: SVNCommandContext
    ) async throws -> SVNDiffPreview {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["diff", "-c", String(revision), rootPath],
            workingDirectory: rootPath
        )
        let result = try await runner.run(request)

        guard result.exitCode == 0 else {
            throw SubversionDiffInspectorError.commandFailed(
                arguments: request.arguments,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return SVNDiffPreview(targetPath: "r\(revision)", rawText: result.stdout)
    }

    private func fallbackWorkingDirectory(for path: String) -> String {
        let parentDirectory = (path as NSString).deletingLastPathComponent
        return parentDirectory.isEmpty ? path : parentDirectory
    }
}
