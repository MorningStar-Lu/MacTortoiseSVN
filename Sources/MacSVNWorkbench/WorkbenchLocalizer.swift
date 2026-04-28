import CoreTypes
import FinderSyncBridge
import Foundation

extension MacSVNLocalizer {
    fileprivate var useChineseWorkbenchText: Bool {
        language == .simplifiedChinese
    }

    var commitWindowTitle: String {
        useChineseWorkbenchText ? "SVN 工作台" : "SVN Workbench"
    }

    var commitWindowSubtitle: String {
        useChineseWorkbenchText
            ? "围绕工作副本的更改、仓库信息和最近历史来组织常用操作，再逐步补齐完整的 SVN 工作流。"
            : "Organize change review, repository context, and recent history in one workspace, then grow the rest of the SVN workflows around it."
    }

    var changeListPanelTitle: String {
        useChineseWorkbenchText ? "更改列表" : "Change List"
    }

    var changeListModeTitle: String {
        useChineseWorkbenchText ? "更改列表(T):" : "Change List:"
    }

    var changeListModeChanges: String {
        useChineseWorkbenchText ? "更改" : "Changes"
    }

    var commitMessagePanelTitle: String {
        useChineseWorkbenchText ? "提交消息" : "Commit Message"
    }

    var diffPreviewTitle: String {
        useChineseWorkbenchText ? "差异" : "Diff"
    }

    var diffPreviewEmptyTitle: String {
        useChineseWorkbenchText ? "还没有可预览的条目。" : "No entry selected for preview yet."
    }

    var diffPreviewEmptyDescription: String {
        useChineseWorkbenchText
            ? "先在左侧勾选或点选要提交的文件，这里会同步显示当前选择的路径、状态和后续要接入的 diff 面板位置。"
            : "Select files from the left-hand tree first. This panel will mirror the current selection, status, and the future diff viewer slot."
    }

    var subversionOptionsTitle: String {
        useChineseWorkbenchText ? "Subversion" : "Subversion"
    }

    var updateWorkingCopy: String {
        useChineseWorkbenchText ? "更新工作副本" : "Update Working Copy"
    }

    var cleanupWorkingCopy: String {
        useChineseWorkbenchText ? "清理工作副本" : "Cleanup Working Copy"
    }

    var revertSelected: String {
        useChineseWorkbenchText ? "还原所选" : "Revert Selected"
    }

    var resolveSelected: String {
        useChineseWorkbenchText ? "解决所选冲突" : "Resolve Selected"
    }

    var repositoryOverviewTitle: String {
        useChineseWorkbenchText ? "仓库概览" : "Repository Overview"
    }

    var repositoryBrowserTitle: String {
        useChineseWorkbenchText ? "仓库浏览器" : "Repository Browser"
    }

    var repositoryBrowserLocationTitle: String {
        useChineseWorkbenchText ? "当前位置" : "Current Location"
    }

    var repositoryBrowserRoot: String {
        useChineseWorkbenchText ? "仓库根" : "Repository Root"
    }

    var repositoryBrowserCurrentLocation: String {
        useChineseWorkbenchText ? "工作副本位置" : "Working Copy Location"
    }

    var repositoryBrowserUp: String {
        useChineseWorkbenchText ? "上一级" : "Up One Level"
    }

    var repositoryBrowserOpenDirectory: String {
        useChineseWorkbenchText ? "打开目录" : "Open Directory"
    }

    var repositoryBrowserCopyURL: String {
        useChineseWorkbenchText ? "复制 URL" : "Copy URL"
    }

    var repositoryBrowserOpenInBrowser: String {
        useChineseWorkbenchText ? "浏览器打开" : "Open in Browser"
    }

    var repositoryBrowserPreviewTitle: String {
        useChineseWorkbenchText ? "文件预览" : "File Preview"
    }

    var repositoryOverviewEmptyDescription: String {
        useChineseWorkbenchText
            ? "刷新后会在这里显示仓库 URL、版本号和最近一次提交者等信息。"
            : "Refresh the working copy to load the repository URL, revision, and last changed author here."
    }

    var recentHistoryTitle: String {
        useChineseWorkbenchText ? "最近历史" : "Recent History"
    }

    var recentHistoryEmptyDescription: String {
        useChineseWorkbenchText
            ? "这里会显示最近几条提交记录，作为后续日志和仓库浏览器的落点。"
            : "Recent commits will appear here as the first step toward a fuller log and repository browser."
    }

    var repositoryBrowserEmptyDescription: String {
        useChineseWorkbenchText
            ? "刷新工作副本后，这里会显示仓库目录内容。"
            : "Refresh the working copy to load repository directories and files here."
    }

