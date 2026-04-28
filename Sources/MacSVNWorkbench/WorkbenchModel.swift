import AppKit
import CoreTypes
import FinderSyncBridge
import Foundation
import IntegrationKit
import StatusService
import StatusServiceXPC
import SVNCore
import SwiftUI

@MainActor
final class WorkbenchModel: NSObject, ObservableObject {
    private static let lastWorkingCopyDefaultsKey = "MacSVNLastWorkingCopyRoot"

    enum DiffPreviewMode: String, CaseIterable, Identifiable {
        case workingCopy
        case historyRevision

        var id: String {
            rawValue
        }
    }

    private enum DiffPreviewRequestKey: Hashable {
        case workingCopy(
            rootPath: String,
            targetPath: String,
            status: VersionControlStatus,
            propertyModified: Bool
        )
        case historyRevision(rootPath: String, revision: Int64)
    }

    struct Entry: Identifiable, Hashable {
        let item: WorkingCopyItem
        let relativePath: String

        var id: String { item.path }
        var status: VersionControlStatus { item.status }
        var isDirectory: Bool { item.isDirectory }
        var isActionable: Bool { item.status.isDirty || item.status == .unversioned || item.propertyModified }
        var canAdd: Bool { item.status == .unversioned }
        var canCommit: Bool { item.status.isDirty || item.propertyModified }
        var canRevert: Bool { item.status.isDirty || item.propertyModified }
        var canResolve: Bool { item.status == .conflicted }
        var canLock: Bool { item.status != .unversioned && item.status != .locked }
        var canUnlock: Bool { item.status == .locked }
        var canRename: Bool { item.status != .unversioned }
        var canBlame: Bool { item.status != .unversioned && !isDirectory }
        var canCreatePatch: Bool { item.status.isDirty }
        var canShowProperties: Bool { item.status != .unversioned }
        var canShowLog: Bool { item.status != .unversioned }
    }

    @Published var rootPath: String
    @Published var commitMessage = ""
    @Published var language: MacSVNLanguage {
        didSet {
            if oldValue != language {
                languageStore.saveLanguage(language)
            }
        }
    }
    @Published private(set) var entries: [Entry] = []
    @Published var treeNodes: [ChangeTreeNode] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var badgeEntryCount = 0
    @Published private(set) var dirtyCount = 0
    @Published private(set) var unversionedCount = 0
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var repositorySummary: SVNRepositorySummary?
    @Published private(set) var repositoryBrowserListing: SVNRepositoryBrowserListing?
    @Published private(set) var repositoryBrowserRootURL: String?
    @Published private(set) var repositoryBrowserWorkingCopyURL: String?
    @Published private(set) var isLoadingRepositoryBrowser = false
    @Published private(set) var repositoryBrowserError: String?
    @Published private(set) var selectedRepositoryBrowserEntry: SVNRepositoryBrowserEntry?
    @Published private(set) var repositoryBrowserPreviewText: String?
    @Published private(set) var repositoryBrowserPreviewMessage: String?
    @Published private(set) var repositoryBrowserPreviewError: String?
    @Published private(set) var isLoadingRepositoryBrowserPreview = false
    @Published private(set) var recentHistory: [SVNHistoryEntry] = []
    @Published private(set) var recentHistoryError: String?
    @Published private(set) var selectedHistoryRevision: Int64?
    @Published private(set) var selectedHistoryEntryDetail: SVNHistoryEntryDetail?
    @Published private(set) var isLoadingHistoryDetail = false
    @Published var preferredDiffPreviewMode: DiffPreviewMode = .workingCopy
    @Published private(set) var selectedDiffText: String?
    @Published private(set) var isLoadingDiffPreview = false
    @Published private(set) var diffPreviewMessage: String?
    @Published private(set) var diffPreviewError: String?
    @Published private(set) var isLaunchingExternalDiff = false
    @Published private(set) var statusNotice: WorkbenchNotice
    @Published private(set) var lastError: String?
    @Published private(set) var externalTools: [ExternalToolProfile] = []
    @Published var refreshStatusAfterCommit = true
    @Published private(set) var isRunningWorkspaceOperation = false
    @Published var defaultWindowPreset: WorkbenchWindowPreset {
        didSet {
            guard oldValue != defaultWindowPreset else {
                return
            }
            savePresentationPreferences()
            requestWindowPresentationRefresh()
        }
    }
    @Published var hideDiffPreviewInCompactWindow: Bool {
        didSet {
            guard oldValue != hideDiffPreviewInCompactWindow else {
                return
            }
            savePresentationPreferences()
        }
    }
    @Published private(set) var windowPresentationRevision = UUID()

    enum NavigationItem: String, CaseIterable, Identifiable {
        case changes
        case repoBrowser
        case history

        var id: String { rawValue }
    }

    @Published var activeNavigation: NavigationItem = .changes
    @Published var bookmarks: [WorkspaceBookmark] = []
    @Published var visibilityPrefs: WorkbenchPresentationPreferences {
        didSet {
            guard oldValue != visibilityPrefs else { return }
            if isSidebarVisible != visibilityPrefs.showSidebar {
                isSidebarVisible = visibilityPrefs.showSidebar
            }
            savePresentationPreferences()
        }
    }
    @Published var isSidebarVisible = true {
        didSet {
            guard oldValue != isSidebarVisible else { return }
            if visibilityPrefs.showSidebar != isSidebarVisible {
                visibilityPrefs.showSidebar = isSidebarVisible
                return
            }
            savePresentationPreferences()
        }
    }

    @Published private(set) var blameLines: [BlameLine] = []
    @Published private(set) var isLoadingBlame = false
    @Published private(set) var blameError: String?
    @Published var isBlamePresented = false
    @Published var blameTargetPath: String?

    @Published private(set) var propertyList: [SVNPropertyEntry] = []
    @Published private(set) var isLoadingProperties = false
    @Published private(set) var propertiesError: String?
    @Published var isPropertiesPresented = false
    @Published var propertiesTargetPath: String?

    @Published var isRenamePresented = false
    @Published var renameTargetPath: String?
    @Published var renameNewName = ""

    private var host: StatusServiceHost?
    private var xpcClient: StatusServiceXPCClient?
    private var client: RustCommandBridgeSVNClient?
    private var workspaceOperator: SubversionWorkspaceOperator?
    private var repositoryInspector: SubversionRepositoryInspector?
    private var diffInspector: SubversionDiffInspector?
    private var hasQueuedRefresh = false
    private var queuedRefreshNeedsFullRescan = false
    private var configuredRootPath: String?
    private var pendingWorkbenchCommand: MacSVNWorkbenchCommand?
    private var lastHandledWorkbenchCommandID: UUID?
    private let runtimePaths: MacSVNRuntimePaths
    private let languageStore = MacSVNLanguageStore()
    private let monitoredRootsStore = MacSVNMonitoredRootsStore()
    private let workbenchCommandStore = MacSVNWorkbenchCommandStore()
    private let presentationPreferencesStore = WorkbenchPresentationPreferencesStore()
    private let bookmarkStore = WorkspaceBookmarkStore()
    private let registry = ExternalToolRegistry()
    private let externalToolLauncher = ExternalToolLauncher()
    private let runner = ProcessSubversionRunner()
    private var entryByPath: [String: Entry] = [:]
    private var diffPreviewTask: Task<Void, Never>?
    private var repositoryBrowserPreviewTask: Task<Void, Never>?
    private var lastDiffPreviewRequest: DiffPreviewRequestKey?
    private let externalDiffArtifactsRootURL: URL
    private var externalDiffArtifactDirectories: [URL] = []

