import AppKit
import CoreTypes
import FinderSyncBridge
import SVNCore
import SwiftUI

struct HistoryFullView: View {
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
        HStack {
            Text(localizer.historyFullViewTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            Spacer()

            ToolbarIconButton(
                symbol: "arrow.clockwise",
                title: localizer.repositoryBrowserPreviewLoading,
                isEnabled: !model.isRefreshing
            ) {
                model.refreshSnapshot(forceFullRefresh: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var content: some View {
        HSplitView {
            historyList
                .frame(minWidth: 320)

            detailPanel
                .frame(minWidth: 300)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if let error = model.recentHistoryError {
            VStack {
                Spacer()
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(CommitPalette.error)
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if model.recentHistory.isEmpty {
            VStack {
                Spacer()
                Text(localizer.historyFullViewEmpty)
                    .font(.system(size: 13))
                    .foregroundStyle(CommitPalette.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.recentHistory) { entry in
                        Button {
                            model.showHistoryDetail(for: entry.revision)
                        } label: {
                            HistoryEntryRow(
                                entry: entry,
                                localizer: localizer,
                                isSelected: model.selectedHistoryRevision == entry.revision
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                model.showHistoryDetail(for: entry.revision)
                            } label: {
                                Label(localizer.historyContextViewDetail, systemImage: "doc.text.magnifyingglass")
                            }

                            Divider()

                            Button {
                                let text = "r\(entry.revision)"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            } label: {
                                Label(localizer.historyContextCopyRevision, systemImage: "doc.on.doc")
                            }

                            if let author = entry.author, !author.isEmpty {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(author, forType: .string)
                                } label: {
                                    Label(localizer.historyContextCopyAuthor, systemImage: "person.crop.circle")
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localizer.revisionDetailTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if model.isLoadingHistoryDetail {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let detail = model.selectedHistoryEntryDetail {
                ScrollView {
                    RevisionDetailCard(detail: detail, localizer: localizer)
                        .padding(10)
                }
            } else {
                VStack {
                    Spacer()
                    Text(localizer.diffPreviewEmptyTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