    var loadingRepositoryBrowser: String {
        useChineseWorkbenchText ? "正在加载仓库目录..." : "Loading repository directory..."
    }

    var repositoryBrowserNoEntries: String {
        useChineseWorkbenchText ? "这个目录下还没有条目。" : "This repository directory is empty."
    }

    var repositoryBrowserCopyFailed: String {
        useChineseWorkbenchText ? "复制仓库 URL 失败。" : "Failed to copy the repository URL."
    }

    var repositoryBrowserOpenFailed: String {
        useChineseWorkbenchText ? "无法打开仓库 URL。" : "Unable to open the repository URL."
    }

    var repositoryBrowserCopied: String {
        useChineseWorkbenchText ? "已复制仓库 URL。" : "Repository URL copied."
    }

    var repositoryBrowserOpened: String {
        useChineseWorkbenchText ? "已在外部浏览器中打开仓库 URL。" : "Opened the repository URL in the browser."
    }

    var repositoryBrowserPreviewLoading: String {
        useChineseWorkbenchText ? "正在加载文件预览..." : "Loading file preview..."
    }

    var repositoryBrowserPreviewEmptyDescription: String {
        useChineseWorkbenchText
            ? "点选仓库浏览器里的文件后，这里会显示其内容预览。目录会继续进入下一级。"
            : "Select a file from the repository browser to preview its contents here. Directories continue navigating deeper."
    }

    func repositoryBrowserBinaryPreview(_ name: String, byteCount: Int) -> String {
        if useChineseWorkbenchText {
            return "\(name) 看起来是二进制文件，当前只显示文本预览。文件大小约 \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))。"
        }
        return "\(name) appears to be a binary file. The current preview supports text content only. Size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))."
    }

    func repositoryBrowserPreviewTruncated(_ name: String, byteCount: Int) -> String {
        if useChineseWorkbenchText {
            return "\(name) 内容较大，预览已截断。原始大小约 \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))。"
        }
        return "\(name) is large, so the preview has been truncated. Original size: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))."
    }

    func repositoryBrowserEmptyPreview(_ name: String) -> String {
        useChineseWorkbenchText
            ? "\(name) 当前没有可显示的文本内容。"
            : "\(name) does not currently provide text content to preview."
    }

    var repositoryURLTitle: String {
        useChineseWorkbenchText ? "仓库 URL" : "Repository URL"
    }

    var repositoryRootTitle: String {
        useChineseWorkbenchText ? "仓库根" : "Repository Root"
    }

    var revisionTitle: String {
        useChineseWorkbenchText ? "当前版本" : "Working Revision"
    }

    var lastChangedRevisionTitle: String {
        useChineseWorkbenchText ? "最近提交版本" : "Last Changed Revision"
    }

    var lastChangedByTitle: String {
        useChineseWorkbenchText ? "最近提交者" : "Last Changed By"
    }

    var repositoryUUIDTitle: String {
        useChineseWorkbenchText ? "仓库 UUID" : "Repository UUID"
    }

    var fileTitle: String {
        useChineseWorkbenchText ? "文件" : "File"
    }

    var revisionDetailTitle: String {
        useChineseWorkbenchText ? "版本详情" : "Revision Detail"
    }

    var revisionDetailEmptyDescription: String {
        useChineseWorkbenchText
            ? "点选一条历史记录后，这里会显示提交说明和受影响路径。"
            : "Select a history item to inspect its commit message and changed paths here."
    }

    var loadingRevisionDetail: String {
        useChineseWorkbenchText ? "正在加载版本详情..." : "Loading revision detail..."
    }

    var logMessageTitle: String {
        useChineseWorkbenchText ? "提交说明" : "Commit Message"
    }

    var changedPathsTitle: String {
        useChineseWorkbenchText ? "变更路径" : "Changed Paths"
    }

    var noChangedPathsDescription: String {
        useChineseWorkbenchText ? "这个版本没有列出受影响路径。" : "No changed paths were reported for this revision."
    }

    var revisionDateTitle: String {
        useChineseWorkbenchText ? "提交时间" : "Committed At"
    }

    var unknownAuthorTitle: String {
        useChineseWorkbenchText ? "未知作者" : "Unknown Author"
    }

    var emptyLogMessage: String {
        useChineseWorkbenchText ? "无提交说明" : "No commit message"
    }

    var updatingWorkingCopyText: String {
        useChineseWorkbenchText ? "正在更新工作副本..." : "Updating working copy..."
    }

    var updateFailed: String {
        useChineseWorkbenchText ? "更新工作副本失败。" : "Working copy update failed."
    }