    override init() {
        let initialCommand = MacSVNWorkbenchCommandStore().loadCommand()
        let initialRoot = initialCommand?.rootPath
            ?? CommandLine.arguments.dropFirst().first
            ?? UserDefaults.standard.string(forKey: Self.lastWorkingCopyDefaultsKey)
            ?? MacSVNMonitoredRootsStore().loadRoots().first
            ?? ""
        let initialLanguage = MacSVNLanguageStore().loadLanguage()
        let initialPresentationPreferences = WorkbenchPresentationPreferencesStore().load()
        self.rootPath = initialRoot
        self.language = initialLanguage
        self.defaultWindowPreset = initialPresentationPreferences.defaultWindowPreset
        self.hideDiffPreviewInCompactWindow = initialPresentationPreferences.hideDiffPreviewInCompactWindow
        self.visibilityPrefs = initialPresentationPreferences
        self.isSidebarVisible = initialPresentationPreferences.showSidebar
        self.bookmarks = WorkspaceBookmarkStore().load()
        self.runtimePaths = MacSVNRuntimePaths.currentProcess()
        self.statusNotice = .chooseWorkingCopyPrompt
        self.pendingWorkbenchCommand = initialCommand
        self.externalDiffArtifactsRootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacTortoiseSVN-ExternalDiff")
            .appending(path: UUID().uuidString)
        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMonitoredRootsRequest(_:)),
            name: MacSVNMonitoredRootsStore.distributedRequestNotificationName,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWorkbenchCommandDidChange(_:)),
            name: MacSVNWorkbenchCommandStore.distributedNotificationName,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        diagnosticLog(
            "init initialRoot=\(initialRoot) initialCommand=\(initialCommand?.command.rawValue ?? "nil")"
        )
        if let initialCommand {
            statusNotice = .processingFinderCommand(
                command: initialCommand.command,
                pathCount: max(initialCommand.selectedPaths.count, 1)
            )
        }

        if !initialRoot.isEmpty {
            broadcastCurrentMonitoredRoot()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.broadcastCurrentMonitoredRoot()
            }
            requestRefresh(forceFullRefresh: initialCommand != nil)
        }

        Task {
            externalTools = await registry.bootstrapDefaultProfiles()
        }
    }

    var selectedCount: Int {
        selectedPaths.count
    }

    var selectedEntries: [Entry] {
        selectedPaths.compactMap { entryByPath[$0] }
            .sorted { lhs, rhs in
                lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
    }

    var primarySelectedEntry: Entry? {
        selectedEntries.first
    }

    var selectedHistoryEntry: SVNHistoryEntry? {
        guard let selectedHistoryRevision else {
            return nil
        }

        return recentHistory.first(where: { $0.revision == selectedHistoryRevision })
    }

    var availableDiffPreviewModes: [DiffPreviewMode] {
        var modes: [DiffPreviewMode] = []
        if primarySelectedEntry != nil {
            modes.append(.workingCopy)
        }
        if selectedHistoryRevision != nil {
            modes.append(.historyRevision)
        }
        return modes
    }

    var effectiveDiffPreviewMode: DiffPreviewMode? {
        if availableDiffPreviewModes.contains(preferredDiffPreviewMode) {
            return preferredDiffPreviewMode
        }

        return availableDiffPreviewModes.first
    }

    var preferredWindowContentSize: CGSize {
        defaultWindowPreset.defaultContentSize
    }

    var canRefresh: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canUpdateWorkingCopy: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canCleanupWorkingCopy: Bool {
        !normalizedRootInput.isEmpty && !isBusy
    }

    var canAddSelected: Bool {
        selectedEntries.contains(where: \.canAdd) && !isBusy
    }

    var canCommitSelected: Bool {
        selectedEntries.contains(where: \.canCommit)
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    var canRevertSelected: Bool {
        selectedEntries.contains(where: \.canRevert) && !isBusy
    }

    var canResolveSelected: Bool {
        selectedEntries.contains(where: \.canResolve) && !isBusy
    }

    var isBusy: Bool {
        isRefreshing || isRunningWorkspaceOperation
    }

    var canBrowseRepositoryRoot: Bool {
        repositoryBrowserRootURL != nil && !isLoadingRepositoryBrowser
    }

    var canBrowseWorkingCopyLocation: Bool {
        repositoryBrowserWorkingCopyURL != nil && !isLoadingRepositoryBrowser
    }

    var canBrowseParentRepositoryDirectory: Bool {
        repositoryBrowserParentURL != nil && !isLoadingRepositoryBrowser
    }

    var repositoryBrowserCurrentURLText: String {
        repositoryBrowserListing?.baseURL ?? localizer.repositoryBrowserEmptyDescription
    }

    var repositoryBrowserParentURL: String? {
        guard
            let currentURLString = repositoryBrowserListing?.baseURL,
            let currentURL = URL(string: currentURLString),
            let rootURLString = repositoryBrowserRootURL,
            let rootURL = URL(string: rootURLString)
        else {
            return nil
        }

        let normalizedCurrent = currentURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedRoot = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedCurrent != normalizedRoot else {
            return nil
        }

        let parentURL = currentURL.deletingLastPathComponent()
        let normalizedParent = parentURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard normalizedParent.count >= normalizedRoot.count else {
            return nil
        }
        guard normalizedParent.hasPrefix(normalizedRoot) else {
            return nil
        }
        return parentURL.absoluteString
    }

    var externalToolSummary: String {
        if externalTools.isEmpty {
            return localizer.loadingDiffProfiles
        }

        return externalTools.map(\.displayName).joined(separator: "  |  ")
    }

    var statusMessage: String {
        statusNotice.text(using: localizer)
    }

    var localizer: MacSVNLocalizer {
        MacSVNLocalizer(language: language)
    }

    func applyPreferredWindowPresentation(to window: NSWindow) {
        window.title = localizer.appTitle
        window.minSize = CGSize(width: 780, height: 560)
        window.setContentSize(preferredWindowContentSize)
    }

    func requestWindowPresentationRefresh() {
        windowPresentationRevision = UUID()
    }

    func chooseWorkingCopy() {
        let panel = NSOpenPanel()
        panel.message = localizer.chooseWorkingCopyPanelMessage
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
        }
    }

    func toggleSelection(for path: String) {
        guard entryByPath[path]?.isActionable == true else {
            return
        }

        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }

        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func setSelection(for paths: [String], isSelected: Bool) {
        let normalizedPaths = Set(paths.filter { entryByPath[$0]?.isActionable == true })
        guard !normalizedPaths.isEmpty else {
            return
        }

        if isSelected {
            selectedPaths.formUnion(normalizedPaths)
        } else {
            selectedPaths.subtract(normalizedPaths)
        }

        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func selectAllActionable() {
        selectedPaths = Set(entryByPath.values.lazy.filter(\.isActionable).map(\.id))
        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview()
    }

    func clearSelection() {
        selectedPaths.removeAll()
        refreshDiffPreview()
    }

    func refreshSnapshot(forceFullRefresh: Bool) {
        requestRefresh(forceFullRefresh: forceFullRefresh)
    }

    func toggleMonitoring() {
        Task {
            await performToggleMonitoring()
        }
    }

    func addSelected() {
        Task {
            await performAddSelected()
        }
    }

    func updateWorkingCopy() {
        Task {
            await performUpdateWorkingCopy()
        }
    }

    func revertSelected() {
        let revertablePaths = collapsedPaths(
            selectedEntries.filter(\.canRevert).map(\.id)
        )
        guard !revertablePaths.isEmpty else {
            lastError = localizer.selectModifiedToRevertError
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmRevertTitle
        alert.informativeText = localizer.confirmRevertMessage(pathCount: revertablePaths.count)
        alert.addButton(withTitle: localizer.confirmRevertButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performRevertSelected(paths: revertablePaths)
        }
    }

    func cleanupWorkingCopy() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmCleanupTitle
        alert.informativeText = localizer.confirmCleanupMessage
        alert.addButton(withTitle: localizer.confirmCleanupButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performCleanupWorkingCopy()
        }
    }

    func resolveSelected() {
        let resolvablePaths = collapsedPaths(
            selectedEntries.filter(\.canResolve).map(\.id)
        )
        guard !resolvablePaths.isEmpty else {
            lastError = localizer.selectConflictedToResolveError
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmResolveTitle
        alert.informativeText = localizer.confirmResolveMessage(pathCount: resolvablePaths.count)
        alert.addButton(withTitle: localizer.confirmResolveButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performResolveSelected(paths: resolvablePaths)
        }
    }

    func commitSelected() {
        Task {
            await performCommitSelected()
        }
    }

    func showHistoryDetail(for revision: Int64) {
        preferredDiffPreviewMode = .historyRevision
        Task {
            await loadHistoryDetail(for: revision)
        }
    }

    func setPreferredDiffPreviewMode(_ mode: DiffPreviewMode) {
        preferredDiffPreviewMode = mode
        refreshDiffPreview(forceReload: true)
    }

    func browseRepositoryRoot() {
        guard let repositoryBrowserRootURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserRootURL)
        }
    }

    func browseWorkingCopyRepositoryLocation() {
        guard let repositoryBrowserWorkingCopyURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserWorkingCopyURL)
        }
    }

    func browseParentRepositoryDirectory() {
        guard let repositoryBrowserParentURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: repositoryBrowserParentURL)
        }
    }

    func refreshRepositoryBrowser() {
        guard let currentURL = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: currentURL)
        }
    }

    func openRepositoryBrowserEntry(_ entry: SVNRepositoryBrowserEntry) {
        guard entry.isDirectory else {
            return
        }
        Task {
            await loadRepositoryBrowserListing(url: entry.fullURL)
        }
    }

    func selectRepositoryBrowserEntry(_ entry: SVNRepositoryBrowserEntry) {
        if entry.isDirectory {
            openRepositoryBrowserEntry(entry)
            return
        }

        Task {
            await loadRepositoryBrowserFilePreview(for: entry)
        }
    }

    func openCurrentRepositoryBrowserLocationInBrowser() {
        guard let urlString = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        openRepositoryURLInBrowser(urlString)
    }

    func copyCurrentRepositoryBrowserLocation() {
        guard let urlString = repositoryBrowserListing?.baseURL ?? repositoryBrowserWorkingCopyURL else {
            return
        }
        copyRepositoryURL(urlString)
    }

    func openRepositoryBrowserEntryInBrowser(_ entry: SVNRepositoryBrowserEntry) {
        openRepositoryURLInBrowser(entry.fullURL)
    }

    func copyRepositoryBrowserEntryURL(_ entry: SVNRepositoryBrowserEntry) {
        copyRepositoryURL(entry.fullURL)
    }

    func openSelectedEntryInExternalDiff(using profile: ExternalToolProfile) {
        preferredDiffPreviewMode = .workingCopy
        Task {
            await performOpenSelectedEntryInExternalDiff(using: profile)
        }
    }

    func isHistoryEntrySelected(_ entry: SVNHistoryEntry) -> Bool {
        selectedHistoryRevision == entry.revision
    }

    func actionablePaths(for node: ChangeTreeNode) -> [String] {
        let prefix = node.absolutePath + "/"
        return entries.compactMap { entry in
            guard entry.isActionable else {
                return nil
            }
            guard entry.id == node.absolutePath || entry.id.hasPrefix(prefix) else {
                return nil
            }
            return entry.id
        }
    }

    // MARK: - Single-File Context Menu Operations

    func revertPath(_ path: String) {
        guard let entry = entryByPath[path], entry.canRevert else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmRevertTitle
        alert.informativeText = localizer.confirmRevertMessage(pathCount: 1)
        alert.addButton(withTitle: localizer.confirmRevertButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performRevertSelected(paths: [path])
        }
    }

    func addPath(_ path: String) {
        guard let entry = entryByPath[path], entry.canAdd else {
            return
        }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                guard let client else {
                    throw WorkbenchError.notConfigured
                }
                try await client.add(
                    paths: [path],
                    depth: .infinity,
                    force: false,
                    context: .foreground
                )
                statusNotice = .addedPaths(1)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
                statusNotice = .addFailed
            }
        }
    }

    func resolvePath(_ path: String) {
        guard let entry = entryByPath[path], entry.canResolve else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.confirmResolveTitle
        alert.informativeText = localizer.confirmResolveMessage(pathCount: 1)
        alert.addButton(withTitle: localizer.confirmResolveButtonTitle)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            await performResolveSelected(paths: [path])
        }
    }

    func deletePath(_ path: String) {
        let displayName = (path as NSString).lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizer.contextDeleteConfirmTitle
        alert.informativeText = localizer.contextDeleteConfirmMessage(displayName)
        alert.addButton(withTitle: localizer.contextDeleteConfirmButton)
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let isUnversioned = entryByPath[path]?.status == .unversioned
                if isUnversioned {
                    try FileManager.default.removeItem(atPath: path)
                } else {
                    guard client != nil else {
                        throw WorkbenchError.notConfigured
                    }
                    let runner = ProcessSubversionRunner()
                    let request = SubversionCLIInvocationRequest(
                        arguments: ["delete", "--force", path],
                        workingDirectory: normalizedRootInput
                    )
                    let result = try await runner.run(request)
                    guard result.exitCode == 0 else {
                        throw WorkbenchError.operationFailed(result.stderr)
                    }
                }
                statusNotice = .deletedPath(displayName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func ignorePath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let fileName = (path as NSString).lastPathComponent
                let parentDir = (path as NSString).deletingLastPathComponent
                let runner = ProcessSubversionRunner()

                let getRequest = SubversionCLIInvocationRequest(
                    arguments: ["propget", "svn:ignore", parentDir],
                    workingDirectory: normalizedRootInput
                )
                let getResult = try await runner.run(getRequest)
                var ignoreList = getResult.exitCode == 0
                    ? getResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                let existingEntries = Set(ignoreList.split(separator: "\n").map(String.init))
                guard !existingEntries.contains(fileName) else {
                    statusNotice = .ignoredPath(fileName)
                    return
                }

                if !ignoreList.isEmpty && !ignoreList.hasSuffix("\n") {
                    ignoreList += "\n"
                }
                ignoreList += fileName + "\n"

                let setRequest = SubversionCLIInvocationRequest(
                    arguments: ["propset", "svn:ignore", ignoreList, parentDir],
                    workingDirectory: normalizedRootInput
                )
                let setResult = try await runner.run(setRequest)
                guard setResult.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(setResult.stderr)
                }

                statusNotice = .ignoredPath(fileName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func rollbackPath(_ path: String, revision: Int64? = nil) {
        guard let entry = entryByPath[path] else {
            return
        }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                guard let workspaceOperator else {
                    throw WorkbenchError.notConfigured
                }

                let pathsToRollback: [String]
                let revisionArgument: String?

                if let revision {
                    // Rollback to specific revision
                    pathsToRollback = [path]
                    revisionArgument = String(revision)
                } else {
                    // Get recent history from the repository
                    let fallbackRoot = normalizedRootInput
                    let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
                    guard !root.isEmpty else {
                        lastError = localizer.rollbackNoHistoryError
                        return
                    }

                    guard let repositoryInspector else {
                        throw WorkbenchError.notConfigured
                    }

                    let history = try await repositoryInspector.recentHistory(
                        at: root,
                        limit: 10,
                        context: .foreground
                    )

                    guard history.count >= 2 else {
                        lastError = localizer.rollbackNoHistoryError
                        return
                    }

                    let prevRevision = history[1].revision
                    pathsToRollback = [path]
                    revisionArgument = String(prevRevision)
                }

                let result = try await workspaceOperator.rollback(
                    paths: pathsToRollback,
                    revision: Int64(revisionArgument ?? "BASE") ?? 0,
                    recursive: entry.isDirectory,
                    context: .foreground
                )

                lastError = nil
                statusNotice = .revertedPaths(result.revertedPaths.count)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
                statusNotice = .revertFailed
            }
        }
    }

    func ignoreDirectory(_ path: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localizer.ignoreDirectoryTitle
        alert.informativeText = localizer.ignoreDirectoryDescription
        alert.addButton(withTitle: localizer.confirmDeleteButtonTitle)  // Reuse
        alert.addButton(withTitle: localizer.cancelTitle)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            ignorePath(path)
        }
    }

    func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPathToClipboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func selectAndShowDiff(for path: String) {
        guard entryByPath[path] != nil else {
            return
        }
        selectedPaths = [path]
        preferredDiffPreviewMode = .workingCopy
        refreshDiffPreview(forceReload: true)
    }

    // MARK: - Bookmark Management

    func switchToBookmark(_ bookmark: WorkspaceBookmark) {
        rootPath = bookmark.path
        var updated = bookmarks
        if let index = updated.firstIndex(where: { $0.id == bookmark.id }) {
            updated[index].lastAccessedAt = Date()
        }
        bookmarks = updated
        bookmarkStore.save(bookmarks)
        requestRefresh(forceFullRefresh: true)
    }

    func addCurrentPathAsBookmark() {
        let trimmed = normalizedRootInput
        guard !trimmed.isEmpty else { return }
        let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        guard !bookmarks.contains(where: { $0.path == standardized }) else { return }
        let bookmark = WorkspaceBookmark(path: standardized)
        bookmarks.append(bookmark)
        bookmarkStore.save(bookmarks)
    }

    func addBookmarkFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = localizer.addWorkingCopyMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let standardized = url.standardizedFileURL.path
        guard !bookmarks.contains(where: { $0.path == standardized }) else {
            if let existing = bookmarks.first(where: { $0.path == standardized }) {
                switchToBookmark(existing)
            }
            return
        }
        let bookmark = WorkspaceBookmark(path: standardized)
        bookmarks.append(bookmark)
        bookmarkStore.save(bookmarks)
        switchToBookmark(bookmark)
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        bookmarkStore.save(bookmarks)
    }

    func reorderBookmarks(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        bookmarkStore.save(bookmarks)
    }

    func renameBookmark(id: UUID, newName: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].displayName = newName.isEmpty ? nil : newName
        bookmarkStore.save(bookmarks)
    }

    // MARK: - New SVN Operations

    func showLogForPath(_ path: String) {
        activeNavigation = .history
    }

    func blamePath(_ path: String) {
        blameTargetPath = path
        isBlamePresented = true
        blameLines = []
        blameError = nil
        isLoadingBlame = true
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["blame", "--xml", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                blameLines = BlameXMLParser.parse(result.stdout)
                isLoadingBlame = false
            } catch {
                blameError = localizedErrorMessage(for: error)
                isLoadingBlame = false
            }
        }
    }

    func lockPath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["lock", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .lockedPath((path as NSString).lastPathComponent)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func unlockPath(_ path: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["unlock", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .unlockedPath((path as NSString).lastPathComponent)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func renamePath(_ path: String) {
        renameTargetPath = path
        renameNewName = (path as NSString).lastPathComponent
        isRenamePresented = true
    }

    func performRename() {
        guard let sourcePath = renameTargetPath else { return }
        let newName = renameNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        let parentDir = (sourcePath as NSString).deletingLastPathComponent
        let destinationPath = (parentDir as NSString).appendingPathComponent(newName)
        isRenamePresented = false

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["move", sourcePath, destinationPath],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                statusNotice = .renamedPath((sourcePath as NSString).lastPathComponent, newName)
                lastError = nil
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func createPatchForPath(_ path: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "patch")!]
        panel.nameFieldStringValue = "\((path as NSString).lastPathComponent).patch"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["diff", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
                statusNotice = .createdPatch((path as NSString).lastPathComponent)
                lastError = nil
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func showPropertiesForPath(_ path: String) {
        propertiesTargetPath = path
        isPropertiesPresented = true
        propertyList = []
        propertiesError = nil
        isLoadingProperties = true
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["proplist", "-v", "--xml", path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                propertyList = SVNPropertyXMLParser.parse(result.stdout)
                isLoadingProperties = false
            } catch {
                propertiesError = localizedErrorMessage(for: error)
                isLoadingProperties = false
            }
        }
    }

    func setProperty(path: String, name: String, value: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["propset", name, value, path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                showPropertiesForPath(path)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    func deleteProperty(path: String, name: String) {
        Task {
            do {
                _ = try await configureServicesIfNeeded()
                let runner = ProcessSubversionRunner()
                let request = SubversionCLIInvocationRequest(
                    executablePath: "svn",
                    arguments: ["propdel", name, path],
                    workingDirectory: normalizedRootInput
                )
                let result = try await runner.run(request)
                guard result.exitCode == 0 else {
                    throw WorkbenchError.operationFailed(result.stderr)
                }
                showPropertiesForPath(path)
                await enqueueRefresh(forceFullRefresh: true)
            } catch {
                lastError = localizedErrorMessage(for: error)
            }
        }
    }

    private var normalizedRootInput: String {
        rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyRepositoryURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(urlString, forType: .string) else {
            lastError = localizer.repositoryBrowserCopyFailed
            return
        }

        lastError = nil
        statusNotice = .copiedRepositoryLocation
    }

    private func openRepositoryURLInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            lastError = localizer.repositoryBrowserOpenFailed
            return
        }

        guard NSWorkspace.shared.open(url) else {
            lastError = localizer.repositoryBrowserOpenFailed
            return
        }

        lastError = nil
        statusNotice = .openedRepositoryLocation
    }

    private func requestRefresh(forceFullRefresh: Bool) {
        Task { [weak self] in
            await self?.enqueueRefresh(forceFullRefresh: forceFullRefresh)
        }
    }

    private func enqueueRefresh(forceFullRefresh: Bool) async {
        if isRefreshing {
            hasQueuedRefresh = true
            queuedRefreshNeedsFullRescan = queuedRefreshNeedsFullRescan || forceFullRefresh
            diagnosticLog(
                "performRefresh queued root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
                "queuedForceFullRefresh=\(queuedRefreshNeedsFullRescan)"
            )
            return
        }

        await performRefresh(forceFullRefresh: forceFullRefresh)
    }

    private func performRefresh(forceFullRefresh: Bool) async {
        guard !normalizedRootInput.isEmpty else {
            lastError = localizer.selectWorkingCopyFirstError
            statusNotice = .noWorkingCopySelected
            diagnosticLog("performRefresh skipped: empty root")
            return
        }

        isRefreshing = true
        lastError = nil
        diagnosticLog(
            "performRefresh start root=\(normalizedRootInput) forceFullRefresh=\(forceFullRefresh) " +
            "pendingCommand=\(pendingWorkbenchCommand?.command.rawValue ?? "nil")"
        )
        defer {
            let shouldRunQueuedRefresh = hasQueuedRefresh
            let queuedForceFullRefresh = queuedRefreshNeedsFullRescan
            hasQueuedRefresh = false
            queuedRefreshNeedsFullRescan = false
            isRefreshing = false

            if shouldRunQueuedRefresh {
                diagnosticLog(
                    "performRefresh draining queued refresh root=\(normalizedRootInput) " +
                    "forceFullRefresh=\(queuedForceFullRefresh)"
                )
                requestRefresh(forceFullRefresh: queuedForceFullRefresh)
            }
        }

        do {
            let root = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            let snapshot = try await refreshSnapshotFromService(
                rootPath: root,
                forceFullRefresh: forceFullRefresh
            )

            let workingCopyItems = try await client.status(
                at: root,
                options: .commitSheet,
                context: .foreground
            )
            await refreshRepositoryInsights(rootPath: root)

            badgeEntryCount = snapshot.entries.count
            let freshEntries = workbenchEntries(from: workingCopyItems, rootPath: root)
            applyLoadedEntries(freshEntries, rootPath: root)
            let appliedCommand = pendingWorkbenchCommand
            selectedPaths = selectionForFreshEntries(freshEntries, rootPath: root)
            refreshDiffPreview(forceReload: true)
            lastRefreshDate = snapshot.generatedAt
            if let appliedCommand {
                statusNotice = finderReadyNotice(
                    for: appliedCommand,
                    selectedCount: selectedPaths.count
                )
            } else {
                statusNotice = .loadedEntries(
                    entryCount: entries.count,
                    badgeCount: badgeEntryCount
                )
            }
            diagnosticLog(
                "performRefresh completed root=\(root) items=\(workingCopyItems.count) " +
                "entries=\(entries.count) badges=\(badgeEntryCount) selected=\(selectedPaths.count) " +
                "appliedCommand=\(appliedCommand?.command.rawValue ?? "nil")"
            )
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .refreshFailed
            diagnosticLog("performRefresh failed error=\(error.localizedDescription)")
        }
    }

    private func performToggleMonitoring() async {
        guard !normalizedRootInput.isEmpty else {
            lastError = localizer.chooseBeforeWatcherError
            return
        }

        do {
            let root = try await configureServicesIfNeeded()

            if isMonitoring {
                try await stopMonitoring(rootPath: root)
                isMonitoring = false
                statusNotice = .watcherStopped
            } else {
                try await startMonitoring(rootPath: root)
                isMonitoring = true
                statusNotice = .watcherStarted
                await enqueueRefresh(forceFullRefresh: false)
            }
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .watcherUpdateFailed
        }
    }

    private func performAddSelected() async {
        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            let addablePaths = selectedEntries.filter(\.canAdd).map(\.id)
            guard !addablePaths.isEmpty else {
                lastError = localizer.selectUnversionedToAddError
                return
            }

            try await client.add(
                paths: addablePaths,
                depth: .infinity,
                force: false,
                context: .foreground
            )
            statusNotice = .addedPaths(addablePaths.count)
            lastError = nil
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .addFailed
        }
    }

    private func performUpdateWorkingCopy() async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .updatingWorkingCopy

        do {
            let root = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            let result = try await workspaceOperator.update(
                rootPath: root,
                context: .foreground
            )
            lastError = nil
            statusNotice = .updatedWorkingCopy(
                pathCount: result.updatedPaths.count,
                revision: result.resultingRevision,
                hasConflicts: result.hasConflicts
            )
            isRunningWorkspaceOperation = false
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            isRunningWorkspaceOperation = false
            lastError = localizedErrorMessage(for: error)
            statusNotice = .updateFailed
        }
    }

    private func performCleanupWorkingCopy() async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .cleaningWorkingCopy

        do {
            let root = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            _ = try await workspaceOperator.cleanup(
                rootPath: root,
                context: .foreground
            )
            lastError = nil
            statusNotice = .cleanedWorkingCopy
            isRunningWorkspaceOperation = false
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            isRunningWorkspaceOperation = false
            lastError = localizedErrorMessage(for: error)
            statusNotice = .cleanupFailed
        }
    }

    private func performRevertSelected(paths: [String]) async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .revertingPaths(pathCount: paths.count)

        do {
            _ = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            let result = try await workspaceOperator.revert(
                paths: paths,
                context: .foreground
            )
            lastError = nil
            statusNotice = .revertedPaths(result.revertedPaths.count)
            isRunningWorkspaceOperation = false
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            isRunningWorkspaceOperation = false
            lastError = localizedErrorMessage(for: error)
            statusNotice = .revertFailed
        }
    }

    private func performResolveSelected(paths: [String]) async {
        guard !isBusy else {
            return
        }

        isRunningWorkspaceOperation = true
        statusNotice = .resolvingPaths(pathCount: paths.count)

        do {
            _ = try await configureServicesIfNeeded()
            guard let workspaceOperator else {
                throw WorkbenchError.notConfigured
            }

            let result = try await workspaceOperator.resolve(
                paths: paths,
                accept: "working",
                context: .foreground
            )
            lastError = nil
            statusNotice = .resolvedPaths(result.resolvedPaths.count)
            isRunningWorkspaceOperation = false
            await enqueueRefresh(forceFullRefresh: true)
        } catch {
            isRunningWorkspaceOperation = false
            lastError = localizedErrorMessage(for: error)
            statusNotice = .resolveFailed
        }
    }

    private func performCommitSelected() async {
        do {
            _ = try await configureServicesIfNeeded()
            guard let client else {
                throw WorkbenchError.notConfigured
            }

            let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                lastError = localizer.emptyCommitMessageError
                return
            }

            let candidates = selectedEntries
                .filter(\.canCommit)
                .map {
                    CommitCandidate(
                        path: $0.id,
                        status: $0.status,
                        isExplicitlySelected: true
                    )
                }

            guard !candidates.isEmpty else {
                lastError = localizer.selectModifiedToCommitError
                return
            }

            let revision = try await client.commit(
                candidates: candidates,
                message: message,
                context: .foreground
            )
            commitMessage = ""
            lastError = nil
            statusNotice = .committedPaths(
                pathCount: candidates.count,
                revision: revision
            )
            if refreshStatusAfterCommit {
                await enqueueRefresh(forceFullRefresh: true)
            }
        } catch {
            lastError = localizedErrorMessage(for: error)
            statusNotice = .commitFailed
        }
    }

    private func configureServicesIfNeeded() async throws -> String {
        let rawRoot = normalizedRootInput
        guard !rawRoot.isEmpty else {
            throw WorkbenchError.invalidWorkingCopyRoot
        }
        let root = URL(fileURLWithPath: rawRoot).standardizedFileURL.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) else {
            throw WorkbenchError.workingCopyPathNotFound(root)
        }
        guard isDirectory.boolValue else {
            throw WorkbenchError.workingCopyPathIsNotDirectory(root)
        }

        if
            configuredRootPath == root,
            client != nil,
            repositoryInspector != nil,
            diffInspector != nil,
            (host != nil || xpcClient != nil)
        {
            return root
        }

        if isMonitoring, let configuredRootPath, configuredRootPath != root {
            try? await stopMonitoring(rootPath: configuredRootPath)
            isMonitoring = false
        }

        let baseConfiguration = runtimePaths.statusServiceConfiguration(repositoryRoot: root)

        if runtimePaths.hasBundledStatusService {
            host = nil
            xpcClient = StatusServiceXPCClient()
        } else {
            host = try StatusServiceHost(
                configuration: baseConfiguration
            )
            xpcClient = nil
        }
        client = RustCommandBridgeSVNClient(
            configuration: baseConfiguration.clientConfiguration,
            bridgeConfiguration: runtimePaths.bridgeConfiguration
        )
        workspaceOperator = SubversionWorkspaceOperator()
        repositoryInspector = SubversionRepositoryInspector()
        diffInspector = SubversionDiffInspector()
        UserDefaults.standard.set(root, forKey: Self.lastWorkingCopyDefaultsKey)
        broadcastCurrentMonitoredRoot()
        configuredRootPath = root
        badgeEntryCount = 0
        clearLoadedEntries()
        return root
    }

    private func refreshSnapshotFromService(
        rootPath: String,
        forceFullRefresh: Bool
    ) async throws -> BadgeSnapshot {
        if let xpcClient {
            return try await xpcClient.refresh(
                rootPath: rootPath,
                forceFullRefresh: forceFullRefresh
            )
        }

        guard let host else {
            throw WorkbenchError.notConfigured
        }

        if forceFullRefresh {
            return try await host.refresh(rootPath: rootPath, forceFullRefresh: true)
        }
        return try await host.refreshIfNeeded(rootPath: rootPath)
    }

    private func startMonitoring(rootPath: String) async throws {
        if let xpcClient {
            try await xpcClient.startMonitoring(rootPath: rootPath)
            return
        }

        guard let host else {
            throw WorkbenchError.notConfigured
        }
        try await host.startMonitoring(rootPath: rootPath)
    }

    private func stopMonitoring(rootPath: String) async throws {
        if let xpcClient {
            try await xpcClient.stopMonitoring(rootPath: rootPath)
            return
        }

        guard let host else {
            throw WorkbenchError.notConfigured
        }
        try await host.stopMonitoring(rootPath: rootPath)
    }

    private func localizedErrorMessage(for error: Error) -> String {
        if let workbenchError = error as? WorkbenchError {
            return workbenchError.localizedText(using: localizer)
        }

        return error.localizedDescription
    }

    private func refreshRepositoryInsights(rootPath: String) async {
        guard let repositoryInspector else {
            repositorySummary = nil
            repositoryBrowserListing = nil
            repositoryBrowserRootURL = nil
            repositoryBrowserWorkingCopyURL = nil
            isLoadingRepositoryBrowser = false
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            recentHistory = []
            recentHistoryError = nil
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
            return
        }

        do {
            let summary = try await repositoryInspector.summary(
                at: rootPath,
                context: .foreground
            )
            repositorySummary = summary
            repositoryBrowserRootURL = summary.repositoryRootURL ?? summary.repositoryURL
            repositoryBrowserWorkingCopyURL = summary.repositoryURL

            let preferredBrowserURL = preferredRepositoryBrowserURL(
                summary: summary,
                currentListingURL: repositoryBrowserListing?.baseURL
            )
            await loadRepositoryBrowserListing(
                url: preferredBrowserURL,
                using: repositoryInspector
            )
        } catch {
            diagnosticLog("refreshRepositoryInsights summary failed error=\(error.localizedDescription)")
            repositorySummary = nil
            repositoryBrowserListing = nil
            repositoryBrowserRootURL = nil
            repositoryBrowserWorkingCopyURL = nil
            isLoadingRepositoryBrowser = false
            repositoryBrowserError = localizedErrorMessage(for: error)
            clearRepositoryBrowserFilePreview()
            recentHistory = []
            recentHistoryError = nil
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
            return
        }

        do {
            diagnosticLog("refreshRepositoryInsights history request rootPath=\(rootPath)")
            let history = try await repositoryInspector.recentHistory(
                at: rootPath,
                limit: 8,
                context: .foreground
            )
            diagnosticLog("refreshRepositoryInsights history loaded rootPath=\(rootPath) revisions=\(history.map(\\.revision))")
            recentHistory = history
            recentHistoryError = nil

            guard !history.isEmpty else {
                selectedHistoryRevision = nil
                selectedHistoryEntryDetail = nil
                isLoadingHistoryDetail = false
                return
            }

            let preferredRevision = history.contains { $0.revision == selectedHistoryRevision }
                ? selectedHistoryRevision
                : history.first?.revision

            if let preferredRevision {
                selectedHistoryRevision = preferredRevision
                isLoadingHistoryDetail = true
                do {
                    diagnosticLog("refreshRepositoryInsights detail request rootPath=\(rootPath) revision=\(preferredRevision)")
                    selectedHistoryEntryDetail = try await repositoryInspector.logDetail(
                        at: rootPath,
                        revision: preferredRevision,
                        context: .foreground
                    )
                    diagnosticLog("refreshRepositoryInsights detail loaded rootPath=\(rootPath) revision=\(preferredRevision) changedPaths=\(selectedHistoryEntryDetail?.changedPaths.count ?? 0)")
                } catch {
                    selectedHistoryEntryDetail = nil
                    diagnosticLog("refreshRepositoryInsights detail failed rootPath=\(rootPath) revision=\(preferredRevision) error=\(error.localizedDescription)")
                }
                isLoadingHistoryDetail = false
            }
        } catch {
            diagnosticLog("refreshRepositoryInsights history failed error=\(error.localizedDescription)")
            recentHistory = []
            recentHistoryError = localizedErrorMessage(for: error)
            selectedHistoryRevision = nil
            selectedHistoryEntryDetail = nil
            isLoadingHistoryDetail = false
        }
    }

    private func preferredRepositoryBrowserURL(
        summary: SVNRepositorySummary,
        currentListingURL: String?
    ) -> String {
        if let currentListingURL, !currentListingURL.isEmpty {
            return currentListingURL
        }
        return summary.repositoryURL
    }

    private func loadRepositoryBrowserListing(
        url: String,
        using repositoryInspector: SubversionRepositoryInspector? = nil
    ) async {
        guard !url.isEmpty else {
            repositoryBrowserListing = nil
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            return
        }

        guard let repositoryInspector = repositoryInspector ?? self.repositoryInspector else {
            repositoryBrowserListing = nil
            repositoryBrowserError = nil
            clearRepositoryBrowserFilePreview()
            return
        }

        isLoadingRepositoryBrowser = true
        repositoryBrowserError = nil
        do {
            let listing = try await repositoryInspector.browse(
                url: url,
                context: .foreground
            )
            repositoryBrowserListing = listing
            repositoryBrowserError = nil

            if
                let selectedRepositoryBrowserEntry,
                let refreshedEntry = listing.entries.first(where: { $0.id == selectedRepositoryBrowserEntry.id }),
                !refreshedEntry.isDirectory
            {
                await loadRepositoryBrowserFilePreview(for: refreshedEntry)
            } else {
                clearRepositoryBrowserFilePreview()
            }
        } catch {
            clearRepositoryBrowserFilePreview()
            repositoryBrowserError = localizedErrorMessage(for: error)
            diagnosticLog("loadRepositoryBrowserListing failed url=\(url) error=\(error.localizedDescription)")
        }
        isLoadingRepositoryBrowser = false
    }

    private func loadHistoryDetail(for revision: Int64) async {
        guard let repositoryInspector else {
            return
        }

        let fallbackRoot = normalizedRootInput
        let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
        guard !root.isEmpty else {
            return
        }

        selectedHistoryRevision = revision
        isLoadingHistoryDetail = true
        refreshDiffPreview(forceReload: true)
        do {
            diagnosticLog("loadHistoryDetail request root=\(root) revision=\(revision)")
            selectedHistoryEntryDetail = try await repositoryInspector.logDetail(
                at: root,
                revision: revision,
                context: .foreground
            )
            diagnosticLog("loadHistoryDetail loaded root=\(root) revision=\(revision) changedPaths=\(selectedHistoryEntryDetail?.changedPaths.count ?? 0)")
        } catch {
            selectedHistoryEntryDetail = nil
            diagnosticLog("loadHistoryDetail failed root=\(root) revision=\(revision) error=\(error.localizedDescription)")
        }
        isLoadingHistoryDetail = false
    }

    private func loadRepositoryBrowserFilePreview(for entry: SVNRepositoryBrowserEntry) async {
        guard !entry.isDirectory else {
            clearRepositoryBrowserFilePreview()
            return
        }

        guard let repositoryInspector else {
            clearRepositoryBrowserFilePreview()
            return
        }

        repositoryBrowserPreviewTask?.cancel()
        repositoryBrowserPreviewTask = nil
        selectedRepositoryBrowserEntry = entry
        repositoryBrowserPreviewText = nil
        repositoryBrowserPreviewMessage = nil
        repositoryBrowserPreviewError = nil
        isLoadingRepositoryBrowserPreview = true

        repositoryBrowserPreviewTask = Task { [weak self] in
            do {
                let preview = try await repositoryInspector.fileContents(
                    url: entry.fullURL,
                    context: .foreground
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard let self, self.selectedRepositoryBrowserEntry?.id == entry.id else {
                        return
                    }

                    self.isLoadingRepositoryBrowserPreview = false
                    self.repositoryBrowserPreviewError = nil

                    if preview.isBinary {
                        self.repositoryBrowserPreviewText = nil
                        self.repositoryBrowserPreviewMessage = self.localizer.repositoryBrowserBinaryPreview(
                            entry.name,
                            byteCount: preview.byteCount
                        )
                    } else if let text = preview.text {
                        let truncated = self.truncateRepositoryBrowserPreviewText(text)
                        self.repositoryBrowserPreviewText = truncated.text
                        self.repositoryBrowserPreviewMessage = truncated.wasTruncated
                            ? self.localizer.repositoryBrowserPreviewTruncated(
                                entry.name,
                                byteCount: preview.byteCount
                            )
                            : nil
                    } else {
                        self.repositoryBrowserPreviewText = nil
                        self.repositoryBrowserPreviewMessage = self.localizer.repositoryBrowserEmptyPreview(
                            entry.name
                        )
                    }

                    self.repositoryBrowserPreviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard let self, self.selectedRepositoryBrowserEntry?.id == entry.id else {
                        return
                    }

                    self.isLoadingRepositoryBrowserPreview = false
                    self.repositoryBrowserPreviewText = nil
                    self.repositoryBrowserPreviewMessage = nil
                    self.repositoryBrowserPreviewError = self.localizedErrorMessage(for: error)
                    self.repositoryBrowserPreviewTask = nil
                }
            }
        }
    }

    private func clearRepositoryBrowserFilePreview() {
        repositoryBrowserPreviewTask?.cancel()
        repositoryBrowserPreviewTask = nil
        selectedRepositoryBrowserEntry = nil
        repositoryBrowserPreviewText = nil
        repositoryBrowserPreviewMessage = nil
        repositoryBrowserPreviewError = nil
        isLoadingRepositoryBrowserPreview = false
    }

    private func truncateRepositoryBrowserPreviewText(_ text: String) -> (text: String, wasTruncated: Bool) {
        let maxCharacters = 48_000
        guard text.count > maxCharacters else {
            return (text, false)
        }

        let truncated = String(text.prefix(maxCharacters))
        return (truncated, true)
    }

    private func refreshDiffPreview(forceReload: Bool = false) {
        guard let diffInspector else {
            clearDiffPreview(message: nil)
            return
        }

        let fallbackRoot = normalizedRootInput
        let root = configuredRootPath ?? (fallbackRoot.isEmpty ? "" : Self.standardizedPath(fallbackRoot))
        guard !root.isEmpty else {
            clearDiffPreview(message: nil)
            return
        }

        guard let mode = effectiveDiffPreviewMode else {
            clearDiffPreview(message: nil)
            return
        }

        let requestKey: DiffPreviewRequestKey
        let emptyMessage: String?

        switch mode {
        case .workingCopy:
            guard let entry = primarySelectedEntry else {
                clearDiffPreview(message: nil)
                return
            }

            if entry.status == .unversioned {
                clearDiffPreview(
                    message: localizer.diffPreviewUnavailableForUnversioned(entry.displayName)
                )
                return
            }

            requestKey = .workingCopy(
                rootPath: root,
                targetPath: entry.id,
                status: entry.status,
                propertyModified: entry.item.propertyModified
            )
            emptyMessage = localizer.diffPreviewNoChanges(entry.displayName)
        case .historyRevision:
            guard let selectedHistoryRevision else {
                clearDiffPreview(message: nil)
                return
            }

            requestKey = .historyRevision(
                rootPath: root,
                revision: selectedHistoryRevision
            )
            emptyMessage = localizer.historyDiffNoChanges(selectedHistoryRevision)
        }

        guard forceReload || lastDiffPreviewRequest != requestKey else {
            return
        }

        diffPreviewTask?.cancel()
        diffPreviewTask = nil
        lastDiffPreviewRequest = requestKey
        selectedDiffText = nil
        diffPreviewMessage = nil
        diffPreviewError = nil
        isLoadingDiffPreview = true

        diffPreviewTask = Task { [weak self] in
            do {
                let preview: SVNDiffPreview
                switch requestKey {
                case let .workingCopy(rootPath, targetPath, _, _):
                    preview = try await diffInspector.workingCopyDiff(
                        at: targetPath,
                        workingCopyRoot: rootPath,
                        context: .foreground
                    )
                case let .historyRevision(rootPath, revision):
                    preview = try await diffInspector.revisionDiff(
                        at: rootPath,
                        revision: revision,
                        context: .foreground
                    )
                }

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard
                        let self,
                        self.lastDiffPreviewRequest == requestKey
                    else {
                        return
                    }

                    self.isLoadingDiffPreview = false
                    self.diffPreviewError = nil

                    if preview.isEmpty {
                        self.selectedDiffText = nil
                        self.diffPreviewMessage = emptyMessage
                    } else {
                        self.selectedDiffText = preview.rawText
                        self.diffPreviewMessage = nil
                    }

                    self.diffPreviewTask = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard
                        let self,
                        self.lastDiffPreviewRequest == requestKey
                    else {
                        return
                    }

                    self.isLoadingDiffPreview = false
                    self.selectedDiffText = nil
                    self.diffPreviewMessage = nil
                    self.diffPreviewError = self.localizedErrorMessage(for: error)
                    self.diffPreviewTask = nil
                }
            }
        }
    }

    private func clearDiffPreview(message: String?) {
        diffPreviewTask?.cancel()
        diffPreviewTask = nil
        lastDiffPreviewRequest = nil
        selectedDiffText = nil
        diffPreviewMessage = message
        diffPreviewError = nil
        isLoadingDiffPreview = false
    }

    private func performOpenSelectedEntryInExternalDiff(using profile: ExternalToolProfile) async {
        guard !isLaunchingExternalDiff else {
            return
        }

        guard let entry = primarySelectedEntry else {
            lastError = localizer.externalDiffSelectEntryFirst
            return
        }

        guard entry.status != .unversioned else {
            lastError = localizer.externalDiffUnavailableForUnversioned(entry.displayName)
            return
        }

        var stagedArtifactDirectory: URL?
        do {
            _ = try await configureServicesIfNeeded()
            guard let repositoryInspector else {
                throw WorkbenchError.notConfigured
            }

            isLaunchingExternalDiff = true
            let artifactDirectory = try createExternalDiffArtifactDirectory(for: entry)
            stagedArtifactDirectory = artifactDirectory
            let leftURL = try await prepareExternalDiffLeftHandSide(
                for: entry,
                in: artifactDirectory,
                using: repositoryInspector
            )
            let rightPath = entry.id

            try await externalToolLauncher.launch(
                profile: profile,
                leftPath: leftURL.path,
                rightPath: rightPath,
                isDirectory: entry.isDirectory
            )

            externalDiffArtifactDirectories.append(artifactDirectory)
            stagedArtifactDirectory = nil
            if externalDiffArtifactDirectories.count > 12 {
                let staleDirectories = externalDiffArtifactDirectories.dropLast(12)
                for directory in staleDirectories {
                    try? FileManager.default.removeItem(at: directory)
                }
                externalDiffArtifactDirectories = Array(externalDiffArtifactDirectories.suffix(12))
            }

            lastError = nil
            statusNotice = .openedExternalDiff(profile.displayName)
        } catch {
            if let stagedArtifactDirectory {
                try? FileManager.default.removeItem(at: stagedArtifactDirectory)
            }
            lastError = localizedErrorMessage(for: error)
            statusNotice = .externalDiffLaunchFailed
        }

        isLaunchingExternalDiff = false
    }

    private func createExternalDiffArtifactDirectory(for entry: Entry) throws -> URL {
        try FileManager.default.createDirectory(
            at: externalDiffArtifactsRootURL,
            withIntermediateDirectories: true
        )

        let sanitizedName = entry.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let artifactDirectory = externalDiffArtifactsRootURL
            .appending(path: UUID().uuidString + "-" + sanitizedName)
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )
        return artifactDirectory
    }

    private func prepareExternalDiffLeftHandSide(
        for entry: Entry,
        in artifactDirectory: URL,
        using repositoryInspector: SubversionRepositoryInspector
    ) async throws -> URL {
        if entry.isDirectory {
            let baseDirectory = artifactDirectory.appending(path: "BASE-\(entry.displayName)")
            try await repositoryInspector.exportWorkingCopyBase(
                at: entry.id,
                to: baseDirectory.path,
                context: .foreground
            )
            return baseDirectory
        }

        let preview = try await repositoryInspector.workingCopyBaseContents(
            at: entry.id,
            context: .foreground
        )
        let baseFileURL = artifactDirectory.appending(path: "BASE-\(entry.displayName)")
        try preview.data.write(to: baseFileURL, options: .atomic)
        return baseFileURL
    }

    private func applyLoadedEntries(_ freshEntries: [Entry], rootPath: String) {
        entries = freshEntries
        entryByPath = Dictionary(uniqueKeysWithValues: freshEntries.map { ($0.id, $0) })
        treeNodes = ChangeTreeNode.build(from: freshEntries, rootPath: rootPath)
        dirtyCount = freshEntries.reduce(0) { count, entry in
            count + (entry.canCommit ? 1 : 0)
        }
        unversionedCount = freshEntries.reduce(0) { count, entry in
            count + (entry.canAdd ? 1 : 0)
        }
    }

    private func clearLoadedEntries() {
        entries = []
        treeNodes = []
        selectedPaths = []
        dirtyCount = 0
        unversionedCount = 0
        repositorySummary = nil
        repositoryBrowserListing = nil
        repositoryBrowserRootURL = nil
        repositoryBrowserWorkingCopyURL = nil
        isLoadingRepositoryBrowser = false
        repositoryBrowserError = nil
        clearRepositoryBrowserFilePreview()
        recentHistory = []
        recentHistoryError = nil
        selectedHistoryRevision = nil
        selectedHistoryEntryDetail = nil
        isLoadingHistoryDetail = false
        entryByPath = [:]
        clearDiffPreview(message: nil)
    }

    private func collapsedPaths(_ paths: [String]) -> [String] {
        let sortedPaths = Array(Set(paths.map(Self.standardizedPath))).sorted {
            if $0.count != $1.count {
                return $0.count < $1.count
            }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }

        var collapsed: [String] = []
        for path in sortedPaths {
            if collapsed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            collapsed.append(path)
        }
        return collapsed
    }

    private func savePresentationPreferences() {
        var prefs = visibilityPrefs
        prefs.defaultWindowPreset = defaultWindowPreset
        prefs.hideDiffPreviewInCompactWindow = hideDiffPreviewInCompactWindow
        presentationPreferencesStore.save(prefs)
    }

    private func workbenchEntries(from items: [WorkingCopyItem], rootPath: String) -> [Entry] {
        items
            .sorted { lhs, rhs in
                if lhs.isDirty != rhs.isDirty {
                    return lhs.isDirty && !rhs.isDirty
                }
                if lhs.status == .unversioned, rhs.status != .unversioned {
                    return true
                }
                if rhs.status == .unversioned, lhs.status != .unversioned {
                    return false
                }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            .map {
                Entry(
                    item: $0,
                    relativePath: Self.relativePath(for: $0.path, rootPath: rootPath)
                )
            }
    }

    private func retainedSelection(for entries: [Entry]) -> Set<String> {
        let validPaths = Set(entries.filter(\.isActionable).map(\.id))
        let retained = selectedPaths.intersection(validPaths)
        if !retained.isEmpty {
            return retained
        }

        return []
    }

    private func selectionForFreshEntries(_ entries: [Entry], rootPath: String) -> Set<String> {
        guard let pendingWorkbenchCommand else {
            return retainedSelection(for: entries)
        }

        guard pendingWorkbenchCommand.rootPath == nil || pendingWorkbenchCommand.rootPath == rootPath else {
            return retainedSelection(for: entries)
        }

        lastHandledWorkbenchCommandID = pendingWorkbenchCommand.id
        self.pendingWorkbenchCommand = nil
        workbenchCommandStore.clearCommand()

        let requestedSelection = selectedPaths(
            matching: pendingWorkbenchCommand.selectedPaths,
            in: entries
        )
        if !requestedSelection.isEmpty {
            return requestedSelection
        }

        return retainedSelection(for: entries)
    }

    private func selectedPaths(
        matching requestedPaths: [String],
        in entries: [Entry]
    ) -> Set<String> {
        guard !requestedPaths.isEmpty else {
            return []
        }

        let actionableEntries = entries.filter(\.isActionable)
        let availablePaths = Set(actionableEntries.map(\.id))
        var resolvedSelection: Set<String> = []

        for requestedPath in Set(requestedPaths.map(Self.standardizedPath)) {
            if availablePaths.contains(requestedPath) {
                resolvedSelection.insert(requestedPath)
                continue
            }

            let prefix = requestedPath.hasSuffix("/") ? requestedPath : requestedPath + "/"
            let descendants = actionableEntries
                .map(\.id)
                .filter { $0.hasPrefix(prefix) }
            resolvedSelection.formUnion(descendants)
        }

        return resolvedSelection
    }

    private static func relativePath(for path: String, rootPath: String) -> String {
        let rootURL = URL(fileURLWithPath: rootPath)
        let pathURL = URL(fileURLWithPath: path)
        let relative = pathURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return relative.isEmpty ? "." : relative
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func broadcastCurrentMonitoredRoot() {
        let trimmedRoot = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty else {
            return
        }
        monitoredRootsStore.saveRoots([trimmedRoot])
    }

    @objc
    private func handleMonitoredRootsRequest(_ notification: Notification) {
        broadcastCurrentMonitoredRoot()
    }

    @objc
    private func handleWorkbenchCommandDidChange(_ notification: Notification) {
        diagnosticLog("handleWorkbenchCommandDidChange notification")
        guard ingestPendingWorkbenchCommand(reason: "distributed-notification") != nil else {
            return
        }
        requestRefresh(forceFullRefresh: true)
    }

    @objc
    private func handleAppDidBecomeActive(_ notification: Notification) {
        diagnosticLog("handleAppDidBecomeActive")
        if ingestPendingWorkbenchCommand(reason: "app-did-become-active") != nil {
            requestRefresh(forceFullRefresh: true)
            return
        }

        guard entries.isEmpty, !normalizedRootInput.isEmpty else {
            return
        }

        requestRefresh(forceFullRefresh: false)
    }

    private func ingestPendingWorkbenchCommand(reason: String) -> MacSVNWorkbenchCommand? {
        guard let command = workbenchCommandStore.loadCommand() else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) no command")
            return nil
        }
        guard command.id != pendingWorkbenchCommand?.id else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) ignored pending duplicate \(command.id)")
            return nil
        }
        guard command.id != lastHandledWorkbenchCommandID else {
            diagnosticLog("ingestPendingWorkbenchCommand(\(reason)) ignored handled duplicate \(command.id)")
            return nil
        }

        pendingWorkbenchCommand = command
        if let rootPath = command.rootPath, self.rootPath != rootPath {
            self.rootPath = rootPath
        }
        statusNotice = .processingFinderCommand(
            command: command.command,
            pathCount: max(command.selectedPaths.count, 1)
        )
        lastError = nil
        diagnosticLog(
            "ingestPendingWorkbenchCommand(\(reason)) command=\(command.command.rawValue) " +
            "root=\(command.rootPath ?? "nil") selected=\(command.selectedPaths.count)"
        )
        requestWindowPresentationRefresh()
        return command
    }

    private func finderReadyNotice(
        for command: MacSVNWorkbenchCommand,
        selectedCount: Int
    ) -> WorkbenchNotice {
        switch command.command {
        case .commitSelected:
            return .finderCommitReady(selectedCount: selectedCount)
        case .diffSelected:
            return .finderDiffReady(selectedCount: selectedCount)
        case .openInWorkbench, .refreshNow:
            return .finderCommandReady(command: command.command, selectedCount: selectedCount)
        }
    }

    private func diagnosticLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: "MacTortoiseSVN")
            .appending(path: "workbench-debug.log")

        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            return
        }
    }

    deinit {
        diffPreviewTask?.cancel()
        repositoryBrowserPreviewTask?.cancel()
        try? FileManager.default.removeItem(at: externalDiffArtifactsRootURL)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

}
