import Foundation

final class SVNProcessExitStatusObserver: @unchecked Sendable {
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

public struct SVNRepositorySummary: Sendable, Hashable, Codable {
    public var workingCopyRoot: String
    public var repositoryURL: String
    public var repositoryRootURL: String?
    public var revision: Int64
    public var lastChangedRevision: Int64?
    public var lastChangedAuthor: String?
    public var workingCopyUUID: String?

    public init(
        workingCopyRoot: String,
        repositoryURL: String,
        repositoryRootURL: String?,
        revision: Int64,
        lastChangedRevision: Int64?,
        lastChangedAuthor: String?,
        workingCopyUUID: String?
    ) {
        self.workingCopyRoot = workingCopyRoot
        self.repositoryURL = repositoryURL
        self.repositoryRootURL = repositoryRootURL
        self.revision = revision
        self.lastChangedRevision = lastChangedRevision
        self.lastChangedAuthor = lastChangedAuthor
        self.workingCopyUUID = workingCopyUUID
    }
}

public struct SVNHistoryEntry: Sendable, Hashable, Codable, Identifiable {
    public var revision: Int64
    public var author: String?
    public var date: Date?
    public var message: String

    public var id: Int64 {
        revision
    }

    public init(
        revision: Int64,
        author: String?,
        date: Date?,
        message: String
    ) {
        self.revision = revision
        self.author = author
        self.date = date
        self.message = message
    }
}

public struct SVNHistoryChangedPath: Sendable, Hashable, Codable, Identifiable {
    public var path: String
    public var action: String
    public var kind: String?
    public var textModified: Bool?
    public var propertyModified: Bool?

    public var id: String {
        "\(action):\(path)"
    }

    public init(
        path: String,
        action: String,
        kind: String?,
        textModified: Bool?,
        propertyModified: Bool?
    ) {
        self.path = path
        self.action = action
        self.kind = kind
        self.textModified = textModified
        self.propertyModified = propertyModified
    }
}

public struct SVNHistoryEntryDetail: Sendable, Hashable, Codable {
    public var entry: SVNHistoryEntry
    public var changedPaths: [SVNHistoryChangedPath]

    public init(entry: SVNHistoryEntry, changedPaths: [SVNHistoryChangedPath]) {
        self.entry = entry
        self.changedPaths = changedPaths
    }
}

public struct SVNRepositoryBrowserEntry: Sendable, Hashable, Codable, Identifiable {
    public var name: String
    public var fullURL: String
    public var isDirectory: Bool
    public var size: Int64?
    public var revision: Int64?
    public var author: String?
    public var date: Date?

    public var id: String {
        fullURL
    }

    public init(
        name: String,
        fullURL: String,
        isDirectory: Bool,
        size: Int64?,
        revision: Int64?,
        author: String?,
        date: Date?
    ) {
        self.name = name
        self.fullURL = fullURL
        self.isDirectory = isDirectory
        self.size = size
        self.revision = revision
        self.author = author
        self.date = date
    }
}

public struct SVNRepositoryBrowserListing: Sendable, Hashable, Codable {
    public var baseURL: String
    public var entries: [SVNRepositoryBrowserEntry]

    public init(baseURL: String, entries: [SVNRepositoryBrowserEntry]) {
        self.baseURL = baseURL
        self.entries = entries
    }
}

public struct SVNFileContentPreview: Sendable, Hashable {
    public var sourceIdentifier: String
    public var data: Data
    public var text: String?
    public var isBinary: Bool

    public var byteCount: Int {
        data.count
    }

    public init(sourceIdentifier: String, data: Data) {
        self.sourceIdentifier = sourceIdentifier
        self.data = data

        if let decodedText = Self.decodeText(from: data) {
            self.text = decodedText
            self.isBinary = false
        } else {
            self.text = nil
            self.isBinary = true
        }
    }

    private static func decodeText(from data: Data) -> String? {
        if data.isEmpty {
            return ""
        }

        if data.contains(0) {
            return nil
        }

        if let utf8Text = String(data: data, encoding: .utf8), looksLikeText(utf8Text) {
            return utf8Text
        }

        if let asciiText = String(data: data, encoding: .ascii), looksLikeText(asciiText) {
            return asciiText
        }

        return nil
    }

