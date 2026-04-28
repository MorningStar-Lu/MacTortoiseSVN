import Cocoa
import FinderSync
import FinderSyncBridge
import OSLog
import StatusServiceXPC

private final class FinderMenuActionsBox: @unchecked Sendable {
    var actions: [FinderMenuActionDescriptor]

    init(actions: [FinderMenuActionDescriptor]) {
        self.actions = actions
    }
}

private struct FinderSelectionContext {
    var menuKind: FIMenuKind
    var selectedURLPaths: [String]
    var targetedPath: String?
    var candidatePaths: [String]
    var selectedPaths: [String]
    var rootPath: String?
}

@objc(FinderSyncExtension)
public final class FinderSyncExtension: FIFinderSync {
    private let logger = Logger(
        subsystem: "com.morningstar.MacTortoiseSVN.FinderSync",
        category: "extension"
    )
    private let finderController = FIFinderSyncController.default()
    private let statusClient = StatusServiceXPCClient()
    private let monitoredRootsStore = MacSVNMonitoredRootsStore()
    private let workbenchCommandStore = MacSVNWorkbenchCommandStore()
    private var cachedMonitoredRoots: [String] = []
    private var lastMenuSelectionContext: FinderSelectionContext?

    override init() {
        super.init()
        touchMarker(named: "event-init")
        diagnosticLog("init")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMonitoredRootsDidChange(_:)),
            name: MacSVNMonitoredRootsStore.distributedNotificationName,
            object: nil
        )
        DistributedNotificationCenter.default().post(
            name: MacSVNMonitoredRootsStore.distributedRequestNotificationName,
            object: nil
        )
        touchMarker(named: "event-roots-requested")
        registerKnownBadges()
        reloadMonitoredRoots()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    public override func beginObservingDirectory(at url: URL) {
        touchMarker(named: "event-beginObserving")
        diagnosticLog("beginObservingDirectory path=\(url.path)")
    }

    public override func endObservingDirectory(at url: URL) {
        touchMarker(named: "event-endObserving")
        diagnosticLog("endObservingDirectory path=\(url.path)")
    }

    public override func requestBadgeIdentifier(for url: URL) {
        touchMarker(named: "event-badge")
        diagnosticLog("requestBadgeIdentifier path=\(url.path)")
        let path = url.standardizedFileURL.path
        guard let rootPath = rootPathForURL(url) else {
            diagnosticLog("requestBadgeIdentifier skipped: no rootPath")
            return
        }

        let statusClient = self.statusClient
        Task { [statusClient] in
            let assignments = try? await statusClient.badgeAssignments(
                rootPath: rootPath,
                visiblePaths: [path]
            )
            guard let assignment = assignments?.first else {
                return
            }

            await MainActor.run {
                FIFinderSyncController.default().setBadgeIdentifier(
                    assignment.badgeIdentifier,
                    for: url
                )
            }
        }
    }

    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        touchMarker(named: "event-menu")
        let language = MacSVNLanguageStore().loadLanguage()
        let localizer = MacSVNLocalizer(language: language)
        let menu = NSMenu(title: localizer.finderMenuTitle)
        let context = resolvedSelectionContext(menuKind: menuKind)
        lastMenuSelectionContext = context
        diagnosticLog(
            "menu kind=\(menuKindDescription(menuKind)) raw=\(menuKind.rawValue) " +
            "selectedURLs=\(summarizePaths(context.selectedURLPaths)) " +
            "targeted=\(context.targetedPath ?? "nil") " +
            "candidates=\(summarizePaths(context.candidatePaths)) " +
            "selected=\(summarizePaths(context.selectedPaths)) " +
            "root=\(context.rootPath ?? "nil")"
        )

        guard context.rootPath != nil else {
            let fallbackItem = NSMenuItem(
                title: localizer.title(for: .openInWorkbench),
                action: #selector(handleOpenInWorkbenchMenuItem(_:)),
                keyEquivalent: ""
            )
            fallbackItem.target = self
            menu.addItem(fallbackItem)
            return menu
        }

        let resolvedActions = resolveMenuActions(for: context, language: language)
        diagnosticLog(
            "menu actions count=\(resolvedActions.count) states=" +
            resolvedActions
                .map { "\($0.command.rawValue)=\($0.isEnabled)" }
                .joined(separator: "|")
        )

        for action in resolvedActions {
            let item = NSMenuItem(
                title: action.title,
                action: selector(for: action.command),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = action.isEnabled
            menu.addItem(item)
        }
        return menu
    }

    @objc
    private func handleCommitSelectedMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.commitSelected, sender: sender)
    }

    @objc
    private func handleDiffSelectedMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.diffSelected, sender: sender)
    }

    @objc
    private func handleRefreshNowMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.refreshNow, sender: sender)
    }

    @objc
    private func handleOpenInWorkbenchMenuItem(_ sender: NSMenuItem) {
        handleMenuCommand(.openInWorkbench, sender: sender)
    }

    private func handleMenuCommand(_ command: FinderMenuCommand, sender: NSMenuItem) {
        diagnosticLog(
            "handleMenuItem invoked command=\(command.rawValue) title=\(sender.title)"
        )
        let context = lastMenuSelectionContext ?? resolvedSelectionContext(menuKind: .contextualMenuForItems)
        let selectedPaths = context.selectedPaths
        let rootPath = context.rootPath
        diagnosticLog(
            "handleMenuItem command=\(command.rawValue) selected=\(selectedPaths.count) root=\(rootPath ?? "nil")"
        )

        switch command {
        case .refreshNow:
            guard let rootPath else {
                return
            }
            let statusClient = self.statusClient
            Task { [statusClient] in
                _ = try? await statusClient.refresh(rootPath: rootPath, forceFullRefresh: true)
            }
        case .openInWorkbench, .commitSelected, .diffSelected:
            openHostApp(command: command, rootPath: rootPath, selectedPaths: selectedPaths)
        }
    }

    private func registerKnownBadges() {
        for badge in FinderBadgeKind.allCases {
            let imageName: NSImage.Name
            switch badge {
            case .modified, .descendantDirty:
                imageName = NSImage.Name("NSStatusPartiallyAvailable")
            case .added:
                imageName = NSImage.Name("NSStatusAvailable")
            case .deleted:
                imageName = NSImage.Name("NSStatusUnavailable")
            case .conflicted:
                imageName = NSImage.Name("NSCaution")
            case .unversioned:
                imageName = NSImage.Name("NSAddTemplate")
            }

            if let image = NSImage(named: imageName) {
                finderController.setBadgeImage(
                    image,
                    label: badge.badgeLabel,
                    forBadgeIdentifier: badge.badgeIdentifier
                )
            }
        }
    }

    @objc
    private func handleMonitoredRootsDidChange(_ notification: Notification) {
        if
            let roots = notification.userInfo?[MacSVNMonitoredRootsStore.distributedNotificationRootsKey] as? [String]
        {
            diagnosticLog("handleMonitoredRootsDidChange notifiedRoots=\(roots.count)")
            applyMonitoredRoots(roots)
            return
        }

        diagnosticLog("handleMonitoredRootsDidChange")
        reloadMonitoredRoots()
    }

    private func reloadMonitoredRoots() {
        applyMonitoredRoots(monitoredRootsStore.loadRoots())
    }

    private func applyMonitoredRoots(_ monitoredRoots: [String]) {
        let normalizedRoots = Array(
            Set(monitoredRoots.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        ).sorted()
        let directoryURLs = normalizedRoots.map(URL.init(fileURLWithPath:))
        cachedMonitoredRoots = normalizedRoots

        if normalizedRoots.isEmpty {
            touchMarker(named: "event-roots-empty")
        } else {
            touchMarker(named: "event-roots-configured")
        }

        diagnosticLog(
            "reloadMonitoredRoots roots=\(normalizedRoots.joined(separator: ",")) " +
            "effective=\(directoryURLs.map { $0.path }.joined(separator: ","))"
        )
        finderController.directoryURLs = Set(directoryURLs)
    }

    private func resolveMenuActions(
        for context: FinderSelectionContext,
        language: MacSVNLanguage
    ) -> [FinderMenuActionDescriptor] {
        let fallbackActions = fallbackMenuActions(
            selectedPaths: context.selectedPaths,
            rootPath: context.rootPath,
            language: language
        )

        guard
            let rootPath = context.rootPath,
            !context.selectedPaths.isEmpty
        else {
            return fallbackActions
        }

        let semaphore = DispatchSemaphore(value: 0)
        let actionsBox = FinderMenuActionsBox(actions: fallbackActions)
        let startedAt = DispatchTime.now()
        let statusClient = self.statusClient

        Task { [statusClient, actionsBox] in
            if let resolvedActions = try? await statusClient.menuActions(
                rootPath: rootPath,
                selectedPaths: context.selectedPaths
            ), !resolvedActions.isEmpty {
                actionsBox.actions = resolvedActions
            }
            semaphore.signal()
        }

        let didResolve = semaphore.wait(timeout: .now() + 1.2) == .success
        let elapsedMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
        )
        diagnosticLog(
            "menu resolution kind=\(menuKindDescription(context.menuKind)) " +
            "didResolve=\(didResolve) elapsedMs=\(elapsedMs)"
        )
        return actionsBox.actions
    }

    private func fallbackMenuActions(
        selectedPaths: [String],
        rootPath: String?,
        language: MacSVNLanguage
    ) -> [FinderMenuActionDescriptor] {
        let localizer = MacSVNLocalizer(language: language)
        let hasSelection = !selectedPaths.isEmpty
        let canOperate = hasSelection && rootPath != nil

        return [
            FinderMenuActionDescriptor(
                command: .commitSelected,
                title: localizer.title(for: .commitSelected),
                isEnabled: canOperate
            ),
            FinderMenuActionDescriptor(
                command: .diffSelected,
                title: localizer.title(for: .diffSelected),
                isEnabled: canOperate && selectedPaths.count <= 2
            ),
            FinderMenuActionDescriptor(
                command: .refreshNow,
                title: localizer.title(for: .refreshNow),
                isEnabled: rootPath != nil
            ),
            FinderMenuActionDescriptor(
                command: .openInWorkbench,
                title: localizer.title(for: .openInWorkbench)
            ),
        ]
    }

    private func resolvedSelectionContext(menuKind: FIMenuKind) -> FinderSelectionContext {
        let selectedURLs = (finderController.selectedItemURLs() ?? [])
            .map(\.standardizedFileURL)
        let targetedURL = finderController.targetedURL()?.standardizedFileURL

        let candidateURLs: [URL]
        if !selectedURLs.isEmpty {
            candidateURLs = selectedURLs
        } else if let targetedURL {
            candidateURLs = [targetedURL]
        } else {
            candidateURLs = []
        }

        let selectedPaths = candidateURLs.map(\.path)
        let rootPath = candidateURLs.first.flatMap(rootPathForURL(_:))

        return FinderSelectionContext(
            menuKind: menuKind,
            selectedURLPaths: selectedURLs.map(\.path),
            targetedPath: targetedURL?.path,
            candidatePaths: candidateURLs.map(\.path),
            selectedPaths: selectedPaths,
            rootPath: rootPath
        )
    }

    private func rootPathForURL(_ url: URL) -> String? {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.hasDirectoryPath
            ? standardizedURL.path
            : standardizedURL.deletingLastPathComponent().path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return cachedMonitoredRoots
            .filter { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    private func openHostApp(
        command: FinderMenuCommand,
        rootPath: String?,
        selectedPaths: [String]
    ) {
        guard let hostAppURL = hostAppURL() else {
            return
        }

        workbenchCommandStore.saveCommand(
            MacSVNWorkbenchCommand(
                command: command,
                rootPath: rootPath,
                selectedPaths: selectedPaths
            )
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bundleIdentifier = MacSVNXPCConstants.workbenchBundleIdentifier

        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            diagnosticLog("openHostApp activatingRunningApp bundleIdentifier=\(bundleIdentifier)")
            runningApp.activate(options: [.activateAllWindows])
        }

        let logger = self.logger
        NSWorkspace.shared.openApplication(at: hostAppURL, configuration: configuration) {
            runningApp, error in
            if let error {
                Self.diagnosticLog(
                    "openHostApp failed error=\(error.localizedDescription)",
                    logger: logger
                )
                return
            }

            Self.diagnosticLog(
                "openHostApp completed pid=\(runningApp?.processIdentifier ?? 0) " +
                "bundleIdentifier=\(runningApp?.bundleIdentifier ?? "nil")",
                logger: logger
            )
            runningApp?.activate(options: [.activateAllWindows])
        }
    }

    private func hostAppURL() -> URL? {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func diagnosticLog(_ message: String) {
        Self.diagnosticLog(message, logger: logger)
    }

    private static func diagnosticLog(_ message: String, logger: Logger) {
        logger.info("\(message, privacy: .public)")
        appendDiagnosticLine(message)
    }

    private static func appendDiagnosticLine(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let logURLs = [
            URL(fileURLWithPath: NSHomeDirectory()).appending(path: "finder-sync-debug.log"),
            URL(fileURLWithPath: "/tmp/mactortoisesvn-finder-sync-debug.log")
        ]

        for logURL in logURLs {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: logURL) else {
                continue
            }

            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
    }

    private func touchMarker(named name: String) {
        let markerURL = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: name)

        if FileManager.default.fileExists(atPath: markerURL.path) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: markerURL.path
            )
            return
        }

        _ = FileManager.default.createFile(atPath: markerURL.path, contents: Data())
    }

    private func menuKindDescription(_ menuKind: FIMenuKind) -> String {
        switch menuKind {
        case .contextualMenuForItems:
            return "items"
        case .contextualMenuForContainer:
            return "container"
        case .contextualMenuForSidebar:
            return "sidebar"
        case .toolbarItemMenu:
            return "toolbar"
        @unknown default:
            return "unknown"
        }
    }

    private func summarizePaths(_ paths: [String], limit: Int = 4) -> String {
        guard !paths.isEmpty else {
            return "[]"
        }

        let normalizedPaths = paths.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let displayed = normalizedPaths.prefix(limit).joined(separator: " | ")
        if normalizedPaths.count > limit {
            return "[\(displayed) | +\(normalizedPaths.count - limit) more]"
        }
        return "[\(displayed)]"
    }

    private func selector(for command: FinderMenuCommand) -> Selector {
        switch command {
        case .commitSelected:
            return #selector(handleCommitSelectedMenuItem(_:))
        case .diffSelected:
            return #selector(handleDiffSelectedMenuItem(_:))
        case .refreshNow:
            return #selector(handleRefreshNowMenuItem(_:))
        case .openInWorkbench:
            return #selector(handleOpenInWorkbenchMenuItem(_:))
        }
    }
}
