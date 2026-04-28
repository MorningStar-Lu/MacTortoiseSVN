import CoreTypes
import Foundation

public enum MacSVNLanguage: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String {
        rawValue
    }

    public var nativeDisplayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "中文"
        }
    }

    public static func automaticDefault(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> MacSVNLanguage {
        guard let identifier = preferredLanguages.first?.lowercased() else {
            return .english
        }
        return identifier.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

public struct MacSVNLanguageStore: Sendable {
    public static let appGroupSuiteName = "group.com.morningstar.MacTortoiseSVN"
    public static let userDefaultsKey = "MacSVNPreferredLanguage"

    public init() {
    }

    public func loadLanguage() -> MacSVNLanguage {
        if
            let data = try? Data(contentsOf: storageURL),
            let rawValue = try? JSONDecoder().decode(String.self, from: data),
            let language = MacSVNLanguage(rawValue: rawValue)
        {
            return language
        }

        let sharedDefaults = UserDefaults(suiteName: Self.appGroupSuiteName)
        let rawValue = sharedDefaults?.string(forKey: Self.userDefaultsKey)
            ?? UserDefaults.standard.string(forKey: Self.userDefaultsKey)

        if let rawValue, let language = MacSVNLanguage(rawValue: rawValue) {
            return language
        }

        return MacSVNLanguage.automaticDefault()
    }

    public func saveLanguage(_ language: MacSVNLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: Self.userDefaultsKey)

        if let sharedDefaults = UserDefaults(suiteName: Self.appGroupSuiteName) {
            sharedDefaults.set(language.rawValue, forKey: Self.userDefaultsKey)
        }

        do {
            try FileManager.default.createDirectory(
                at: macSVNSharedAppSupportDirectory(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(language.rawValue)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private var storageURL: URL {
        macSVNSharedAppSupportDirectory().appending(path: "language.json")
    }
}

public struct MacSVNMonitoredRootsStore: Sendable {
    public static let distributedNotificationName = Notification.Name(
        "com.morningstar.MacTortoiseSVN.monitoredRootsDidChange"
    )
    public static let distributedRequestNotificationName = Notification.Name(
        "com.morningstar.MacTortoiseSVN.monitoredRootsRequest"
    )
    public static let distributedNotificationRootsKey = "roots"

    public init() {
    }

    public func loadRoots() -> [String] {
        guard
            let data = try? Data(contentsOf: storageURL),
            let paths = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Array(Set(paths.map(standardizedPath))).sorted()
    }

    public func saveRoots(_ roots: [String]) {
        let normalizedRoots = Array(Set(roots.map(standardizedPath))).sorted()
        let fileManager = FileManager.default
        let directoryURL = storageURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(normalizedRoots)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }

        DistributedNotificationCenter.default().post(
            name: Self.distributedNotificationName,
            object: nil,
            userInfo: [Self.distributedNotificationRootsKey: normalizedRoots]
        )
    }

    public func rootPath(containing path: String) -> String? {
        let standardized = standardizedPath(path)
        return loadRoots()
            .filter { standardized == $0 || standardized.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    private var storageURL: URL {
        macSVNSharedAppSupportDirectory()
            .appending(path: "monitored-roots.json")
    }
}

public struct MacSVNWorkbenchCommand: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var issuedAt: Date
    public var command: FinderMenuCommand
    public var rootPath: String?
    public var selectedPaths: [String]

    public init(
        id: UUID = UUID(),
        issuedAt: Date = Date(),
        command: FinderMenuCommand,
        rootPath: String?,
        selectedPaths: [String]
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.command = command
        self.rootPath = rootPath.map(standardizedPath)
        self.selectedPaths = Array(Set(selectedPaths.map(standardizedPath))).sorted()
    }
}

public struct MacSVNWorkbenchCommandStore: Sendable {
    public static let distributedNotificationName = Notification.Name(
        "com.morningstar.MacTortoiseSVN.workbenchCommandDidChange"
    )

    public init() {
    }

    public func loadCommand() -> MacSVNWorkbenchCommand? {
        guard
            let data = try? Data(contentsOf: storageURL),
            let command = try? JSONDecoder().decode(MacSVNWorkbenchCommand.self, from: data)
        else {
            return nil
        }

        return command
    }

    public func saveCommand(_ command: MacSVNWorkbenchCommand) {
        let fileManager = FileManager.default
        let directoryURL = storageURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(command)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }

        DistributedNotificationCenter.default().post(
            name: Self.distributedNotificationName,
            object: nil
        )
    }

    public func clearCommand() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    private var storageURL: URL {
        macSVNSharedAppSupportDirectory()
            .appending(path: "workbench-command.json")
    }
}

public struct MacSVNLocalizer: Sendable {
    public let language: MacSVNLanguage

    public init(language: MacSVNLanguage) {
        self.language = language
    }

    public var appTitle: String { choose(english: "MacTortoiseSVN", chinese: "MacTortoiseSVN") }
    public var appSubtitle: String {
        choose(
            english: "Phase 1-4 prototype: Rust status core, Swift status service, add/commit bridge, and a minimal macOS desktop shell.",
            chinese: "第 1 到 4 阶段原型：Rust 状态核心、Swift 状态服务、Add/Commit 桥接，以及一个最小可用的 macOS 桌面壳。"
        )
    }
    public var watcherOn: String { choose(english: "Watcher On", chinese: "监听已开启") }
    public var watcherOff: String { choose(english: "Watcher Off", chinese: "监听已关闭") }
    public var rustBridge: String { choose(english: "Rust Bridge", chinese: "Rust 桥接") }
    public var sqliteCache: String { choose(english: "SQLite Cache", chinese: "SQLite 缓存") }
    public var languageTitle: String { choose(english: "Language", chinese: "语言") }
    public var workingCopy: String { choose(english: "Working Copy", chinese: "工作副本") }
    public var chooseWorkingCopyPlaceholder: String {
        choose(english: "Choose an SVN working copy path", chinese: "选择一个 SVN 工作副本路径")
    }
    public var chooseFolder: String { choose(english: "Choose Folder", chinese: "选择文件夹") }
    public var chooseWorkingCopyPanelMessage: String {
        choose(english: "Choose an SVN working copy folder", chinese: "选择一个 SVN 工作副本文件夹")
    }
    public var selected: String { choose(english: "Selected", chinese: "已选") }
    public var dirty: String { choose(english: "Dirty", chinese: "变更") }
    public var unversioned: String { choose(english: "Unversioned", chinese: "未纳管") }
    public var badgeCache: String { choose(english: "Badge Cache", chinese: "徽标缓存") }
    public var actions: String { choose(english: "Actions", chinese: "操作") }
    public var refreshSnapshot: String { choose(english: "Refresh Snapshot", chinese: "刷新快照") }
    public var refreshIfNeeded: String { choose(english: "Refresh If Needed", chinese: "按需刷新") }
    public var startWatcher: String { choose(english: "Start Watcher", chinese: "启动监听") }
    public var stopWatcher: String { choose(english: "Stop Watcher", chinese: "停止监听") }
    public var selectActionable: String { choose(english: "Select Actionable", chinese: "选择可操作项") }
    public var clearSelection: String { choose(english: "Clear Selection", chinese: "清空选择") }
    public var commitMessagePlaceholder: String {
        choose(english: "Commit message", chinese: "提交说明")
    }
    public var addSelected: String { choose(english: "Add Selected", chinese: "添加所选") }
    public var commitSelected: String { choose(english: "Commit Selected", chinese: "提交所选") }
    public var status: String { choose(english: "Status", chinese: "状态") }
    public var workingCopyEntries: String { choose(english: "Working Copy Entries", chinese: "工作副本条目") }
    public var folder: String { choose(english: "Folder", chinese: "文件夹") }
    public var props: String { choose(english: "Props", chinese: "属性") }
    public var loadingDiffProfiles: String {
        choose(english: "Loading diff profiles...", chinese: "正在加载对比工具配置...")
    }
    public var noEntriesLoadedTitle: String {
        choose(english: "No entries loaded yet.", chinese: "还没有加载任何条目。")
    }
    public var noEntriesLoadedDescription: String {
        choose(
            english: "Run a refresh to populate this list from the Rust SVN bridge. Unversioned files can be added here, and modified paths can be committed once selected.",
            chinese: "执行一次刷新后，这里会从 Rust SVN 桥接加载条目。未纳管文件可以在这里添加，已修改路径在选中后可以直接提交。"
        )
    }
    public var noWorkingCopySelected: String {
        choose(english: "No working copy selected.", chinese: "还没有选择工作副本。")
    }
    public var chooseWorkingCopyPrompt: String {
        choose(english: "Choose a working copy to load SVN status.", chinese: "请选择一个工作副本来加载 SVN 状态。")
    }
    public var refreshFailed: String { choose(english: "Refresh failed.", chinese: "刷新失败。") }
    public var watcherStarted: String { choose(english: "Background watcher started.", chinese: "后台监听已启动。") }
    public var watcherStopped: String { choose(english: "Background watcher stopped.", chinese: "后台监听已停止。") }
    public var watcherUpdateFailed: String { choose(english: "Watcher update failed.", chinese: "监听状态更新失败。") }
    public var addFailed: String { choose(english: "Add failed.", chinese: "添加失败。") }
    public var commitFailed: String { choose(english: "Commit failed.", chinese: "提交失败。") }
    public func finderCommandLoadingText(_ commandTitle: String, pathCount: Int) -> String {
        choose(
            english: "Received Finder command: \(commandTitle). Loading \(pathCount) selected path(s)...",
            chinese: "已收到访达命令：\(commandTitle)。正在加载 \(pathCount) 个所选路径..."
        )
    }
    public func finderCommandReadyText(_ commandTitle: String, selectedCount: Int) -> String {
        choose(
            english: "Finder command ready: \(commandTitle). Loaded \(selectedCount) selected path(s).",
            chinese: "访达命令已就绪：\(commandTitle)。已载入 \(selectedCount) 个所选路径。"
        )
    }
    public func finderCommitReadyText(selectedCount: Int) -> String {
        choose(
            english: "Loaded \(selectedCount) selected path(s) from Finder. Enter a commit message to continue.",
            chinese: "已从访达载入 \(selectedCount) 个所选路径，请填写提交说明后继续。"
        )
    }
    public func finderDiffReadyText(selectedCount: Int) -> String {
        choose(
            english: "Loaded \(selectedCount) selected path(s) from Finder. Diff integration is the next step.",
            chinese: "已从访达载入 \(selectedCount) 个所选路径，比较功能链路是下一步。"
        )
    }
    public var invalidWorkingCopyRoot: String {
        choose(english: "The selected working copy path is invalid.", chinese: "所选工作副本路径无效。")
    }
    public func workingCopyPathNotFoundText(_ path: String) -> String {
        choose(
            english: "The selected working copy path does not exist: \(path)",
            chinese: "所选工作副本路径不存在：\(path)"
        )
    }
    public func workingCopyPathIsNotDirectoryText(_ path: String) -> String {
        choose(
            english: "The selected working copy path is not a folder: \(path)",
            chinese: "所选工作副本路径不是文件夹：\(path)"
        )
    }
    public var notConfigured: String {
        choose(
            english: "The workbench could not initialize the status service or SVN bridge.",
            chinese: "工作台未能初始化状态服务或 SVN 桥接。"
        )
    }
    public var selectWorkingCopyFirstError: String {
        choose(english: "Please choose a working copy first.", chinese: "请先选择一个工作副本。")
    }
    public var chooseBeforeWatcherError: String {
        choose(
            english: "Please choose a working copy before starting the background watcher.",
            chinese: "请先选择一个工作副本，再启动后台监听。"
        )
    }
    public var selectUnversionedToAddError: String {
        choose(
            english: "Select one or more unversioned files or folders to add.",
            chinese: "请选择一个或多个未纳管的文件或文件夹来添加。"
        )
    }
    public var emptyCommitMessageError: String {
        choose(english: "Commit message cannot be empty.", chinese: "提交说明不能为空。")
    }
    public var selectModifiedToCommitError: String {
        choose(
            english: "Select one or more modified paths to commit.",
            chinese: "请选择一个或多个已修改路径来提交。"
        )
    }
    public var finderMenuTitle: String { "MacTortoiseSVN" }

    public func lastRefreshText(_ dateText: String) -> String {
        choose(english: "Last refresh: \(dateText)", chinese: "上次刷新：\(dateText)")
    }

    public func loadedEntriesText(entryCount: Int, badgeCount: Int) -> String {
        choose(
            english: "Loaded \(entryCount) paths, with \(badgeCount) badge entries cached.",
            chinese: "已加载 \(entryCount) 个路径，缓存中有 \(badgeCount) 个徽标条目。"
        )
    }

    public func loadedCountText(_ count: Int) -> String {
        choose(english: "\(count) loaded", chinese: "已加载 \(count) 项")
    }

    public func addSucceededText(pathCount: Int) -> String {
        choose(english: "Added \(pathCount) path(s) to SVN.", chinese: "已将 \(pathCount) 个路径添加到 SVN。")
    }

    public func commitSucceededText(pathCount: Int, revision: Int64) -> String {
        choose(
            english: "Committed \(pathCount) path(s) as r\(revision).",
            chinese: "已提交 \(pathCount) 个路径，版本号为 r\(revision)。"
        )
    }

    public func title(for status: VersionControlStatus) -> String {
        switch status {
        case .normal:
            return choose(english: "Normal", chinese: "正常")
        case .modified:
            return choose(english: "Modified", chinese: "已修改")
        case .added:
            return choose(english: "Added", chinese: "已添加")
        case .deleted:
            return choose(english: "Deleted", chinese: "已删除")
        case .conflicted:
            return choose(english: "Conflicted", chinese: "有冲突")
        case .ignored:
            return choose(english: "Ignored", chinese: "已忽略")
        case .external:
            return choose(english: "External", chinese: "外部")
        case .locked:
            return choose(english: "Locked", chinese: "已锁定")
        case .missing:
            return choose(english: "Missing", chinese: "已丢失")
        case .replaced:
            return choose(english: "Replaced", chinese: "已替换")
        case .incomplete:
            return choose(english: "Incomplete", chinese: "不完整")
        case .obstructed:
            return choose(english: "Obstructed", chinese: "被阻塞")
        case .unversioned:
            return choose(english: "Unversioned", chinese: "未纳管")
        }
    }

    public func title(for command: FinderMenuCommand) -> String {
        switch command {
        case .commitSelected:
            return choose(english: "Commit Selected...", chinese: "提交所选...")
        case .diffSelected:
            return choose(english: "Diff Selected", chinese: "比较所选")
        case .refreshNow:
            return choose(english: "Refresh Cached Status", chinese: "刷新缓存状态")
        case .openInWorkbench:
            return choose(english: "Open in SVN Workbench", chinese: "在 MacSVN 工作台中打开")
        }
    }

    private func choose(english: String, chinese: String) -> String {
        switch language {
        case .english:
            return english
        case .simplifiedChinese:
            return chinese
        }
    }
}

public enum FinderBadgeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case modified
    case added
    case deleted
    case conflicted
    case unversioned
    case descendantDirty

    public var badgeIdentifier: String {
        rawValue
    }

    public var badgeLabel: String {
        switch self {
        case .modified:
            return "M"
        case .added:
            return "A"
        case .deleted:
            return "D"
        case .conflicted:
            return "!"
        case .unversioned:
            return "U"
        case .descendantDirty:
            return "..."
        }
    }
}

public struct FinderBadgeAssignment: Sendable, Hashable, Codable, Identifiable {
    public var path: String
    public var kind: FinderBadgeKind

    public var id: String {
        path
    }

    public var badgeIdentifier: String {
        kind.badgeIdentifier
    }

    public var badgeLabel: String {
        kind.badgeLabel
    }

    public init(path: String, kind: FinderBadgeKind) {
        self.path = path
        self.kind = kind
    }
}

public struct FinderBadgeRequest: Sendable, Hashable, Codable {
    public var rootPath: String
    public var visiblePaths: [String]

    public init(rootPath: String, visiblePaths: [String]) {
        self.rootPath = rootPath
        self.visiblePaths = visiblePaths
    }
}

public struct FinderBadgeResponse: Sendable, Hashable, Codable {
    public var assignments: [FinderBadgeAssignment]

    public init(assignments: [FinderBadgeAssignment]) {
        self.assignments = assignments
    }
}

public enum FinderMenuCommand: String, Sendable, Hashable, Codable, CaseIterable {
    case commitSelected
    case diffSelected
    case refreshNow
    case openInWorkbench
}

public struct FinderMenuActionDescriptor: Sendable, Hashable, Codable, Identifiable {
    public var command: FinderMenuCommand
    public var title: String
    public var isEnabled: Bool

    public var id: String {
        command.rawValue
    }

    public init(command: FinderMenuCommand, title: String, isEnabled: Bool = true) {
        self.command = command
        self.title = title
        self.isEnabled = isEnabled
    }
}

public struct FinderMenuRequest: Sendable, Hashable, Codable {
    public var rootPath: String
    public var selectedPaths: [String]

    public init(rootPath: String, selectedPaths: [String]) {
        self.rootPath = rootPath
        self.selectedPaths = selectedPaths
    }
}

public struct FinderMenuResponse: Sendable, Hashable, Codable {
    public var actions: [FinderMenuActionDescriptor]

    public init(actions: [FinderMenuActionDescriptor]) {
        self.actions = actions
    }
}

public struct FinderBadgeResolver: Sendable {
    public init() {
    }

    public func assignments(
        for visiblePaths: [String],
        snapshot: BadgeSnapshot
    ) -> [FinderBadgeAssignment] {
        let standardizedEntries = Dictionary(
            uniqueKeysWithValues: snapshot.entries.map { key, value in
                (standardizedPath(key), value)
            }
        )

        return visiblePaths.compactMap { path in
            let standardized = standardizedPath(path)
            if let directStatus = standardizedEntries[standardized],
               let kind = badgeKind(for: directStatus) {
                return FinderBadgeAssignment(path: standardized, kind: kind)
            }

            guard hasDirtyDescendant(for: standardized, entries: standardizedEntries) else {
                return nil
            }

            return FinderBadgeAssignment(path: standardized, kind: .descendantDirty)
        }
    }

    private func hasDirtyDescendant(
        for path: String,
        entries: [String: VersionControlStatus]
    ) -> Bool {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return entries.keys.contains(where: { $0.hasPrefix(prefix) })
    }

    private func badgeKind(for status: VersionControlStatus) -> FinderBadgeKind? {
        switch status {
        case .modified, .missing, .replaced, .incomplete, .obstructed:
            return .modified
        case .added:
            return .added
        case .deleted:
            return .deleted
        case .conflicted:
            return .conflicted
        case .unversioned:
            return .unversioned
        case .normal, .ignored, .external, .locked:
            return nil
        }
    }
}

public struct FinderContextMenuBuilder: Sendable {
    public init() {
    }

    public func actions(
        for selectedPaths: [String],
        snapshot: BadgeSnapshot?,
        language: MacSVNLanguage = MacSVNLanguageStore().loadLanguage()
    ) -> [FinderMenuActionDescriptor] {
        let standardizedSelection = Array(Set(selectedPaths.map(standardizedPath))).sorted()
        guard !standardizedSelection.isEmpty else {
            return []
        }

        let localizer = MacSVNLocalizer(language: language)

        let dirtySelectionCount = standardizedSelection.filter { path in
            isDirty(path: path, snapshot: snapshot)
        }.count
        let canCommit = dirtySelectionCount > 0
        let canDiff = dirtySelectionCount > 0 && standardizedSelection.count <= 2

        return [
            FinderMenuActionDescriptor(
                command: .commitSelected,
                title: localizer.title(for: .commitSelected),
                isEnabled: canCommit
            ),
            FinderMenuActionDescriptor(
                command: .diffSelected,
                title: localizer.title(for: .diffSelected),
                isEnabled: canDiff
            ),
            FinderMenuActionDescriptor(
                command: .refreshNow,
                title: localizer.title(for: .refreshNow)
            ),
            FinderMenuActionDescriptor(
                command: .openInWorkbench,
                title: localizer.title(for: .openInWorkbench)
            ),
        ]
    }

    private func isDirty(path: String, snapshot: BadgeSnapshot?) -> Bool {
        guard let snapshot else {
            return false
        }

        let standardizedEntries = Dictionary(
            uniqueKeysWithValues: snapshot.entries.map { key, value in
                (standardizedPath(key), value)
            }
        )
        if let status = standardizedEntries[path] {
            return status.isDirty
        }

        let prefix = path.hasSuffix("/") ? path : path + "/"
        return standardizedEntries.keys.contains(where: { $0.hasPrefix(prefix) })
    }
}

private func standardizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}

private func macSVNSharedAppSupportDirectory() -> URL {
    let fileManager = FileManager.default
    let baseDirectory: URL
    if let appGroupURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: MacSVNLanguageStore.appGroupSuiteName
    ) {
        baseDirectory = appGroupURL
    } else {
        baseDirectory = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
    }

    let preferredDirectory = baseDirectory.appending(path: "MacTortoiseSVN")
    let legacyDirectory = baseDirectory.appending(path: "MacSVNWorkbench")

    if fileManager.fileExists(atPath: preferredDirectory.path) {
        return preferredDirectory
    }

    if fileManager.fileExists(atPath: legacyDirectory.path) {
        return legacyDirectory
    }

    return preferredDirectory
}
