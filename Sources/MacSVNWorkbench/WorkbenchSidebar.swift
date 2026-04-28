import AppKit
import FinderSyncBridge
import SwiftUI

struct WorkbenchSidebar: View {
    @ObservedObject var model: WorkbenchModel

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.visibilityPrefs.showSidebarBookmarks {
                bookmarksSection
            }

            if model.visibilityPrefs.showSidebarNavigation {
                navigationSection
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxHeight: .infinity)
        .background(CommitPalette.chromeBackground.opacity(0.6))
    }

    // MARK: - Bookmarks

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localizer.sidebarWorkspacesTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    model.addBookmarkFromPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommitPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .help(localizer.addWorkingCopyTitle)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            if model.bookmarks.isEmpty {
                Button {
                    model.addBookmarkFromPicker()
                } label: {
                    Label(localizer.addWorkingCopyTitle, systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CommitPalette.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(model.bookmarks) { bookmark in
                            BookmarkRow(
                                bookmark: bookmark,
                                isActive: bookmark.path == model.rootPath,
                                localizer: localizer,
                                onSelect: { model.switchToBookmark(bookmark) },
                                onRename: { model.renameBookmark(id: bookmark.id, newName: $0) },
                                onReveal: { model.revealInFinder(bookmark.path) },
                                onCopyPath: { model.copyPathToClipboard(bookmark.path) },
                                onRemove: { model.removeBookmark(id: bookmark.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 4)
        }
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizer.sidebarNavigationTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            NavigationRow(
                item: .changes,
                icon: "list.bullet.rectangle",
                title: localizer.sidebarChangesTitle,
                isActive: model.activeNavigation == .changes,
                onSelect: { model.activeNavigation = .changes }
            )

            NavigationRow(
                item: .repoBrowser,
                icon: "folder.badge.gearshape",
                title: localizer.sidebarRepositoryTitle,
                isActive: model.activeNavigation == .repoBrowser,
                onSelect: { model.activeNavigation = .repoBrowser }
            )

            NavigationRow(
                item: .history,
                icon: "clock.arrow.circlepath",
                title: localizer.sidebarHistoryTitle,
                isActive: model.activeNavigation == .history,
                onSelect: { model.activeNavigation = .history }
            )
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal, 12)

            HStack(spacing: 8) {
                if !model.rootPath.isEmpty {
                    Button {
                        model.addCurrentPathAsBookmark()
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(CommitPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.addWorkingCopyTitle)
                }

                Spacer()

                SettingsLink {
                    Label(localizer.displaySettingsTitle, systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CommitPalette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Bookmark Row

private struct BookmarkRow: View {
    let bookmark: WorkspaceBookmark
    let isActive: Bool
    let localizer: MacSVNLocalizer
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? CommitPalette.accent : CommitPalette.folderTint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.label)
                        .font(.system(size: 12, weight: isActive ? .bold : .medium))
                        .foregroundStyle(isActive ? CommitPalette.textPrimary : CommitPalette.textSecondary)
                        .lineLimit(1)

                    Text(bookmark.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CommitPalette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? CommitPalette.rowSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label(localizer.sidebarWorkspacesTitle, systemImage: "arrow.right.circle")
            }

            Button {
                let prompt = NSAlert()
                prompt.messageText = localizer.renameBookmarkTitle
                prompt.informativeText = bookmark.label
                let input = NSTextField(string: bookmark.displayName ?? bookmark.label)
                input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
                prompt.accessoryView = input
                prompt.addButton(withTitle: "OK")
                prompt.addButton(withTitle: "Cancel")
                if prompt.runModal() == .alertFirstButtonReturn {
                    onRename(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } label: {
                Label(localizer.renameBookmarkTitle, systemImage: "pencil")
            }

            Divider()

            Button {
                onReveal()
            } label: {
                Label(localizer.contextRevealInFinder, systemImage: "folder")
            }

            Button {
                onCopyPath()
            } label: {
                Label(localizer.contextCopyPath, systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label(localizer.removeBookmarkTitle, systemImage: "trash")
            }
        }
    }
}

// MARK: - Navigation Row

private struct NavigationRow: View {
    let item: WorkbenchModel.NavigationItem
    let icon: String
    let title: String
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? CommitPalette.accent : CommitPalette.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? CommitPalette.textPrimary : CommitPalette.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? CommitPalette.rowSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