    var cleaningWorkingCopyText: String {
        useChineseWorkbenchText ? "正在清理工作副本锁定状态..." : "Cleaning up working copy locks..."
    }

    var cleanupSucceededText: String {
        useChineseWorkbenchText ? "工作副本清理完成。" : "Working copy cleanup completed."
    }

    var cleanupFailed: String {
        useChineseWorkbenchText ? "清理工作副本失败。" : "Working copy cleanup failed."
    }

    func updateSucceededText(pathCount: Int, revision: Int64?, hasConflicts: Bool) -> String {
        let revisionSuffix: String
        if let revision {
            revisionSuffix = useChineseWorkbenchText ? "，当前版本 r\(revision)" : ", now at r\(revision)"
        } else {
            revisionSuffix = ""
        }

        let conflictSuffix: String
        if hasConflicts {
            conflictSuffix = useChineseWorkbenchText ? "，但存在冲突需要处理。" : ", but conflicts need attention."
        } else {
            conflictSuffix = useChineseWorkbenchText ? "。" : "."
        }

        if useChineseWorkbenchText {
            return "已更新 \(pathCount) 个路径\(revisionSuffix)\(conflictSuffix)"
        }
        return "Updated \(pathCount) path(s)\(revisionSuffix)\(conflictSuffix)"
    }

    func revertingPathsText(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "正在还原 \(pathCount) 个所选路径..."
            : "Reverting \(pathCount) selected path(s)..."
    }

    var revertFailed: String {
        useChineseWorkbenchText ? "还原所选失败。" : "Revert selected failed."
    }

    func revertSucceededText(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "已还原 \(pathCount) 个路径。"
            : "Reverted \(pathCount) path(s)."
    }

    var selectModifiedToRevertError: String {
        useChineseWorkbenchText
            ? "请选择一个或多个需要还原的已修改路径。"
            : "Select one or more modified paths to revert."
    }

    var confirmRevertTitle: String {
        useChineseWorkbenchText ? "确认还原所选更改" : "Confirm Revert Selected"
    }

    func confirmRevertMessage(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "这会撤销 \(pathCount) 个所选路径中的本地修改。这个操作会丢失未提交的内容。"
            : "This will discard local changes in \(pathCount) selected path(s). Uncommitted content will be lost."
    }

    var confirmRevertButtonTitle: String {
        useChineseWorkbenchText ? "继续还原" : "Revert"
    }

    var resolvingPathsTextPrefix: String {
        useChineseWorkbenchText ? "正在将所选冲突标记为已解决" : "Marking selected conflicts as resolved"
    }

    func resolvingPathsText(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "\(resolvingPathsTextPrefix)（\(pathCount) 项）..."
            : "\(resolvingPathsTextPrefix) (\(pathCount) path(s))..."
    }

    var resolveFailed: String {
        useChineseWorkbenchText ? "标记冲突为已解决失败。" : "Resolve selected failed."
    }

    func resolveSucceededText(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "已将 \(pathCount) 个冲突路径标记为已解决。"
            : "Marked \(pathCount) conflicted path(s) as resolved."
    }

    var selectConflictedToResolveError: String {
        useChineseWorkbenchText
            ? "请选择一个或多个有冲突的路径来标记为已解决。"
            : "Select one or more conflicted paths to mark as resolved."
    }

    var confirmResolveTitle: String {
        useChineseWorkbenchText ? "确认标记所选冲突为已解决" : "Confirm Resolve Selected"
    }

    func confirmResolveMessage(pathCount: Int) -> String {
        useChineseWorkbenchText
            ? "这会使用当前工作副本内容，将 \(pathCount) 个所选冲突路径标记为已解决。它不会自动合并差异，只是结束冲突状态。"
            : "This will keep the current working copy contents and mark \(pathCount) selected conflicted path(s) as resolved. It does not merge changes automatically; it only clears the conflict state."
    }

    var confirmResolveButtonTitle: String {
        useChineseWorkbenchText ? "标记为已解决" : "Mark Resolved"
    }

    var confirmCleanupTitle: String {
        useChineseWorkbenchText ? "确认清理工作副本" : "Confirm Working Copy Cleanup"
    }

    var confirmCleanupMessage: String {
        useChineseWorkbenchText
            ? "这会移除工作副本中的 Subversion 写锁。只有在上一次 SVN 操作异常中断或工作副本被锁住时才需要使用。"
            : "This removes Subversion write locks from the working copy. Use it when a previous SVN operation was interrupted or the working copy is stuck in a locked state."
    }

