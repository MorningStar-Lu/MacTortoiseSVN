import AppKit
import CoreTypes
import FinderSyncBridge
import IntegrationKit
import SVNCore
import SwiftUI

enum WorkbenchPane: String, CaseIterable, Identifiable {
    case changeList
    case commitMessage
    case diffPreview
    case inspector

    var id: String {
        rawValue
    }
}

struct WorkbenchRootView: View {
    @ObservedObject var model: WorkbenchModel
    @State private var hostWindow: NSWindow?
    @State private var lastAppliedWindowPresentationRevision: UUID?
    @State private var isTopBarCollapsed: Bool = false
    @FocusState private var isCommitMessageFocused: Bool
    @AppStorage("MacTortoiseSVN.workbench.ratio.wide.main")
    private var wideMainRatio = 0.58
    @AppStorage("MacTortoiseSVN.workbench.ratio.wide.leftColumn")
    private var wideLeftColumnRatio = 0.62
    @AppStorage("MacTortoiseSVN.workbench.ratio.wide.rightColumn")
    private var wideRightColumnRatio = 0.55
    @AppStorage("MacTortoiseSVN.workbench.ratio.compact.main")
    private var compactMainRatio = 0.56
    @AppStorage("MacTortoiseSVN.workbench.ratio.compact.detail")
    private var compactDetailRatio = 0.52
    @AppStorage("MacTortoiseSVN.workbench.ratio.compact.utility")
    private var compactUtilityRatio = 0.56
    @AppStorage("MacTortoiseSVN.workbench.collapse.changeList")
    private var isChangeListCollapsed = false
    @AppStorage("MacTortoiseSVN.workbench.collapse.commitMessage")
    private var isCommitMessageCollapsed = false
    @AppStorage("MacTortoiseSVN.workbench.collapse.diffPreview")
    private var isDiffPreviewCollapsed = false
    @AppStorage("MacTortoiseSVN.workbench.collapse.inspector")
    private var isInspectorCollapsed = false
    @AppStorage("MacTortoiseSVN.workbench.externalDiffTool")
    private var selectedExternalDiffToolID = ""

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { model.isMonitoring },
            set: { newValue in
                guard newValue != model.isMonitoring else {
                    return
                }
                model.toggleMonitoring()
            }
        )
    }

    private var selectedExternalToolProfile: ExternalToolProfile? {
        if let storedProfile = model.externalTools.first(where: { $0.id == selectedExternalDiffToolID }) {
            return storedProfile
        }

        return model.externalTools.first
    }

    private var externalToolSelectionBinding: Binding<String> {
        Binding(
            get: { selectedExternalToolProfile?.id ?? "" },
            set: { selectedExternalDiffToolID = $0 }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = WorkbenchLayout(size: proxy.size)

            ZStack {
                CommitPalette.windowBackground
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    if model.isSidebarVisible {
                        WorkbenchSidebar(model: model)
                            .frame(width: WorkbenchLayout.sidebarWidth)
                        Divider()
                    }

                    Group {
                        switch model.activeNavigation {
                        case .changes:
                            if layout.usesCompactStack {
                                compactWorkspace(layout: layout)
                            } else {
                                wideWorkspace(layout: layout)
                            }
                        case .repoBrowser:
                            workbenchWorkspace(layout: layout) {
                                RepositoryBrowserFullView(model: model)
                            }
                        case .history:
                            workbenchWorkspace(layout: layout) {
                                HistoryFullView(model: model)
                            }
                        }
                    }
                    .padding(layout.outerPadding)
                }
            }
        }
        .background(.regularMaterial)
        .background(
            WindowAccessor { window in
                hostWindow = window
                if lastAppliedWindowPresentationRevision != model.windowPresentationRevision {
                    model.applyPreferredWindowPresentation(to: window)
                    lastAppliedWindowPresentationRevision = model.windowPresentationRevision
                } else {
                    window.title = localizer.appTitle
                }
            }
        )
        .onChange(of: model.windowPresentationRevision) { _, revision in
            guard let hostWindow else {
                return
            }
            model.applyPreferredWindowPresentation(to: hostWindow)
            lastAppliedWindowPresentationRevision = revision
        }
        .onChange(of: model.language) { _, _ in
            hostWindow?.title = localizer.appTitle
        }
        .tint(CommitPalette.accent)
    }

    // MARK: - Workspace Layouts

    private func wideWorkspace(layout: WorkbenchLayout) -> some View {
        workbenchWorkspace(layout: layout) {
            wideWorkspaceBody(layout: layout)
        }
    }

    private func compactWorkspace(layout: WorkbenchLayout) -> some View {
        workbenchWorkspace(layout: layout) {
            compactWorkspaceBody(layout: layout)
        }
    }

    private func workbenchWorkspace<Content: View>(
        layout: WorkbenchLayout,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: CommitPalette.workspaceGap) {
            topBar(layout: layout)
            collapsedPaneBar(layout: layout)
            
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footerBar(layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Top Bar

    private func topBar(layout: WorkbenchLayout) -> some View {
        VStack(spacing: 10) {
            ViewThatFits {
                HStack(alignment: .center, spacing: 14) {
                    brandBlock
                    sidebarToggleButton
                    topBarCollapseButton
                    Spacer(minLength: 0)
                    if !isTopBarCollapsed {
                        summaryBlock
                        settingsLinkLabel
                        languagePicker
                    } else {
                        settingsLinkLabel
                    }
                }

                if !isTopBarCollapsed {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            brandBlock
                            sidebarToggleButton
                            topBarCollapseButton
                            Spacer(minLength: 0)
                            settingsLinkLabel
                        }

                        HStack(spacing: 12) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                summaryBlock
                            }
                            languagePicker
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        brandBlock
                        sidebarToggleButton
                        topBarCollapseButton
                        Spacer(minLength: 0)
                        settingsLinkLabel
                    }
                }
            }

            if layout.pathBarWraps || layout.usesMinimalCommitMode {
                VStack(alignment: .leading, spacing: 10) {
                    workingCopyField
                    if !isTopBarCollapsed {
                        actionBar(compact: layout.usesMinimalCommitMode)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    workingCopyField
                    if !isTopBarCollapsed {
                        actionBar(compact: false)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .background(CommitPalette.chromeBackground, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.15), Color.clear, Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    private var sidebarToggleButton: some View {
        Button {
            model.isSidebarVisible.toggle()
        } label: {
            Image(systemName: model.isSidebarVisible ? "sidebar.left" : "sidebar.left.hide")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommitPalette.textSecondary)
                .frame(width: 30, height: 30)
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(localizer.toggleSidebarTitle)
    }

    private var topBarCollapseButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                isTopBarCollapsed.toggle()
            }
        } label: {
            Image(systemName: isTopBarCollapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommitPalette.textSecondary)
                .frame(width: 30, height: 30)
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isTopBarCollapsed ? localizer.showDetails : localizer.hideDetails)
    }

    private var brandBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("tmsTUCenter", bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CommitPalette.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.commitWindowTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CommitPalette.textPrimary)

                Text(model.rootPath.isEmpty ? localizer.commitWindowSubtitle : model.rootPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var summaryBlock: some View {
        HStack(spacing: 8) {
            HeaderMetricChip(
                title: localizer.selected,
                value: "\(model.selectedCount)",
                tint: CommitPalette.accent
            )

            HeaderMetricChip(
                title: localizer.dirty,
                value: "\(model.dirtyCount)",
                tint: Color.orange
            )

            HeaderMetricChip(
                title: localizer.unversioned,
                value: "\(model.unversionedCount)",
                tint: Color.blue
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workingCopyField: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(CommitPalette.textSecondary)

            TextField(localizer.chooseWorkingCopyPlaceholder, text: $model.rootPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .onSubmit {
                    model.refreshSnapshot(forceFullRefresh: true)
                }

            Button(localizer.chooseFolder) {
                model.chooseWorkingCopy()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionBar(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ToolbarActionButton(
                    title: localizer.refreshSnapshot,
                    symbol: "arrow.clockwise",
                    isEnabled: model.canRefresh
                ) {
                    model.refreshSnapshot(forceFullRefresh: true)
                }

                ToolbarActionButton(
                    title: localizer.refreshIfNeeded,
                    symbol: "arrow.triangle.2.circlepath",
                    isEnabled: model.canRefresh
                ) {
                    model.refreshSnapshot(forceFullRefresh: false)
                }

                ToolbarActionButton(
                    title: localizer.updateWorkingCopy,
                    symbol: "arrow.down.circle",
                    isEnabled: model.canUpdateWorkingCopy
                ) {
                    model.updateWorkingCopy()
                }

                ToolbarActionButton(
                    title: localizer.cleanupWorkingCopy,
                    symbol: "wrench.and.screwdriver",
                    isEnabled: model.canCleanupWorkingCopy
                ) {
                    model.cleanupWorkingCopy()
                }

                ToolbarActionButton(
                    title: model.isMonitoring ? localizer.stopWatcher : localizer.startWatcher,
                    symbol: model.isMonitoring ? "eye.slash" : "eye",
                    isEnabled: !model.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isBusy
                ) {
                    model.toggleMonitoring()
                }

                ToolbarActionButton(
                    title: localizer.selectActionable,
                    symbol: "checkmark.square",
                    isEnabled: !model.entries.isEmpty
                ) {
                    model.selectAllActionable()
                }

                ToolbarActionButton(
                    title: localizer.clearSelection,
                    symbol: "eraser",
                    isEnabled: !model.selectedPaths.isEmpty
                ) {
                    model.clearSelection()
                }

                ToolbarActionButton(
                    title: localizer.revertSelected,
                    symbol: "arrow.uturn.backward.circle",
                    isEnabled: model.canRevertSelected
                ) {
                    model.revertSelected()
                }

                ToolbarActionButton(
                    title: localizer.resolveSelected,
                    symbol: "checkmark.circle",
                    isEnabled: model.canResolveSelected
                ) {
                    model.resolveSelected()
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
    }

    private var languagePicker: some View {
        Picker(localizer.languageTitle, selection: $model.language) {
            ForEach(MacSVNLanguage.allCases) { language in
                Text(language.nativeDisplayName).tag(language)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
    }

    private var settingsLinkLabel: some View {
        SettingsLink {
            Label(localizer.displaySettingsTitle, systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommitPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pane Management

    private func showsDiffPreview(in layout: WorkbenchLayout) -> Bool {
        !layout.usesMinimalCommitMode || !model.hideDiffPreviewInCompactWindow
    }

    private func paneTitle(_ pane: WorkbenchPane) -> String {
        switch pane {
        case .changeList:
            return localizer.changeListPanelTitle
        case .commitMessage:
            return localizer.commitMessagePanelTitle
        case .diffPreview:
            return localizer.diffPreviewTitle
        case .inspector:
            return localizer.subversionOptionsTitle
        }
    }

    private func paneSymbol(_ pane: WorkbenchPane) -> String {
        switch pane {
        case .changeList:
            return "folder.badge.gearshape"
        case .commitMessage:
            return "square.and.pencil"
        case .diffPreview:
            return "doc.text.magnifyingglass"
        case .inspector:
            return "slider.horizontal.3"
        }
    }

    private func isPaneCollapsed(_ pane: WorkbenchPane) -> Bool {
        switch pane {
        case .changeList:
            return isChangeListCollapsed
        case .commitMessage:
            return isCommitMessageCollapsed
        case .diffPreview:
            return isDiffPreviewCollapsed
        case .inspector:
            return isInspectorCollapsed
        }
    }

    private func setPaneCollapsed(_ pane: WorkbenchPane, _ collapsed: Bool) {
        switch pane {
        case .changeList:
            isChangeListCollapsed = collapsed
        case .commitMessage:
            isCommitMessageCollapsed = collapsed
        case .diffPreview:
            isDiffPreviewCollapsed = collapsed
        case .inspector:
            isInspectorCollapsed = collapsed
        }
    }

    private func isPaneAvailable(_ pane: WorkbenchPane, in layout: WorkbenchLayout) -> Bool {
        switch pane {
        case .diffPreview:
            return showsDiffPreview(in: layout)
        case .changeList, .commitMessage, .inspector:
            return true
        }
    }

    private func isPaneVisible(_ pane: WorkbenchPane, in layout: WorkbenchLayout) -> Bool {
        isPaneAvailable(pane, in: layout) && !isPaneCollapsed(pane)
    }

    private func hasVisiblePane(_ panes: [WorkbenchPane], in layout: WorkbenchLayout) -> Bool {
        panes.contains { isPaneVisible($0, in: layout) }
    }

    private func collapsedPanes(in layout: WorkbenchLayout) -> [WorkbenchPane] {
        WorkbenchPane.allCases.filter { isPaneAvailable($0, in: layout) && isPaneCollapsed($0) }
    }

    @ViewBuilder
    private func collapsedPaneBar(layout: WorkbenchLayout) -> some View {
        let hiddenPanes = collapsedPanes(in: layout)

        if !hiddenPanes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text(localizer.collapsedPanelsTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CommitPalette.textSecondary)

                    ForEach(hiddenPanes) { pane in
                        Button {
                            setPaneCollapsed(pane, false)
                        } label: {
                            Label(paneTitle(pane), systemImage: paneSymbol(pane))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CommitPalette.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(CommitPalette.toolbarFill, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(localizer.restorePanelTitle)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
            .background(CommitPalette.chromeBackground, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                    .strokeBorder(CommitPalette.border, lineWidth: 0.5)
            )
        }
    }

    private func panelCollapseButton(for pane: WorkbenchPane) -> some View {
        Button {
            setPaneCollapsed(pane, true)
        } label: {
            Image(systemName: "minus.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CommitPalette.textSecondary)
                .frame(width: 28, height: 28)
                .background(CommitPalette.toolbarFill, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(localizer.collapsePanelTitle)
    }

    // MARK: - Wide Workspace Body

    @ViewBuilder
    private func wideWorkspaceBody(layout: WorkbenchLayout) -> some View {
        let showsLeftColumn = hasVisiblePane([.changeList, .commitMessage], in: layout)
        let showsRightColumn = hasVisiblePane([.diffPreview, .inspector], in: layout)

        if showsLeftColumn && showsRightColumn {
            HStack(alignment: .top, spacing: CommitPalette.workspaceGap) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if isPaneVisible(.changeList, in: layout) {
                            changeListPanel.frame(minHeight: 250)
                        }
                        if isPaneVisible(.commitMessage, in: layout) {
                            commitMessagePanel
                        }
                    }
                }
                .frame(width: 440)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if isPaneVisible(.diffPreview, in: layout) { diffPreviewPanel }
                        if isPaneVisible(.inspector, in: layout) { inspectorSidebar }
                    }
                }
            }
        } else if showsLeftColumn {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if isPaneVisible(.changeList, in: layout) {
                        changeListPanel.frame(minHeight: 350)
                    }
                    if isPaneVisible(.commitMessage, in: layout) {
                        commitMessagePanel
                    }
                }
            }
        } else if showsRightColumn {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if isPaneVisible(.diffPreview, in: layout) { diffPreviewPanel }
                    if isPaneVisible(.inspector, in: layout) { inspectorSidebar }
                }
            }
        } else {
            collapsedWorkspacePlaceholder
        }
    }

    // MARK: - Compact Workspace Body

    @ViewBuilder
    private func compactWorkspaceBody(layout: WorkbenchLayout) -> some View {
        let showsPrimaryColumn = hasVisiblePane([.changeList, .commitMessage], in: layout)
        let showsDetailColumn = hasVisiblePane([.diffPreview, .inspector], in: layout)

        if showsPrimaryColumn || showsDetailColumn {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if isPaneVisible(.changeList, in: layout) {
                        changeListPanel.frame(minHeight: 250)
                    }
                    if isPaneVisible(.commitMessage, in: layout) {
                        commitMessagePanel
                    }
                    if isPaneVisible(.diffPreview, in: layout) { diffPreviewPanel }
                    if isPaneVisible(.inspector, in: layout) { inspectorSidebar }
                }
                .padding(.trailing, 4)
            }
        } else {
            collapsedWorkspacePlaceholder
        }
    }


    private var collapsedWorkspacePlaceholder: some View {
        CommitPanel(title: localizer.collapsedWorkspaceTitle) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localizer.collapsedWorkspaceDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizer.collapsedPanelsTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CommitPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }

    // MARK: - Footer Bar

    private func footerBar(layout: WorkbenchLayout) -> some View {
        ViewThatFits {
            HStack(spacing: 14) {
                footerStatusRow

                Spacer(minLength: 12)

                commitActionRow
                    .frame(width: 430)
            }

            VStack(alignment: .leading, spacing: 12) {
                footerStatusRow

                ScrollView(.horizontal, showsIndicators: false) {
                    commitActionRow
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .background(CommitPalette.chromeBackground, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.border, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var footerStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                InlineCapsule(
                    text: localizer.selectedEntriesText(model.selectedCount),
                    tint: CommitPalette.accent
                )

                InlineCapsule(
                    text: localizer.changedSummaryText(dirty: model.dirtyCount, unversioned: model.unversionedCount),
                    tint: Color.orange
                )

                if model.isMonitoring {
                    InlineCapsule(text: localizer.watcherRunningTitle, tint: Color.green)
                }
            }
        }
    }

    // MARK: - Change List Panel

    private var changeListPanel: some View {
        CommitPanel(
            title: localizer.changeListPanelTitle,
            headerTrailing: {
                HStack(spacing: 10) {
                    Text(localizer.selectedEntriesText(model.selectedCount))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommitPalette.textSecondary)

                    panelCollapseButton(for: .changeList)
                }
            }
        ) {
            if model.entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localizer.noEntriesLoadedTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Text(localizer.noEntriesLoadedDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            } else {
                List(model.treeNodes, children: \.children) { node in
                    ChangeOutlineRow(
                        node: node,
                        localizer: localizer,
                        selectedPaths: model.selectedPaths,
                        onSetNodeSelection: { targetNode, isSelected in
                            model.setSelection(
                                for: model.actionablePaths(for: targetNode),
                                isSelected: isSelected
                            )
                            isCommitMessageFocused = true
                        },
                        onToggleEntry: { entryPath in
                            model.toggleSelection(for: entryPath)
                            isCommitMessageFocused = true
                        }
                    )
                    .contextMenu {
                        changeListContextMenu(for: node)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(
                        node.selectionState(in: model.selectedPaths) == .none
                            ? CommitPalette.listBackground
                            : CommitPalette.rowSelection
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(CommitPalette.listBackground)
                .environment(\.defaultMinListRowHeight, 34)
            }
        }
    }

    // MARK: - Change List Context Menu

    @ViewBuilder
    private func changeListContextMenu(for node: ChangeTreeNode) -> some View {
        let entry = node.entry
        let path = node.absolutePath

        if let entry {
            Button {
                model.selectAndShowDiff(for: path)
            } label: {
                Label(localizer.contextShowDiff, systemImage: "doc.text.magnifyingglass")
            }
            .disabled(entry.status == .unversioned)

            Divider()

            Button {
                model.revertPath(path)
            } label: {
                Label(localizer.contextRevert, systemImage: "arrow.uturn.backward")
            }
            .disabled(!entry.canRevert)

            Button {
                model.rollbackPath(path)
            } label: {
                Label(localizer.contextRollback, systemImage: "arrow.uturn.backward.2.circle")
            }
            .disabled(entry.status == .unversioned)

            Button {
                model.addPath(path)
            } label: {
                Label(localizer.contextAdd, systemImage: "plus.circle")
            }
            .disabled(!entry.canAdd)

            Button {
                model.resolvePath(path)
            } label: {
                Label(localizer.contextResolve, systemImage: "checkmark.circle")
            }
            .disabled(!entry.canResolve)

            Divider()

            if entry.isDirectory {
                Button {
                    model.ignoreDirectory(path)
                } label: {
                    Label(localizer.contextIgnore, systemImage: "folder.badge.questionmark")
                }
                .disabled(entry.status == .unversioned)
            } else {
                Button {
                    model.ignorePath(path)
                } label: {
                    Label(localizer.contextIgnore, systemImage: "eye.slash")
                }
                .disabled(entry.status == .unversioned)
            }

            Button(role: .destructive) {
                model.deletePath(path)
            } label: {
                Label(localizer.contextDelete, systemImage: "trash")
            }

            Divider()
        }

        Button {
            model.revealInFinder(path)
        } label: {
            Label(localizer.contextRevealInFinder, systemImage: "folder")
        }

        Button {
            model.copyPathToClipboard(path)
        } label: {
            Label(localizer.contextCopyPath, systemImage: "doc.on.doc")
        }

        if let entry, !entry.isDirectory {
            Divider()

            Button {
                model.blamePath(path)
            } label: {
                Label(localizer.contextBlame, systemImage: "text.magnifyingglass")
            }
            .disabled(entry.status == .unversioned)

            Button {
                model.showPropertiesForPath(path)
            } label: {
                Label(localizer.contextProperties, systemImage: "list.bullet.rectangle")
            }

            Button {
                model.createPatchForPath(path)
            } label: {
                Label(localizer.contextCreatePatch, systemImage: "doc.badge.ellipsis")
            }
            .disabled(entry.status == .unversioned)

            Divider()

            Button {
                model.lockPath(path)
            } label: {
                Label(localizer.contextLock, systemImage: "lock")
            }

            Button {
                model.unlockPath(path)
            } label: {
                Label(localizer.contextUnlock, systemImage: "lock.open")
            }
        } else if let entry, entry.isDirectory {
            Divider()

            Button {
                model.showPropertiesForPath(path)
            } label: {
                Label(localizer.contextProperties, systemImage: "list.bullet.rectangle")
            }
        }
    }

    // MARK: - Commit Message Panel

    private var commitMessagePanel: some View {
        CommitPanel(
            title: localizer.commitMessagePanelTitle,
            headerTrailing: {
                HStack(spacing: 10) {
                    Text(localizer.selectedEntriesText(model.selectedCount))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CommitPalette.textMuted)

                    panelCollapseButton(for: .commitMessage)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.statusMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    if let lastRefreshDate = model.lastRefreshDate {
                        Text(localizer.lastRefreshText(
                            lastRefreshDate.formatted(date: .omitted, time: .standard)
                        ))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                    }

                    if let lastError = model.lastError {
                        Text(lastError)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(CommitPalette.error)
                    }
                }

                CommitMessageEditor(
                    text: $model.commitMessage,
                    placeholder: localizer.commitMessagePlaceholder,
                    isFocused: $isCommitMessageFocused
                )

                Text(localizer.commitFooterHint(selectedCount: model.selectedCount))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
    }

    private var minimalCommitPanel: some View {
        CommitPanel(
            title: localizer.commitMessagePanelTitle,
            headerTrailing: {
                HStack(spacing: 10) {
                    Text(localizer.compactWindowModeSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CommitPalette.textMuted)

                    panelCollapseButton(for: .commitMessage)
                }
            }
        ) {
            ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CommitPalette.textPrimary)

                    if let lastRefreshDate = model.lastRefreshDate {
                        Text(localizer.lastRefreshText(
                            lastRefreshDate.formatted(date: .omitted, time: .shortened)
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(CommitPalette.textSecondary)
                    }

                    if let lastError = model.lastError {
                        Text(lastError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CommitPalette.error)
                    }
                }

                compactQuickOptions

                CommitMessageEditor(
                    text: $model.commitMessage,
                    placeholder: localizer.commitMessagePlaceholder,
                    isFocused: $isCommitMessageFocused
                )
                .frame(height: 116)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            InlineCapsule(text: localizer.selectedEntriesText(model.selectedCount), tint: CommitPalette.accent)
                            InlineCapsule(text: localizer.changedSummaryText(dirty: model.dirtyCount, unversioned: model.unversionedCount), tint: Color.orange)
                        }

                        Text(localizer.compactWindowHint)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CommitPalette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    commitActionRow
                        .frame(width: 340)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            }
        }
    }

    private var compactQuickOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.quickOptionsTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CommitPalette.textPrimary)

            ViewThatFits {
                HStack(spacing: 18) {
                    Toggle(localizer.backgroundMonitorTitle, isOn: monitoringBinding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))

                    Toggle(localizer.refreshAfterCommitTitle, isOn: $model.refreshStatusAfterCommit)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(localizer.backgroundMonitorTitle, isOn: monitoringBinding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))

                    Toggle(localizer.refreshAfterCommitTitle, isOn: $model.refreshStatusAfterCommit)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            if model.hideDiffPreviewInCompactWindow {
                Text(localizer.compactDiffHiddenHint)
                    .font(.system(size: 11))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Commit Action Row

    private var commitActionRow: some View {
        HStack(spacing: 10) {
            Button(localizer.clearSelection) {
                model.clearSelection()
            }
            .buttonStyle(.plain)
            .disabled(model.selectedPaths.isEmpty)
            .modifier(FooterActionButtonModifier(kind: .secondary))

            Button(localizer.addSelected) {
                model.addSelected()
            }
            .buttonStyle(.plain)
            .disabled(!model.canAddSelected)
            .modifier(FooterActionButtonModifier(kind: .secondary))

            Button(localizer.commitSelected) {
                model.commitSelected()
            }
            .buttonStyle(.plain)
            .disabled(!model.canCommitSelected)
            .keyboardShortcut(.return, modifiers: [.command])
            .modifier(FooterActionButtonModifier(kind: .primary))
        }
    }

    // MARK: - Diff Preview Panel

    private var diffPreviewPanel: some View {
        CommitPanel(
            title: localizer.diffPreviewTitle,
            headerTrailing: {
                HStack(spacing: 10) {
                    if model.effectiveDiffPreviewMode == .workingCopy, let entry = model.primarySelectedEntry {
                        StatusBadge(status: entry.status, localizer: localizer)
                    } else if model.effectiveDiffPreviewMode == .historyRevision, let entry = model.selectedHistoryEntry {
                        InlineCapsule(text: "r\(entry.revision)", tint: CommitPalette.accent)
                    }

                    panelCollapseButton(for: .diffPreview)
                }
            }
        ) {
            if model.effectiveDiffPreviewMode == .workingCopy, let entry = model.primarySelectedEntry {
                workingCopyDiffPreviewBody(entry: entry)
            } else if model.effectiveDiffPreviewMode == .historyRevision, let historyEntry = model.selectedHistoryEntry {
                historyDiffPreviewBody(entry: historyEntry)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localizer.diffPreviewEmptyTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Text(localizer.diffPreviewEmptyDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
        }
    }

    private func workingCopyDiffPreviewBody(entry: WorkbenchModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Text(entry.relativePath)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                if entry.item.propertyModified {
                    InlineCapsule(text: localizer.props, tint: .orange)
                }

                if entry.isDirectory {
                    InlineCapsule(text: localizer.folder, tint: .gray)
                }
            }

            HStack(spacing: 12) {
                DiffMetadataCell(
                    title: localizer.currentSelectionTitle,
                    value: localizer.selectedEntriesText(model.selectedEntries.count)
                )
                DiffMetadataCell(
                    title: localizer.changeStateTitle,
                    value: localizer.title(for: entry.status)
                )
                DiffMetadataCell(
                    title: localizer.propertiesStateTitle,
                    value: entry.item.propertyModified ? localizer.props : localizer.normalStateTitle
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.absolutePathTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)

                Text(entry.id)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .textSelection(.enabled)
            }

            if model.selectedEntries.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.selectedEntries.prefix(10), id: \.id) { selectedEntry in
                                InlineCapsule(
                                    text: selectedEntry.displayName,
                                    tint: selectedEntry.status.color
                                )
                            }
                        }
                    }

                    Text(localizer.diffPreviewMultipleSelectionNote)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textMuted)
                }
            }

            diffPreviewToolbar(entry: entry)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        }

        diffPreviewContentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func historyDiffPreviewBody(entry: SVNHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.historyDiffTitle(entry.revision))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Text(historyDiffSubtitle(for: entry))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                }

                Spacer(minLength: 0)

                InlineCapsule(
                    text: entry.author ?? localizer.unknownAuthorTitle,
                    tint: Color.orange
                )
            }

            if let detail = model.selectedHistoryEntryDetail {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizer.logMessageTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.textMuted)

                    Text(historyDiffMessage(for: detail.entry))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !detail.changedPaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detail.changedPaths.prefix(10)) { changedPath in
                                InlineCapsule(
                                    text: "\(changedPath.action.uppercased()) \(changedPath.path)",
                                    tint: historyChangedPathTint(changedPath.action)
                                )
                            }
                        }
                    }
                }
            }

            diffPreviewToolbar(entry: nil)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        }

        diffPreviewContentBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func diffPreviewToolbar(entry: WorkbenchModel.Entry?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits {
                HStack(alignment: .center, spacing: 12) {
                    diffPreviewModePicker

                    Spacer(minLength: 0)

                    externalDiffToolbar(entry: entry)
                }

                VStack(alignment: .leading, spacing: 10) {
                    diffPreviewModePicker
                    externalDiffToolbar(entry: entry)
                }
            }

            if let entry, let externalDiffHint = externalDiffHint(for: entry) {
                Text(externalDiffHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var diffPreviewModePicker: some View {
        if model.availableDiffPreviewModes.count > 1 {
            Picker(localizer.diffPreviewSourceTitle, selection: diffPreviewModeBinding) {
                ForEach(model.availableDiffPreviewModes) { mode in
                    Text(localizer.title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    @ViewBuilder
    private func externalDiffToolbar(entry: WorkbenchModel.Entry?) -> some View {
        if let entry {
            if model.externalTools.isEmpty {
                Text(localizer.loadingDiffProfiles)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
            } else {
                ViewThatFits {
                    HStack(spacing: 10) {
                        externalDiffProfilePicker
                        externalDiffLaunchButton(for: entry)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        externalDiffProfilePicker
                        externalDiffLaunchButton(for: entry)
                    }
                }
            }
        }
    }

    private var externalDiffProfilePicker: some View {
        Picker(localizer.externalDiffProfileTitle, selection: externalToolSelectionBinding) {
            ForEach(model.externalTools) { profile in
                Text(profile.displayName).tag(profile.id)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 190)
    }

    private func externalDiffLaunchButton(for entry: WorkbenchModel.Entry) -> some View {
        Button(localizer.openInExternalDiff) {
            if let selectedExternalToolProfile {
                model.openSelectedEntryInExternalDiff(using: selectedExternalToolProfile)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canOpenExternalDiff(for: entry))
        .modifier(FooterActionButtonModifier(kind: .secondary))
        .frame(width: 170)
    }

    private var diffPreviewContentBody: some View {
        Group {
            if model.isLoadingDiffPreview {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text(localizer.loadingDiffPreview)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(
                    CommitPalette.groupBackground,
                    in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                )
            } else if let diffPreviewError = model.diffPreviewError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizer.diffPreviewErrorTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.error)

                    Text(diffPreviewError)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(
                    CommitPalette.groupBackground,
                    in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                )
            } else if let selectedDiffText = model.selectedDiffText {
                DiffTextPreview(text: selectedDiffText)
            } else if let diffPreviewMessage = model.diffPreviewMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizer.diffPreviewUnavailableTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Text(diffPreviewMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(
                    CommitPalette.groupBackground,
                    in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                )
            }
        }
    }

    private var diffPreviewModeBinding: Binding<WorkbenchModel.DiffPreviewMode> {
        Binding(
            get: { model.effectiveDiffPreviewMode ?? .workingCopy },
            set: { model.setPreferredDiffPreviewMode($0) }
        )
    }

    private func canOpenExternalDiff(for entry: WorkbenchModel.Entry) -> Bool {
        guard let selectedExternalToolProfile else {
            return false
        }

        guard !model.isLaunchingExternalDiff else {
            return false
        }

        guard entry.status != .unversioned else {
            return false
        }

        if entry.isDirectory && !selectedExternalToolProfile.supportsDirectoryDiff {
            return false
        }

        return true
    }

    private func externalDiffHint(for entry: WorkbenchModel.Entry) -> String? {
        guard let selectedExternalToolProfile else {
            return nil
        }

        if entry.status == .unversioned {
            return localizer.externalDiffUnavailableForUnversioned(entry.displayName)
        }

        if entry.isDirectory && !selectedExternalToolProfile.supportsDirectoryDiff {
            return localizer.externalDiffDirectoryUnsupported(selectedExternalToolProfile.displayName)
        }

        return localizer.externalDiffReadyHint(selectedExternalToolProfile.displayName)
    }

    private func historyDiffSubtitle(for entry: SVNHistoryEntry) -> String {
        let author = entry.author ?? localizer.unknownAuthorTitle
        if let date = entry.date {
            return "\(author) · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return author
    }

    private func historyDiffMessage(for entry: SVNHistoryEntry) -> String {
        let trimmed = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localizer.emptyLogMessage : trimmed
    }

    private func historyChangedPathTint(_ action: String) -> Color {
        switch action.uppercased() {
        case "A":
            return Color.green
        case "D":
            return Color.red
        case "R":
            return Color.mint
        case "M":
            return Color.orange
        default:
            return CommitPalette.textSecondary
        }
    }

    // MARK: - Inspector Sidebar

    private var inspectorSidebar: some View {
        CommitPanel(
            title: localizer.subversionOptionsTitle,
            headerTrailing: {
                panelCollapseButton(for: .inspector)
            }
        ) {
            ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                InspectorSection(title: localizer.repositoryOverviewTitle) {
                    if let summary = model.repositorySummary {
                        SidebarInfoRow(
                            title: localizer.repositoryURLTitle,
                            value: summary.repositoryURL
                        )

                        if let repositoryRootURL = summary.repositoryRootURL {
                            SidebarInfoRow(
                                title: localizer.repositoryRootTitle,
                                value: repositoryRootURL
                            )
                        }

                        SidebarInfoRow(
                            title: localizer.revisionTitle,
                            value: "r\(summary.revision)"
                        )

                        if let lastChangedRevision = summary.lastChangedRevision {
                            SidebarInfoRow(
                                title: localizer.lastChangedRevisionTitle,
                                value: "r\(lastChangedRevision)"
                            )
                        }

                        SidebarInfoRow(
                            title: localizer.lastChangedByTitle,
                            value: summary.lastChangedAuthor ?? localizer.unknownAuthorTitle
                        )

                        if let workingCopyUUID = summary.workingCopyUUID {
                            SidebarInfoRow(
                                title: localizer.repositoryUUIDTitle,
                                value: workingCopyUUID
                            )
                        }
                    } else {
                        Text(localizer.repositoryOverviewEmptyDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InspectorSection(title: localizer.repositoryBrowserTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            ToolbarIconButton(
                                symbol: "arrow.uturn.backward.circle",
                                title: localizer.repositoryBrowserUp,
                                isEnabled: model.canBrowseParentRepositoryDirectory
                            ) {
                                model.browseParentRepositoryDirectory()
                            }

                            ToolbarIconButton(
                                symbol: "point.topleft.down.curvedto.point.bottomright.up",
                                title: localizer.repositoryBrowserCurrentLocation,
                                isEnabled: model.canBrowseWorkingCopyLocation
                            ) {
                                model.browseWorkingCopyRepositoryLocation()
                            }

                            ToolbarIconButton(
                                symbol: "tray.full",
                                title: localizer.repositoryBrowserRoot,
                                isEnabled: model.canBrowseRepositoryRoot
                            ) {
                                model.browseRepositoryRoot()
                            }

                            ToolbarIconButton(
                                symbol: "arrow.clockwise",
                                title: localizer.refreshSnapshot,
                                isEnabled: !model.isLoadingRepositoryBrowser
                            ) {
                                model.refreshRepositoryBrowser()
                            }

                            ToolbarIconButton(
                                symbol: "doc.on.doc",
                                title: localizer.repositoryBrowserCopyURL,
                                isEnabled: model.repositoryBrowserListing != nil || model.repositoryBrowserWorkingCopyURL != nil
                            ) {
                                model.copyCurrentRepositoryBrowserLocation()
                            }

                            ToolbarIconButton(
                                symbol: "safari",
                                title: localizer.repositoryBrowserOpenInBrowser,
                                isEnabled: model.repositoryBrowserListing != nil || model.repositoryBrowserWorkingCopyURL != nil
                            ) {
                                model.openCurrentRepositoryBrowserLocationInBrowser()
                            }
                        }

                        SidebarInfoRow(
                            title: localizer.repositoryBrowserLocationTitle,
                            value: model.repositoryBrowserCurrentURLText
                        )

                        if let repositoryBrowserError = model.repositoryBrowserError {
                            Text(repositoryBrowserError)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(CommitPalette.error)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if model.isLoadingRepositoryBrowser {
                            Text(localizer.loadingRepositoryBrowser)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(CommitPalette.textSecondary)
                        } else if let listing = model.repositoryBrowserListing {
                            if listing.entries.isEmpty {
                                Text(localizer.repositoryBrowserNoEntries)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(CommitPalette.textSecondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(listing.entries.prefix(18)) { entry in
                                        RepositoryBrowserEntryRow(
                                            entry: entry,
                                            localizer: localizer,
                                            isSelected: model.selectedRepositoryBrowserEntry?.id == entry.id,
                                            onPrimaryAction: {
                                                model.selectRepositoryBrowserEntry(entry)
                                            },
                                            onOpenDirectory: {
                                                model.openRepositoryBrowserEntry(entry)
                                            },
                                            onCopyURL: {
                                                model.copyRepositoryBrowserEntryURL(entry)
                                            },
                                            onOpenInBrowser: {
                                                model.openRepositoryBrowserEntryInBrowser(entry)
                                            }
                                        )
                                        .contextMenu {
                                            if entry.isDirectory {
                                                Button {
                                                    model.openRepositoryBrowserEntry(entry)
                                                } label: {
                                                    Label(localizer.repositoryBrowserOpenDirectory, systemImage: "folder.fill")
                                                }
                                                Divider()
                                            }
                                            Button {
                                                model.copyRepositoryBrowserEntryURL(entry)
                                            } label: {
                                                Label(localizer.repositoryBrowserCopyURL, systemImage: "doc.on.doc")
                                            }
                                            Button {
                                                model.openRepositoryBrowserEntryInBrowser(entry)
                                            } label: {
                                                Label(localizer.repositoryBrowserOpenInBrowser, systemImage: "safari")
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(localizer.repositoryBrowserEmptyDescription)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(CommitPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                InspectorSection(title: localizer.repositoryBrowserPreviewTitle) {
                    if model.isLoadingRepositoryBrowserPreview {
                        Text(localizer.repositoryBrowserPreviewLoading)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                    } else if let repositoryBrowserPreviewError = model.repositoryBrowserPreviewError {
                        Text(repositoryBrowserPreviewError)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(CommitPalette.error)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let selectedRepositoryBrowserEntry = model.selectedRepositoryBrowserEntry {
                        VStack(alignment: .leading, spacing: 10) {
                            SidebarInfoRow(
                                title: localizer.fileTitle,
                                value: selectedRepositoryBrowserEntry.name
                            )

                            if let repositoryBrowserPreviewMessage = model.repositoryBrowserPreviewMessage {
                                Text(repositoryBrowserPreviewMessage)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(CommitPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let repositoryBrowserPreviewText = model.repositoryBrowserPreviewText {
                                DiffTextPreview(text: repositoryBrowserPreviewText)
                                    .frame(minHeight: 180)
                            }
                        }
                    } else {
                        Text(localizer.repositoryBrowserPreviewEmptyDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InspectorSection(title: localizer.recentHistoryTitle) {
                    if let recentHistoryError = model.recentHistoryError {
                        Text(recentHistoryError)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(CommitPalette.error)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if model.recentHistory.isEmpty {
                        Text(localizer.recentHistoryEmptyDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.recentHistory.prefix(6)) { entry in
                                Button {
                                    model.showHistoryDetail(for: entry.revision)
                                } label: {
                                    HistoryEntryRow(
                                        entry: entry,
                                        localizer: localizer,
                                        isSelected: model.isHistoryEntrySelected(entry)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                InspectorSection(title: localizer.revisionDetailTitle) {
                    if model.isLoadingHistoryDetail {
                        Text(localizer.loadingRevisionDetail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                    } else if let detail = model.selectedHistoryEntryDetail {
                        RevisionDetailCard(detail: detail, localizer: localizer)
                    } else {
                        Text(localizer.revisionDetailEmptyDescription)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                InspectorSection(title: localizer.quickOptionsTitle) {
                    Toggle(localizer.refreshAfterCommitTitle, isOn: $model.refreshStatusAfterCommit)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 14, weight: .medium, design: .rounded))

                    Toggle(localizer.backgroundMonitorTitle, isOn: monitoringBinding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }

                InspectorSection(title: localizer.status) {
                    SidebarInfoRow(
                        title: localizer.workingCopy,
                        value: model.rootPath.isEmpty ? "—" : model.rootPath
                    )

                    SidebarInfoRow(
                        title: localizer.status,
                        value: model.statusMessage
                    )

                    if let lastRefreshDate = model.lastRefreshDate {
                        SidebarInfoRow(
                            title: localizer.lastRefreshTitle,
                            value: lastRefreshDate.formatted(date: .omitted, time: .standard)
                        )
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
            }
        }
    }
}
