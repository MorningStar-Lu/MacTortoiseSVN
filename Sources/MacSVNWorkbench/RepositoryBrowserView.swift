import CoreTypes
import FinderSyncBridge
import SVNCore
import SwiftUI

struct RepositoryBrowserFullView: View {
    @ObservedObject var model: WorkbenchModel

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(CommitPalette.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.panelCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: CommitPalette.panelShadowRadius, y: CommitPalette.panelShadowYOffset)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(localizer.repoBrowserFullViewTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            Spacer()

            browserToolbar
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var browserToolbar: some View {
        HStack(spacing: 6) {
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
                title: localizer.repositoryBrowserPreviewLoading,
                isEnabled: !model.isLoadingRepositoryBrowser
            ) {
                model.refreshRepositoryBrowser()
            }
        }
    }

    private var content: some View {
        HSplitView {
            browserList
                .frame(minWidth: 300)

            previewPanel
                .frame(minWidth: 280)
        }
    }

    private var browserList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let currentURL = model.repositoryBrowserListing?.baseURL {
                SidebarInfoRow(
                    title: localizer.repositoryBrowserLocationTitle,
                    value: currentURL
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }

            if model.isLoadingRepositoryBrowser {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = model.repositoryBrowserError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(CommitPalette.error)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let listing = model.repositoryBrowserListing {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(listing.entries) { entry in
                            RepositoryBrowserEntryRow(
                                entry: entry,
                                localizer: localizer,
                                isSelected: model.selectedRepositoryBrowserEntry?.id == entry.id,
                                onPrimaryAction: { model.selectRepositoryBrowserEntry(entry) },
                                onOpenDirectory: { model.openRepositoryBrowserEntry(entry) },
                                onCopyURL: { model.copyRepositoryBrowserEntryURL(entry) },
                                onOpenInBrowser: { model.openRepositoryBrowserEntryInBrowser(entry) }
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
                    .padding(8)
                }
            } else {
                VStack {
                    Spacer()
                    Text(localizer.repositoryBrowserEmptyDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localizer.repositoryBrowserPreviewTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if model.isLoadingRepositoryBrowserPreview {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = model.repositoryBrowserPreviewError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(CommitPalette.error)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let previewText = model.repositoryBrowserPreviewText {
                ScrollView {
                    DiffTextPreview(text: previewText)
                        .padding(10)
                }
            } else if let message = model.repositoryBrowserPreviewMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text(localizer.repositoryBrowserPreviewEmptyDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