    var confirmCleanupButtonTitle: String {
        useChineseWorkbenchText ? "继续清理" : "Run Cleanup"
    }

    var cancelTitle: String {
        useChineseWorkbenchText ? "取消" : "Cancel"
    }

    var commitChecksTitle: String {
        useChineseWorkbenchText ? "提交检查" : "Commit Checks"
    }

    var advancedCommitChecksTitle: String {
        useChineseWorkbenchText ? "高级提交检查" : "Advanced Checks"
    }

    var afterCommitTitle: String {
        useChineseWorkbenchText ? "在提交之后" : "After Commit"
    }

    var afterCommitDescription: String {
        useChineseWorkbenchText
            ? "提交完成后可以自动刷新状态，右侧保留给 update、锁保持、格式整理和代码分析等后续能力。"
            : "After the commit, the workbench can refresh status automatically. This side rail is reserved for follow-up abilities such as update, lock retention, formatting, and analysis."
    }

    var backgroundMonitorTitle: String {
        useChineseWorkbenchText ? "后台监听" : "Background Monitoring"
    }

    var refreshAfterCommitTitle: String {
        useChineseWorkbenchText ? "提交后刷新状态" : "Refresh Status After Commit"
    }

    var currentSelectionTitle: String {
        useChineseWorkbenchText ? "当前选择" : "Current Selection"
    }

    var lastRefreshTitle: String {
        useChineseWorkbenchText ? "最后刷新" : "Last Refresh"
    }

    var absolutePathTitle: String {
        useChineseWorkbenchText ? "绝对路径" : "Absolute Path"
    }

    var changeStateTitle: String {
        useChineseWorkbenchText ? "变更状态" : "Change State"
    }

    var propertiesStateTitle: String {
        useChineseWorkbenchText ? "属性状态" : "Properties"
    }

    var readyStateTitle: String {
        useChineseWorkbenchText ? "已接通" : "Ready"
    }

    var normalStateTitle: String {
        useChineseWorkbenchText ? "正常" : "Normal"
    }

    func selectedEntriesText(_ count: Int) -> String {
        useChineseWorkbenchText ? "已选 \(count)" : "\(count) selected"
    }

    func groupCountText(_ count: Int) -> String {
        useChineseWorkbenchText ? "\(count) 个文件" : "\(count) file(s)"
    }

    func treeSummaryText(changed: Int, unversioned: Int, total: Int) -> String {
        if useChineseWorkbenchText {
            if changed > 0 || unversioned > 0 {
                return "\(changed) 已修改 · \(unversioned) 未纳管"
            }
            return "\(total) 个条目"
        }

        if changed > 0 || unversioned > 0 {
            return "\(changed) changed · \(unversioned) unversioned"
        }
        return "\(total) item(s)"
    }

    func changedSummaryText(dirty: Int, unversioned: Int) -> String {
        if useChineseWorkbenchText {
            return "\(dirty) 已修改，\(unversioned) 未纳管"
        }
        return "\(dirty) changed, \(unversioned) unversioned"
    }

    func commitFooterHint(selectedCount: Int) -> String {
        if useChineseWorkbenchText {
            return "当前已选 \(selectedCount) 项。填写提交说明后，可以从右下角直接提交所选。"
        }
        return "\(selectedCount) item(s) selected. Add a commit message, then use the bottom-right action to submit the selection."
    }

    var diffPreviewSourceTitle: String {
        useChineseWorkbenchText ? "差异来源" : "Diff Source"
    }

    var externalDiffProfileTitle: String {
        useChineseWorkbenchText ? "外部比较工具" : "External Diff Tool"
    }

    var openInExternalDiff: String {
        useChineseWorkbenchText ? "在外部工具中比较" : "Open in External Diff"
    }

    var externalDiffSelectEntryFirst: String {
        useChineseWorkbenchText ? "请先选择一个已纳管的工作副本条目再打开外部比较。" : "Select a versioned working-copy entry before opening an external diff."
    }

    func externalDiffUnavailableForUnversioned(_ displayName: String) -> String {
        if useChineseWorkbenchText {
            return "\(displayName) 还是未纳管状态，不能直接交给外部 SVN diff 工具。"
        }
        return "\(displayName) is still unversioned, so it cannot be sent to an external SVN diff tool yet."
    }

    func externalDiffDirectoryUnsupported(_ profileName: String) -> String {
        if useChineseWorkbenchText {
            return "\(profileName) 当前未声明目录比较能力。请切换到支持目录 diff 的工具，或先选中文件。"
        }
        return "\(profileName) does not currently advertise directory diff support. Switch to a directory-capable tool or select a file instead."
    }

