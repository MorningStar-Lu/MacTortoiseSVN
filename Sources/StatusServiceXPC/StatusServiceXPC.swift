import CoreTypes
import FinderSyncBridge
import Foundation
import StatusService
import SVNCore

public enum MacSVNXPCConstants {
    public static let workbenchBundleIdentifier = "com.morningstar.MacTortoiseSVN"
    public static let statusServiceIdentifier = "com.morningstar.MacTortoiseSVN.StatusService"
}

public struct MacSVNRuntimePaths: Sendable, Hashable {
    public var workspaceRootURL: URL
    public var bundleURL: URL
    public var resourceRootURL: URL?

    public init(
        workspaceRootURL: URL,
        bundleURL: URL = Bundle.main.bundleURL,
        resourceRootURL: URL? = Bundle.main.resourceURL
    ) {
        self.workspaceRootURL = workspaceRootURL
        self.bundleURL = bundleURL
        self.resourceRootURL = resourceRootURL
    }

    public static func currentProcess() -> MacSVNRuntimePaths {
        MacSVNRuntimePaths(workspaceRootURL: defaultWorkspaceRootURL())
    }

    public var bundledRustBinaryURL: URL? {
        guard let resourceRootURL else {
            return nil
        }
        return resourceRootURL.appending(path: "bin").appending(path: "mtsvn-rs")
    }

    public var hasBundledRustBinary: Bool {
        guard let bundledRustBinaryURL else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: bundledRustBinaryURL.path)
    }

    public var bundledStatusServiceURL: URL {
        bundleURL
            .appending(path: "Contents")
            .appending(path: "XPCServices")
            .appending(path: "\(MacSVNXPCConstants.statusServiceIdentifier).xpc")
    }

    public var hasBundledStatusService: Bool {
        FileManager.default.fileExists(atPath: bundledStatusServiceURL.path)
    }

    public var bridgeConfiguration: RustBridgeConfiguration {
        if hasBundledRustBinary, let resourceRootURL {
            return RustBridgeConfiguration(
                repositoryRoot: resourceRootURL.path,
                rustWorkspaceRelativePath: ".",
                rustBinaryRelativePath: "bin/mtsvn-rs",
                preferBuiltBinary: true
            )
        }

        return RustBridgeConfiguration(
            repositoryRoot: workspaceRootURL.path,
            rustBinaryRelativePath: "rust/target/debug/mtsvn-rs",
            preferBuiltBinary: true
        )
    }

    public func statusServiceConfiguration(repositoryRoot: String) -> StatusServiceConfiguration {
        let base = StatusServiceConfiguration.development(repositoryRoot: repositoryRoot)
        return StatusServiceConfiguration(
            repositoryRoot: repositoryRoot,
            databaseURL: base.databaseURL,
            maxIncrementalDirtyPaths: base.maxIncrementalDirtyPaths,
            bridgeConfiguration: bridgeConfiguration,
            clientConfiguration: base.clientConfiguration,
            statusCenterConfiguration: base.statusCenterConfiguration
        )
    }

    static func defaultWorkspaceRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

public enum StatusServiceXPCError: Error, LocalizedError {
    case invalidRequest(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            return message
        case let .invalidResponse(message):
            return message
        }
    }
}

@objc public protocol StatusServiceXPCProtocol {
    func handleStatusServiceRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    )
    func handleFinderBadgeRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    )
    func handleFinderMenuRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    )
}

public final class StatusServiceXPCServer: NSObject, StatusServiceXPCProtocol {
    private let coordinator = StatusServiceXPCCoordinator()