    private static func looksLikeText(_ string: String) -> Bool {
        let scalars = string.unicodeScalars
        guard !scalars.isEmpty else {
            return true
        }

        let suspiciousScalarCount = scalars.reduce(into: 0) { count, scalar in
            if CharacterSet.controlCharacters.contains(scalar) && !"\n\r\t".unicodeScalars.contains(scalar) {
                count += 1
            }
        }

        return Double(suspiciousScalarCount) / Double(scalars.count) < 0.05
    }
}

public struct SubversionCLIInvocationRequest: Sendable, Hashable {
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executablePath: String = "svn", arguments: [String], workingDirectory: String?) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct SubversionCLIInvocationResult: Sendable, Hashable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public var stdoutData: Data
    public var stderrData: Data

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        stdoutData: Data? = nil,
        stderrData: Data? = nil
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.stdoutData = stdoutData ?? Data(stdout.utf8)
        self.stderrData = stderrData ?? Data(stderr.utf8)
    }
}

protocol SubversionCommandRunning: Sendable {
    func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult
}

public struct ProcessSubversionRunner: SubversionCommandRunning {
    public init() {}

    public func run(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
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

public enum SubversionRepositoryInspectorError: Error, Sendable, LocalizedError, Equatable {
    case commandFailed(arguments: [String], exitCode: Int32, stderr: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, exitCode, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ", stderr: \(stderr)"
            return "svn command failed: svn \(arguments.joined(separator: " ")) (exit: \(exitCode))\(stderrSuffix)"
        case let .invalidResponse(message):
            return "svn returned an invalid XML response: \(message)"
        }
    }
}

public actor SubversionRepositoryInspector {
    private let runner: any SubversionCommandRunning

    public init() {
        self.runner = ProcessSubversionRunner()
    }

    init(runner: any SubversionCommandRunning) {
        self.runner = runner
    }

    public func summary(
        at rootPath: String,
        context: SVNCommandContext
    ) async throws -> SVNRepositorySummary {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["info", "--xml", rootPath],
            workingDirectory: rootPath
        )
        let stdout = try await run(request)
        return try parseSummary(from: stdout, defaultWorkingCopyRoot: rootPath)
    }

    public func recentHistory(
        at rootPath: String,
        limit: Int = 8,
        context: SVNCommandContext
    ) async throws -> [SVNHistoryEntry] {
        guard limit > 0 else {
            return []
        }

        let historyTarget = try await historyLogTarget(
            for: rootPath,
            context: context
        )

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["log", "--xml", "-l", String(limit), historyTarget.target],
            workingDirectory: historyTarget.workingDirectory
        )
        let stdout = try await run(request)
        return try parseHistory(from: stdout)
    }

    public func logDetail(
        at rootPath: String,
        revision: Int64,
        context: SVNCommandContext
    ) async throws -> SVNHistoryEntryDetail {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["log", "--xml", "-v", "-r", String(revision), rootPath],
            workingDirectory: rootPath
        )
        let stdout = try await run(request)
        return try parseHistoryDetail(from: stdout)
    }

    public func browse(
        url: String,
        context: SVNCommandContext
    ) async throws -> SVNRepositoryBrowserListing {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["list", "--xml", url],
            workingDirectory: nil
        )
        let stdout = try await run(request)
        return try parseRepositoryBrowserListing(from: stdout)
    }

    public func fileContents(
        url: String,
        revision: Int64? = nil,
        context: SVNCommandContext
    ) async throws -> SVNFileContentPreview {
        var arguments = ["cat"]
        if let revision {
            arguments += ["-r", String(revision)]
        }
        arguments.append(url)

        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: arguments,
            workingDirectory: nil
        )
        let result = try await runRaw(request)
        return SVNFileContentPreview(sourceIdentifier: url, data: result.stdoutData)
    }

    public func workingCopyBaseContents(
        at path: String,
        context: SVNCommandContext
    ) async throws -> SVNFileContentPreview {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["cat", "-r", "BASE", path],
            workingDirectory: (path as NSString).deletingLastPathComponent
        )
        let result = try await runRaw(request)
        return SVNFileContentPreview(sourceIdentifier: path, data: result.stdoutData)
    }

    public func exportWorkingCopyBase(
        at path: String,
        to destinationPath: String,
        context: SVNCommandContext
    ) async throws {
        let request = SubversionCLIInvocationRequest(
            executablePath: "svn",
            arguments: ["export", "-r", "BASE", path, destinationPath, "--force"],
            workingDirectory: (path as NSString).deletingLastPathComponent
        )
        _ = try await runRaw(request)
    }

    private func run(_ request: SubversionCLIInvocationRequest) async throws -> String {
        let result = try await runRaw(request)
        return result.stdout
    }

    private func runRaw(_ request: SubversionCLIInvocationRequest) async throws -> SubversionCLIInvocationResult {
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

    private func historyLogTarget(
        for rootPath: String,
        context: SVNCommandContext
    ) async throws -> (target: String, workingDirectory: String?) {
        guard !rootPath.contains("://") else {
            return (rootPath, nil)
        }

        let repositorySummary = try await summary(at: rootPath, context: context)
        return (repositorySummary.repositoryURL, rootPath)
    }

    private func parseSummary(
        from xml: String,
        defaultWorkingCopyRoot: String
    ) throws -> SVNRepositorySummary {
        let delegate = SubversionInfoXMLParserDelegate(defaultWorkingCopyRoot: defaultWorkingCopyRoot)
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let summary = delegate.summary else {
            let detail = parser.parserError?.localizedDescription
                ?? xml.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SubversionRepositoryInspectorError.invalidResponse(detail)
        }

        return summary
    }

    private func parseHistory(from xml: String) throws -> [SVNHistoryEntry] {
        let delegate = SubversionLogXMLParserDelegate()
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription
                ?? xml.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SubversionRepositoryInspectorError.invalidResponse(detail)
        }

        return delegate.entries
    }

    private func parseHistoryDetail(from xml: String) throws -> SVNHistoryEntryDetail {
        let delegate = SubversionVerboseLogXMLParserDelegate()
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let detail = delegate.detail else {
            let detail = parser.parserError?.localizedDescription
                ?? xml.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SubversionRepositoryInspectorError.invalidResponse(detail)
        }

        return detail
    }

    private func parseRepositoryBrowserListing(from xml: String) throws -> SVNRepositoryBrowserListing {
        let delegate = SubversionListXMLParserDelegate()
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let listing = delegate.listing else {
            let detail = parser.parserError?.localizedDescription
                ?? xml.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SubversionRepositoryInspectorError.invalidResponse(detail)
        }

        return listing
    }
}