    func externalDiffReadyHint(_ profileName: String) -> String {
        if useChineseWorkbenchText {
            return "当前会使用 \(profileName) 打开左侧基线内容与右侧工作副本内容。"
        }
        return "This will launch \(profileName) with the base contents on the left and your working copy on the right."
    }

    func openedExternalDiff(_ profileName: String) -> String {
        useChineseWorkbenchText
            ? "已使用 \(profileName) 打开外部比较。"
            : "Opened the external diff in \(profileName)."
    }

    var externalDiffLaunchFailed: String {
        useChineseWorkbenchText ? "外部比较工具启动失败。" : "Launching the external diff tool failed."
    }

    var loadingDiffPreview: String {
        useChineseWorkbenchText ? "正在加载差异预览..." : "Loading diff preview..."
    }

    var diffPreviewUnavailableTitle: String {
        useChineseWorkbenchText ? "当前没有可显示的差异" : "No Diff Available"
    }

    var diffPreviewErrorTitle: String {
        useChineseWorkbenchText ? "差异加载失败" : "Diff Preview Failed"
    }

    var diffPreviewMultipleSelectionNote: String {
        useChineseWorkbenchText
            ? "已选多项时，这里会显示排序后的第一项差异，其余所选项保持在上方供你确认。"
            : "When multiple paths are selected, this panel shows the first selected diff while keeping the rest visible above for confirmation."
    }

    func diffPreviewNoChanges(_ displayName: String) -> String {
        if useChineseWorkbenchText {
            return "\(displayName) 当前没有可显示的文本差异。这个路径可能只有元数据变化，或本次更改不会生成补丁内容。"
        }
        return "\(displayName) does not currently produce a textual diff. This can happen for metadata-only changes or selections that do not yield patch content."
    }

    func diffPreviewUnavailableForUnversioned(_ displayName: String) -> String {
        if useChineseWorkbenchText {
            return "\(displayName) 还是未纳管状态。先把它加入版本控制后，才能看到 SVN diff。"
        }
        return "\(displayName) is still unversioned. Add it to version control before requesting an SVN diff."
    }

    func historyDiffTitle(_ revision: Int64) -> String {
        useChineseWorkbenchText ? "历史版本 r\(revision)" : "Revision r\(revision)"
    }

    func historyDiffNoChanges(_ revision: Int64) -> String {
        useChineseWorkbenchText
            ? "版本 r\(revision) 没有返回可显示的补丁内容。"
            : "Revision r\(revision) did not return any patch content to display."
    }

    // MARK: - Context Menu

    var contextRevert: String {
        useChineseWorkbenchText ? "还原" : "Revert"
    }

    var contextRevertLong: String {
        useChineseWorkbenchText ? "还原本地更改" : "Revert Local Changes"
    }

    var contextRollback: String {
        useChineseWorkbenchText ? "回滚到历史版本" : "Rollback to Revision"
    }

    var contextRollbackToPrev: String {
        useChineseWorkbenchText ? "回滚到上一个版本" : "Rollback to Previous Revision"
    }

    var contextAdd: String {
        useChineseWorkbenchText ? "添加到 SVN" : "Add to SVN"
    }

    var contextIgnore: String {
        useChineseWorkbenchText ? "忽略（添加到 svn:ignore）" : "Ignore (Add to svn:ignore)"
    }

    var ignoreDirectoryTitle: String {
        useChineseWorkbenchText ? "忽略目录" : "Ignore Directory"
    }

    var ignoreDirectoryDescription: String {
        useChineseWorkbenchText
            ? "这将把当前目录（及其内容）加入 svn:ignore 属性，使其不被版本控制。"
            : "This will add the current directory (and its contents) to the svn:ignore property, excluding it from version control."
    }

    var confirmDeleteButtonTitle: String {
        useChineseWorkbenchText ? "确定" : "OK"
    }

    var rollbackNoHistoryError: String {
        useChineseWorkbenchText ? "无法获取历史记录，无法回滚。" : "Unable to get history, cannot rollback."
    }

    var contextDelete: String {
        useChineseWorkbenchText ? "删除" : "Delete"
    }

    var contextResolve: String {
        useChineseWorkbenchText ? "标记为已解决" : "Mark Resolved"
    }

    var contextShowDiff: String {
        useChineseWorkbenchText ? "查看差异" : "Show Diff"
    }

    var contextRevealInFinder: String {
        useChineseWorkbenchText ? "在访达中显示" : "Reveal in Finder"
    }

    var contextCopyPath: String {
        useChineseWorkbenchText ? "复制路径" : "Copy Path"
    }

