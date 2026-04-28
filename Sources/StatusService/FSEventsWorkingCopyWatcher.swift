import CoreServices
import Foundation

public actor FSEventsWorkingCopyWatcher: WorkingCopyEventWatching {
    private var eventHandler: (any WorkingCopyEventHandling)?
    private var streams: [String: FSEventStreamState] = [:]
    private let latency: CFTimeInterval
    private let coalescingWindowNanoseconds: UInt64
    private let maxBufferedPathsPerRoot: Int
    private var pendingEvents: [String: PendingWorkingCopyEvent] = [:]
    private var scheduledFlushRoots: Set<String> = []

    public init(
        latency: CFTimeInterval = 0.35,
        coalescingWindowNanoseconds: UInt64 = 300_000_000,
        maxBufferedPathsPerRoot: Int = 2_048
    ) {
        self.latency = latency
        self.coalescingWindowNanoseconds = coalescingWindowNanoseconds
        self.maxBufferedPathsPerRoot = maxBufferedPathsPerRoot
    }

    public func setEventHandler(_ handler: (any WorkingCopyEventHandling)?) async {
        self.eventHandler = handler
    }

    public func startMonitoring(rootPath: String) async throws {
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        guard streams[normalizedRoot] == nil else {
            return
        }

        let queue = DispatchQueue(
            label: "MacTortoiseSVN.FSEvents.\(normalizedRoot)",
            qos: .utility
        )
        let callbackBox = FSEventsCallbackBox(rootPath: normalizedRoot) { [weak self] event in
            guard let self else {
                return
            }

            Task {
                await self.consume(event: event)
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackBox).toOpaque(),
            retain: nil,
            release: fseventsContextRelease,
            copyDescription: nil
        )

        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fseventsCallback,
            &context,
            [normalizedRoot] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            createFlags
        )

        guard let stream else {
            throw StatusServiceWatcherError("Failed to create FSEvent stream for \(normalizedRoot)")
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw StatusServiceWatcherError("Failed to start FSEvent stream for \(normalizedRoot)")
        }

        streams[normalizedRoot] = FSEventStreamState(
            rootPath: normalizedRoot,
            stream: stream,
            queue: queue
        )
    }

    public func stopMonitoring(rootPath: String) async throws {
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        guard let state = streams.removeValue(forKey: normalizedRoot) else {
            return
        }

        pendingEvents.removeValue(forKey: normalizedRoot)
        scheduledFlushRoots.remove(normalizedRoot)
        FSEventStreamStop(state.stream)
        FSEventStreamInvalidate(state.stream)
        FSEventStreamRelease(state.stream)
    }

    private func consume(event: WorkingCopyFileSystemEvent) async {
        mergePending(event: event)
        guard scheduledFlushRoots.insert(event.rootPath).inserted else {
            return
        }

        let rootPath = event.rootPath
        let delay = coalescingWindowNanoseconds
        Task {
            try? await Task.sleep(nanoseconds: delay)
            await self.flushPendingEvent(for: rootPath)
        }
    }

    private func mergePending(event: WorkingCopyFileSystemEvent) {
        var pending = pendingEvents[event.rootPath] ?? PendingWorkingCopyEvent(rootPath: event.rootPath)
        pending.merge(event, maxBufferedPathsPerRoot: maxBufferedPathsPerRoot)
        pendingEvents[event.rootPath] = pending
    }

    private func flushPendingEvent(for rootPath: String) async {
        scheduledFlushRoots.remove(rootPath)

        guard
            let eventHandler,
            let pending = pendingEvents.removeValue(forKey: rootPath)
        else {
            return
        }

        await eventHandler.handle(event: pending.asEvent)
    }

    deinit {
        for state in streams.values {
            FSEventStreamStop(state.stream)
            FSEventStreamInvalidate(state.stream)
            FSEventStreamRelease(state.stream)
        }
    }
}

public struct StatusServiceWatcherError: Error, Sendable, LocalizedError, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

private final class FSEventStreamState: @unchecked Sendable {
    let rootPath: String
    let stream: FSEventStreamRef
    let queue: DispatchQueue

    init(rootPath: String, stream: FSEventStreamRef, queue: DispatchQueue) {
        self.rootPath = rootPath
        self.stream = stream
        self.queue = queue
    }
}

private final class FSEventsCallbackBox {
    let rootPath: String
    let onEvent: @Sendable (WorkingCopyFileSystemEvent) -> Void

    init(
        rootPath: String,
        onEvent: @escaping @Sendable (WorkingCopyFileSystemEvent) -> Void
    ) {
        self.rootPath = rootPath
        self.onEvent = onEvent
    }

    func emit(paths: [String], flags: [FSEventStreamEventFlags]) {
        let requiresFullRefresh = flags.contains(where: requiresFullRefresh(for:))
        if requiresFullRefresh || paths.isEmpty {
            onEvent(.fullRefresh(rootPath: rootPath))
            return
        }

        let normalizedPaths = Array(
            Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        ).sorted()
        onEvent(.incremental(rootPath: rootPath, changedPaths: normalizedPaths))
    }

    private func requiresFullRefresh(for flags: FSEventStreamEventFlags) -> Bool {
        let mask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagMount |
            kFSEventStreamEventFlagUnmount |
            kFSEventStreamEventFlagEventIdsWrapped
        )
        return (flags & mask) != 0
    }
}

private struct PendingWorkingCopyEvent {
    let rootPath: String
    var requiresFullRefresh = false
    var changedPaths: Set<String> = []

    var asEvent: WorkingCopyFileSystemEvent {
        if requiresFullRefresh {
            return .fullRefresh(rootPath: rootPath)
        }
        return .incremental(rootPath: rootPath, changedPaths: changedPaths.sorted())
    }

    mutating func merge(
        _ event: WorkingCopyFileSystemEvent,
        maxBufferedPathsPerRoot: Int
    ) {
        if requiresFullRefresh || event.scope == .fullRefresh {
            requiresFullRefresh = true
            changedPaths.removeAll(keepingCapacity: false)
            return
        }

        changedPaths.formUnion(event.changedPaths)
        if changedPaths.count > maxBufferedPathsPerRoot {
            requiresFullRefresh = true
            changedPaths.removeAll(keepingCapacity: false)
        }
    }
}

private let fseventsCallback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPathsPointer, eventFlagsPointer, _ in
    guard let clientCallBackInfo else {
        return
    }

    let callbackBox = Unmanaged<FSEventsCallbackBox>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    let paths = Unmanaged<NSArray>
        .fromOpaque(eventPathsPointer)
        .takeUnretainedValue() as? [String] ?? []
    let flags = Array(
        UnsafeBufferPointer(start: eventFlagsPointer, count: Int(numEvents))
    )

    callbackBox.emit(paths: paths, flags: flags)
}

private let fseventsContextRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else {
        return
    }
    Unmanaged<FSEventsCallbackBox>.fromOpaque(info).release()
}