private final class SubversionInfoXMLParserDelegate: NSObject, XMLParserDelegate {
    private let defaultWorkingCopyRoot: String
    private var repositoryURL: String?
    private var repositoryRootURL: String?
    private var workingCopyUUID: String?
    private var workingCopyRoot: String?
    private var revision: Int64?
    private var lastChangedRevision: Int64?
    private var lastChangedAuthor: String?
    private var isInsideRepository = false
    private var isInsideCommit = false
    private var textBuffer = ""

    var summary: SVNRepositorySummary?

    init(defaultWorkingCopyRoot: String) {
        self.defaultWorkingCopyRoot = defaultWorkingCopyRoot
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        switch elementName {
        case "entry":
            revision = attributeDict["revision"].flatMap(Int64.init)
        case "repository":
            isInsideRepository = true
        case "commit":
            isInsideCommit = true
            lastChangedRevision = attributeDict["revision"].flatMap(Int64.init)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            switch elementName {
            case "url":
                repositoryURL = text
            case "root" where isInsideRepository:
                repositoryRootURL = text
            case "uuid" where isInsideRepository:
                workingCopyUUID = text
            case "wcroot-abspath":
                workingCopyRoot = text
            case "author" where isInsideCommit:
                lastChangedAuthor = text
            default:
                break
            }
        }

        switch elementName {
        case "repository":
            isInsideRepository = false
        case "commit":
            isInsideCommit = false
        case "entry":
            if let repositoryURL, let revision {
                summary = SVNRepositorySummary(
                    workingCopyRoot: workingCopyRoot ?? defaultWorkingCopyRoot,
                    repositoryURL: repositoryURL,
                    repositoryRootURL: repositoryRootURL,
                    revision: revision,
                    lastChangedRevision: lastChangedRevision,
                    lastChangedAuthor: lastChangedAuthor,
                    workingCopyUUID: workingCopyUUID
                )
            }
        default:
            break
        }

        textBuffer = ""
    }
}

private final class SubversionLogXMLParserDelegate: NSObject, XMLParserDelegate {
    private var currentRevision: Int64?
    private var currentAuthor: String?
    private var currentDate: Date?
    private var currentMessage = ""
    private var textBuffer = ""

    var entries: [SVNHistoryEntry] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        if elementName == "logentry" {
            currentRevision = attributeDict["revision"].flatMap(Int64.init)
            currentAuthor = nil
            currentDate = nil
            currentMessage = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "author":
            currentAuthor = text.isEmpty ? nil : text
        case "date":
            currentDate = Self.parseDate(text)
        case "msg":
            currentMessage = text
        case "logentry":
            if let currentRevision {
                entries.append(
                    SVNHistoryEntry(
                        revision: currentRevision,
                        author: currentAuthor,
                        date: currentDate,
                        message: currentMessage
                    )
                )
            }
        default:
            break
        }