    var contextDeleteConfirmTitle: String {
        useChineseWorkbenchText ? "确认删除" : "Confirm Delete"
    }

    func contextDeleteConfirmMessage(_ displayName: String) -> String {
        useChineseWorkbenchText
            ? "确定要删除 \"\(displayName)\" 吗？未纳管文件将直接从磁盘移除，已纳管文件会执行 svn delete。"
            : "Are you sure you want to delete \"\(displayName)\"? Unversioned files will be removed from disk; versioned files will be scheduled for svn delete."
    }

    var contextDeleteConfirmButton: String {
        useChineseWorkbenchText ? "删除" : "Delete"
    }

    func deletedPathText(_ name: String) -> String {
        useChineseWorkbenchText ? "已删除 \(name)。" : "Deleted \(name)."
    }

    func ignoredPathText(_ name: String) -> String {
        useChineseWorkbenchText ? "已将 \(name) 加入忽略列表。" : "Added \(name) to the ignore list."
    }

    var diffPreviewPendingNote: String {
        useChineseWorkbenchText
            ? "这里先承接提交前的选择确认和路径预览。下一步会把真实的 SVN diff 视图接进这个区域。"
            : "This panel currently anchors pre-commit selection review and path preview. The next step is wiring the real SVN diff viewer into this space."
    }

    var displaySettingsTitle: String {
        useChineseWorkbenchText ? "显示设置" : "Display Settings"
    }

    var defaultWindowPresetTitle: String {
        useChineseWorkbenchText ? "默认打开方式" : "Default Window Mode"
    }

    var compactWindowPresetTitle: String {
        useChineseWorkbenchText ? "紧凑提交窗" : "Compact Commit Window"
    }

    var spaciousWindowPresetTitle: String {
        useChineseWorkbenchText ? "完整工作台" : "Full Workspace"
    }

    var hideDiffPreviewInCompactTitle: String {
        useChineseWorkbenchText ? "紧凑窗口自动隐藏差异预览" : "Hide diff preview automatically in compact windows"
    }

    var finderLaunchPreferenceHint: String {
        useChineseWorkbenchText
            ? "从访达右键打开时，也会沿用这里的默认窗口模式。"
            : "Finder context-menu launches use the same default window mode."
    }

    var quickOptionsTitle: String {
        useChineseWorkbenchText ? "关键选项" : "Quick Options"
    }

    var compactWindowHint: String {
        useChineseWorkbenchText
            ? "当前是紧凑提交窗，只保留工作路径、更改树、提交消息和关键勾选项。更多信息可在设置或放大窗口后查看。"
            : "You are in the compact commit window. It keeps only the working path, change tree, commit message, and key toggles visible. Expand the window or open Settings for more."
    }

    var compactDiffHiddenHint: String {
        useChineseWorkbenchText
            ? "差异预览已在紧凑窗口中隐藏。需要时可在设置里关闭这条规则，或直接放大窗口。"
            : "Diff preview is hidden in compact windows. Disable this rule in Settings or enlarge the window when you need it."
    }

    var compactWindowModeSummary: String {
        useChineseWorkbenchText ? "紧凑提交模式" : "Compact Commit Mode"
    }

    var collapsedPanelsTitle: String {
        useChineseWorkbenchText ? "已收起模块" : "Collapsed Panels"
    }

    var collapsePanelTitle: String {
        useChineseWorkbenchText ? "收起面板" : "Collapse Panel"
    }

    var restorePanelTitle: String {
        useChineseWorkbenchText ? "恢复面板" : "Restore Panel"
    }

    var showDetails: String {
        useChineseWorkbenchText ? "展开折叠" : "Show Details"
    }

    var hideDetails: String {
        useChineseWorkbenchText ? "收起折叠" : "Hide Details"
    }

    var collapsedWorkspaceTitle: String {
        useChineseWorkbenchText ? "所有模块都已收起" : "All Panels Are Collapsed"
    }

    var collapsedWorkspaceDescription: String {
        useChineseWorkbenchText
            ? "上方会显示已收起模块的恢复条。点一下需要的模块，就能把更改列表、提交消息、差异或选项区重新展开。"
            : "Use the restore bar above to bring back the panels you need, including the change list, commit message, diff preview, or options sidebar."
    }

    var watcherRunningTitle: String {
        useChineseWorkbenchText ? "后台监听中" : "Watcher Active"
    }

    func title(for mode: WorkbenchModel.DiffPreviewMode) -> String {
        switch mode {
        case .workingCopy:
            return useChineseWorkbenchText ? "工作副本" : "Working Copy"
        case .historyRevision:
            return useChineseWorkbenchText ? "历史版本" : "Revision"
        }
    }