    public func handleStatusServiceRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    ) {
        let payload = requestData as Data
        let coordinator = self.coordinator
        Task {
            do {
                let request = try JSONDecoder().decode(StatusServiceRequest.self, from: payload)
                let response = try await coordinator.handle(request)
                reply(try JSONEncoder().encode(response) as NSData, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    public func handleFinderBadgeRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    ) {
        let payload = requestData as Data
        let coordinator = self.coordinator
        Task {
            do {
                let request = try JSONDecoder().decode(FinderBadgeRequest.self, from: payload)
                let response = try await coordinator.badgeResponse(for: request)
                reply(try JSONEncoder().encode(response) as NSData, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }
    }

    public func handleFinderMenuRequest(
        _ requestData: NSData,
        withReply reply: @escaping @Sendable (NSData?, NSError?) -> Void
    ) {
        let payload = requestData as Data
        let coordinator = self.coordinator
        Task {
            do {
                let request = try JSONDecoder().decode(FinderMenuRequest.self, from: payload)
                let response = try await coordinator.menuResponse(for: request)
                reply(try JSONEncoder().encode(response) as NSData, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }
    }
}

public final class StatusServiceXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let server = StatusServiceXPCServer()

    public override init() {
        super.init()
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: StatusServiceXPCProtocol.self)
        newConnection.exportedObject = server
        newConnection.resume()
        return true
    }
}

actor StatusServiceXPCCoordinator {
    private let runtimePaths: MacSVNRuntimePaths
    private let badgeResolver = FinderBadgeResolver()
    private let menuBuilder = FinderContextMenuBuilder()
    private var hosts: [String: StatusServiceHost]

    init(runtimePaths: MacSVNRuntimePaths = .currentProcess()) {
        self.runtimePaths = runtimePaths
        self.hosts = [:]
    }

    func handle(_ request: StatusServiceRequest) async throws -> StatusServiceResponse {
        let rootPath = try normalizedRootPath(from: request.rootPath)
        let host = try host(for: rootPath)
        let processor = StatusServiceCommandProcessor(host: host)

        var resolvedRequest = request
        resolvedRequest.rootPath = rootPath
        return await processor.handle(resolvedRequest)
    }

    func badgeResponse(for request: FinderBadgeRequest) async throws -> FinderBadgeResponse {
        let rootPath = try normalizedRootPath(from: request.rootPath)
        let snapshot = try await snapshotForFinder(rootPath: rootPath)
        guard let snapshot else {
            return FinderBadgeResponse(assignments: [])
        }

        return FinderBadgeResponse(
            assignments: badgeResolver.assignments(
                for: request.visiblePaths,
                snapshot: snapshot
            )
        )
    }

    func menuResponse(for request: FinderMenuRequest) async throws -> FinderMenuResponse {
        let rootPath = try normalizedRootPath(from: request.rootPath)
        let snapshot = try await snapshotForFinder(rootPath: rootPath)

        return FinderMenuResponse(
            actions: menuBuilder.actions(
                for: request.selectedPaths,
                snapshot: snapshot
            )
        )
    }

    private func snapshotForFinder(rootPath: String) async throws -> BadgeSnapshot? {
        let host = try host(for: rootPath)
        if let snapshot = try await host.snapshot(for: rootPath) {
            return snapshot
        }
        return try await host.refreshIfNeeded(rootPath: rootPath)
    }

    private func host(for rootPath: String) throws -> StatusServiceHost {
        if let host = hosts[rootPath] {
            return host
        }

        let host = try StatusServiceHost(
            configuration: runtimePaths.statusServiceConfiguration(repositoryRoot: rootPath)
        )
        hosts[rootPath] = host
        return host
    }

    private func normalizedRootPath(from rootPath: String?) throws -> String {
        guard let rootPath else {
            throw StatusServiceXPCError.invalidRequest(
                "XPC requests must include a repository root path."
            )
        }

        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StatusServiceXPCError.invalidRequest(
                "Repository root path cannot be empty."
            )
        }

        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory) else {
            throw StatusServiceXPCError.invalidRequest(
                "Repository root path does not exist: \(normalized)"
            )
        }
        guard isDirectory.boolValue else {
            throw StatusServiceXPCError.invalidRequest(
                "Repository root path is not a directory: \(normalized)"
            )
        }
        return normalized
    }
}

public actor StatusServiceXPCClient {
    private let connectionBox: StatusServiceXPCConnectionBox
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(serviceName: String = MacSVNXPCConstants.statusServiceIdentifier) {
        self.connectionBox = StatusServiceXPCConnectionBox(serviceName: serviceName)
    }

    public static func isBundledServiceAvailable(bundle: Bundle = .main) -> Bool {
        MacSVNRuntimePaths(
            workspaceRootURL: MacSVNRuntimePaths.defaultWorkspaceRootURL(),
            bundleURL: bundle.bundleURL,
            resourceRootURL: bundle.resourceURL
        ).hasBundledStatusService
    }

    public func startMonitoring(rootPath: String) async throws {
        let response = try await handle(
            StatusServiceRequest(method: .startMonitoring, rootPath: rootPath)
        )
        guard response.ok else {
            throw StatusServiceXPCError.invalidResponse(
                response.error ?? "Start monitoring failed."
            )
        }
    }

    public func stopMonitoring(rootPath: String) async throws {
        let response = try await handle(
            StatusServiceRequest(method: .stopMonitoring, rootPath: rootPath)
        )
        guard response.ok else {
            throw StatusServiceXPCError.invalidResponse(
                response.error ?? "Stop monitoring failed."
            )
        }
    }

    public func refresh(rootPath: String, forceFullRefresh: Bool) async throws -> BadgeSnapshot {
        let response = try await handle(
            StatusServiceRequest(
                method: .refresh,
                rootPath: rootPath,
                forceFullRefresh: forceFullRefresh
            )
        )
        guard response.ok, let snapshot = response.snapshot else {
            throw StatusServiceXPCError.invalidResponse(
                response.error ?? "Refresh did not return a snapshot."
            )
        }
        return snapshot
    }

    public func refreshIfNeeded(rootPath: String) async throws -> BadgeSnapshot {
        let response = try await handle(
            StatusServiceRequest(method: .refreshIfNeeded, rootPath: rootPath)
        )
        guard response.ok, let snapshot = response.snapshot else {
            throw StatusServiceXPCError.invalidResponse(
                response.error ?? "Refresh did not return a snapshot."
            )
        }
        return snapshot
    }

    public func snapshot(rootPath: String) async throws -> BadgeSnapshot? {
        let response = try await handle(
            StatusServiceRequest(method: .snapshot, rootPath: rootPath)
        )
        guard response.ok else {
            throw StatusServiceXPCError.invalidResponse(
                response.error ?? "Snapshot request failed."
            )
        }
        return response.snapshot
    }

    public func badgeAssignments(
        rootPath: String,
        visiblePaths: [String]
    ) async throws -> [FinderBadgeAssignment] {
        let response: FinderBadgeResponse = try await sendRequest(
            FinderBadgeRequest(rootPath: rootPath, visiblePaths: visiblePaths)
        ) { proxy, payload, reply in
            proxy.handleFinderBadgeRequest(payload, withReply: reply)
        }
        return response.assignments
    }

    public func menuActions(
        rootPath: String,
        selectedPaths: [String]
    ) async throws -> [FinderMenuActionDescriptor] {
        let response: FinderMenuResponse = try await sendRequest(
            FinderMenuRequest(rootPath: rootPath, selectedPaths: selectedPaths)
        ) { proxy, payload, reply in
            proxy.handleFinderMenuRequest(payload, withReply: reply)
        }
        return response.actions
    }

    public func handle(_ request: StatusServiceRequest) async throws -> StatusServiceResponse {
        try await sendRequest(request) { proxy, payload, reply in
            proxy.handleStatusServiceRequest(payload, withReply: reply)
        }
    }

    private func sendRequest<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: Request,
        invoke: @escaping (
            StatusServiceXPCProtocol,
            NSData,
            @escaping @Sendable (NSData?, NSError?) -> Void
        ) -> Void
    ) async throws -> Response {
        let requestData = try encoder.encode(request) as NSData
        return try await withCheckedThrowingContinuation { continuation in
            guard
                let proxy = connectionBox.connection.remoteObjectProxyWithErrorHandler({ error in
                    continuation.resume(throwing: error)
                }) as? StatusServiceXPCProtocol
            else {
                continuation.resume(
                    throwing: StatusServiceXPCError.invalidResponse(
                        "Failed to create XPC proxy."
                    )
                )
                return
            }

            invoke(proxy, requestData) { responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let responseData else {
                    continuation.resume(
                        throwing: StatusServiceXPCError.invalidResponse(
                            "XPC reply did not include a payload."
                        )
                    )
                    return
                }

                do {
                    continuation.resume(
                        returning: try self.decoder.decode(Response.self, from: responseData as Data)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class StatusServiceXPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(serviceName: String) {
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: StatusServiceXPCProtocol.self)
        connection.resume()
        self.connection = connection
    }

    deinit {
        connection.invalidate()
    }
}