        textBuffer = ""
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsedDate = formatterWithFractionalSeconds.date(from: text) {
            return parsedDate
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: text)
    }
}

private final class SubversionVerboseLogXMLParserDelegate: NSObject, XMLParserDelegate {
    private var currentRevision: Int64?
    private var currentAuthor: String?
    private var currentDate: Date?
    private var currentMessage = ""
    private var changedPaths: [SVNHistoryChangedPath] = []
    private var pendingChangedPathAttributes: [String: String]?
    private var textBuffer = ""

    var detail: SVNHistoryEntryDetail?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        switch elementName {
        case "logentry":
            currentRevision = attributeDict["revision"].flatMap(Int64.init)
            currentAuthor = nil
            currentDate = nil
            currentMessage = ""
            changedPaths = []
        case "path":
            pendingChangedPathAttributes = attributeDict
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "author":
            currentAuthor = text.isEmpty ? nil : text
        case "date":
            currentDate = parseDate(text)
        case "msg":
            currentMessage = text
        case "path":
            if let attributes = pendingChangedPathAttributes, !text.isEmpty {
                changedPaths.append(
                    SVNHistoryChangedPath(
                        path: text,
                        action: attributes["action"] ?? "?",
                        kind: attributes["kind"],
                        textModified: parseBool(attributes["text-mods"]),
                        propertyModified: parseBool(attributes["prop-mods"])
                    )
                )
            }
            pendingChangedPathAttributes = nil
        case "logentry":
            if let currentRevision {
                detail = SVNHistoryEntryDetail(
                    entry: SVNHistoryEntry(
                        revision: currentRevision,
                        author: currentAuthor,
                        date: currentDate,
                        message: currentMessage
                    ),
                    changedPaths: changedPaths
                )
            }
        default:
            break
        }

        textBuffer = ""
    }

    private func parseDate(_ text: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsedDate = formatterWithFractionalSeconds.date(from: text) {
            return parsedDate
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: text)
    }

    private func parseBool(_ text: String?) -> Bool? {
        guard let text else {
            return nil
        }
        switch text.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}

private final class SubversionListXMLParserDelegate: NSObject, XMLParserDelegate {
    private var baseURL: String?
    private var currentKind: String?
    private var currentName: String?
    private var currentSize: Int64?
    private var currentRevision: Int64?
    private var currentAuthor: String?
    private var currentDate: Date?
    private var textBuffer = ""
    private var entries: [SVNRepositoryBrowserEntry] = []
    private var isInsideCommit = false

    var listing: SVNRepositoryBrowserListing?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        switch elementName {
        case "list":
            baseURL = attributeDict["path"]
        case "entry":
            currentKind = attributeDict["kind"]
            currentName = nil
            currentSize = nil
            currentRevision = nil
            currentAuthor = nil
            currentDate = nil
        case "commit":
            isInsideCommit = true
            currentRevision = attributeDict["revision"].flatMap(Int64.init)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "name":
            currentName = text
        case "size":
            currentSize = Int64(text)
        case "author" where isInsideCommit:
            currentAuthor = text.isEmpty ? nil : text
        case "date" where isInsideCommit:
            currentDate = parseDate(text)
        case "commit":
            isInsideCommit = false
        case "entry":
            if let baseURL, let currentName, let currentKind {
                entries.append(
                    SVNRepositoryBrowserEntry(
                        name: currentName,
                        fullURL: appendPathComponent(currentName, to: baseURL, isDirectory: currentKind == "dir"),
                        isDirectory: currentKind == "dir",
                        size: currentSize,
                        revision: currentRevision,
                        author: currentAuthor,
                        date: currentDate
                    )
                )
            }
        case "list":
            if let baseURL {
                let sortedEntries = entries.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                listing = SVNRepositoryBrowserListing(baseURL: baseURL, entries: sortedEntries)
            }
        default:
            break
        }

        textBuffer = ""
    }

    private func parseDate(_ text: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsedDate = formatterWithFractionalSeconds.date(from: text) {
            return parsedDate
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: text)
    }

    private func appendPathComponent(_ component: String, to baseURL: String, isDirectory: Bool) -> String {
        guard var url = URL(string: baseURL) else {
            return baseURL + "/" + component
        }
        url.appendPathComponent(component, isDirectory: isDirectory)
        return url.absoluteString
    }
}