    // MARK: - Sidebar

    var sidebarWorkspacesTitle: String {
        useChineseWorkbenchText ? "工作空间" : "Workspaces"
    }

    var sidebarNavigationTitle: String {
        useChineseWorkbenchText ? "导航" : "Navigation"
    }

    var sidebarChangesTitle: String {
        useChineseWorkbenchText ? "更改" : "Changes"
    }

    var sidebarRepositoryTitle: String {
        useChineseWorkbenchText ? "仓库" : "Repository"
    }

    var sidebarHistoryTitle: String {
        useChineseWorkbenchText ? "历史" : "History"
    }

    var addWorkingCopyTitle: String {
        useChineseWorkbenchText ? "添加工作副本" : "Add Working Copy"
    }

    var addWorkingCopyMessage: String {
        useChineseWorkbenchText ? "选择一个 SVN 工作副本文件夹" : "Choose an SVN working copy folder"
    }

    var removeBookmarkTitle: String {
        useChineseWorkbenchText ? "移除" : "Remove"
    }

    var renameBookmarkTitle: String {
        useChineseWorkbenchText ? "重命名书签" : "Rename Bookmark"
    }

    var toggleSidebarTitle: String {
        useChineseWorkbenchText ? "切换侧边栏" : "Toggle Sidebar"
    }

    var sidebarSettingsTitle: String {
        useChineseWorkbenchText ? "侧边栏" : "Sidebar"
    }

    var showSidebarTitle: String {
        useChineseWorkbenchText ? "显示左侧边栏" : "Show Left Sidebar"
    }

    var showSidebarBookmarksTitle: String {
        useChineseWorkbenchText ? "显示书签区" : "Show Bookmarks Section"
    }

    var showSidebarNavigationTitle: String {
        useChineseWorkbenchText ? "显示导航区" : "Show Navigation Section"
    }

    var workspaceSettingsTitle: String {
        useChineseWorkbenchText ? "工作区" : "Workspace"
    }

    var showActionToolbarTitle: String {
        useChineseWorkbenchText ? "显示操作工具条" : "Show Action Toolbar"
    }

    var showChangeListTitle: String {
        useChineseWorkbenchText ? "显示更改列表" : "Show Change List"
    }

    var showCommitMessageTitle: String {
        useChineseWorkbenchText ? "显示提交消息" : "Show Commit Message"
    }

    var showDiffPreviewTitle: String {
        useChineseWorkbenchText ? "显示差异预览" : "Show Diff Preview"
    }

    var showInspectorTitle: String {
        useChineseWorkbenchText ? "显示检查器" : "Show Inspector"
    }

    // MARK: - Context Menu (New Items)

    var contextShowLog: String {
        useChineseWorkbenchText ? "查看日志" : "Show Log"
    }

    var contextBlame: String {
        useChineseWorkbenchText ? "追溯 (Blame)" : "Blame / Annotate"
    }

    var contextLock: String {
        useChineseWorkbenchText ? "锁定" : "Lock"
    }

    var contextUnlock: String {
        useChineseWorkbenchText ? "解锁" : "Unlock"
    }

    var contextRename: String {
        useChineseWorkbenchText ? "重命名" : "Rename"
    }

    var contextCreatePatch: String {
        useChineseWorkbenchText ? "创建补丁" : "Create Patch"
    }

    var contextProperties: String {
        useChineseWorkbenchText ? "属性" : "Properties"
    }

    var historyContextViewDetail: String {
        useChineseWorkbenchText ? "查看详情" : "View Details"
    }

    var historyContextCopyRevision: String {
        useChineseWorkbenchText ? "复制修订号" : "Copy Revision"
    }

    var historyContextCopyAuthor: String {
        useChineseWorkbenchText ? "复制作者" : "Copy Author"
    }

    // MARK: - Notice Texts (New)

    func lockedPathText(_ name: String) -> String {
        useChineseWorkbenchText ? "已锁定 \(name)。" : "Locked \(name)."
    }

    func unlockedPathText(_ name: String) -> String {
        useChineseWorkbenchText ? "已解锁 \(name)。" : "Unlocked \(name)."
    }

    func renamedPathText(_ oldName: String, newName: String) -> String {
        useChineseWorkbenchText ? "已将 \(oldName) 重命名为 \(newName)。" : "Renamed \(oldName) to \(newName)."
    }

    func createdPatchText(_ name: String) -> String {
        useChineseWorkbenchText ? "已为 \(name) 创建补丁。" : "Created patch for \(name)."
    }

    // MARK: - Blame View

    var blameViewTitle: String {
        useChineseWorkbenchText ? "追溯" : "Blame"
    }

    var blameColumnLine: String {
        useChineseWorkbenchText ? "行" : "Line"
    }

    var blameColumnRevision: String {
        useChineseWorkbenchText ? "版本" : "Rev"
    }

    var blameColumnAuthor: String {
        useChineseWorkbenchText ? "作者" : "Author"
    }

    var blameColumnContent: String {
        useChineseWorkbenchText ? "内容" : "Content"
    }

    var blameEmptyState: String {
        useChineseWorkbenchText ? "无追溯数据。" : "No blame data available."
    }

    // MARK: - Properties View

    var propertiesViewTitle: String {
        useChineseWorkbenchText ? "SVN 属性" : "SVN Properties"
    }

    var propertiesNameColumn: String {
        useChineseWorkbenchText ? "属性名" : "Name"
    }

    var propertiesValueColumn: String {
        useChineseWorkbenchText ? "值" : "Value"
    }

    var propertiesAddTitle: String {
        useChineseWorkbenchText ? "添加属性" : "Add Property"
    }

    var propertiesDeleteTitle: String {
        useChineseWorkbenchText ? "删除属性" : "Delete Property"
    }

    var propertiesEmptyState: String {
        useChineseWorkbenchText ? "该路径没有设置 SVN 属性。" : "No SVN properties set on this path."
    }

    // MARK: - Rename Dialog

    var renameDialogTitle: String {
        useChineseWorkbenchText ? "重命名" : "Rename"
    }

    var renameDialogMessage: String {
        useChineseWorkbenchText ? "输入新名称：" : "Enter a new name:"
    }

    var renameDialogConfirm: String {
        useChineseWorkbenchText ? "重命名" : "Rename"
    }

    // MARK: - Settings Sections

    var settingsWindowTitle: String {
        useChineseWorkbenchText ? "窗口" : "Window"
    }

    var settingsPanelsTitle: String {
        useChineseWorkbenchText ? "面板" : "Panels"
    }

    var settingsInspectorSectionsTitle: String {
        useChineseWorkbenchText ? "检查器区域" : "Inspector Sections"
    }

    var settingsToolbarTitle: String {
        useChineseWorkbenchText ? "工具栏" : "Toolbar"
    }

    var settingsSidebarTitle: String {
        useChineseWorkbenchText ? "侧边栏" : "Sidebar"
    }

    var settingsShowChangeList: String {
        useChineseWorkbenchText ? "更改列表" : "Change List"
    }

    var settingsShowCommitMessage: String {
        useChineseWorkbenchText ? "提交消息" : "Commit Message"
    }

    var settingsShowDiffPreview: String {
        useChineseWorkbenchText ? "差异预览" : "Diff Preview"
    }

    var settingsShowInspector: String {
        useChineseWorkbenchText ? "检查器" : "Inspector"
    }

    var settingsShowRepoOverview: String {
        useChineseWorkbenchText ? "仓库概览" : "Repository Overview"
    }

    var settingsShowRepoBrowser: String {
        useChineseWorkbenchText ? "仓库浏览器" : "Repository Browser"
    }

    var settingsShowFilePreview: String {
        useChineseWorkbenchText ? "文件预览" : "File Preview"
    }

    var settingsShowRecentHistory: String {
        useChineseWorkbenchText ? "最近历史" : "Recent History"
    }

    var settingsShowRevisionDetail: String {
        useChineseWorkbenchText ? "版本详情" : "Revision Detail"
    }

    var settingsShowQuickOptions: String {
        useChineseWorkbenchText ? "快捷选项" : "Quick Options"
    }

    var settingsShowStatusSection: String {
        useChineseWorkbenchText ? "状态" : "Status"
    }

    var settingsShowActionToolbar: String {
        useChineseWorkbenchText ? "操作工具栏" : "Action Toolbar"
    }

    var settingsShowBookmarks: String {
        useChineseWorkbenchText ? "书签" : "Bookmarks"
    }

    var settingsShowNavigation: String {
        useChineseWorkbenchText ? "导航" : "Navigation"
    }

    // MARK: - History Full View

    var historyFullViewTitle: String {
        useChineseWorkbenchText ? "提交历史" : "Commit History"
    }

    var historyFullViewEmpty: String {
        useChineseWorkbenchText ? "暂无历史记录。" : "No history available."
    }

    // MARK: - Repository Browser Full View

    var repoBrowserFullViewTitle: String {
        useChineseWorkbenchText ? "仓库浏览器" : "Repository Browser"
    }
}
