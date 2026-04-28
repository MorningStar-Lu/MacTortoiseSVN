import CoreTypes
import FinderSyncBridge
import SVNCore
import SwiftUI

struct RepositoryBrowserEntryRow: View {
    let entry: SVNRepositoryBrowserEntry
    let localizer: MacSVNLocalizer
    let isSelected: Bool
    let onPrimaryAction: () -> Void
    let onOpenDirectory: () -> Void
    let onCopyURL: () -> Void
    let onOpenInBrowser: () -> Void

    private var subtitle: String {
        var parts: [String] = []

        if let revision = entry.revision {
            parts.append("r\(revision)")
        }

        if let author = entry.author, !author.isEmpty {
            parts.append(author)
        }

        if let date = entry.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }

        if !entry.isDirectory, let size = entry.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }

        return parts.isEmpty ? (entry.isDirectory ? localizer.folder : localizer.fileTitle) : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(entry.isDirectory ? CommitPalette.folderTint : CommitPalette.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CommitPalette.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onCopyURL) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(CommitPalette.toolbarFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(localizer.repositoryBrowserCopyURL)

            Button(action: onOpenInBrowser) {
                Image(systemName: "safari")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(CommitPalette.toolbarFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(localizer.repositoryBrowserOpenInBrowser)

            if entry.isDirectory {
                Button {
                    onOpenDirectory()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CommitPalette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(CommitPalette.toolbarFill, in: Circle())
                }
                .buttonStyle(.plain)
                .help(localizer.repositoryBrowserOpenDirectory)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPrimaryAction)
        .padding(10)
        .background(
            isSelected ? CommitPalette.rowSelection : CommitPalette.groupBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? CommitPalette.accent.opacity(0.35) : CommitPalette.subtleBorderLight,
                    lineWidth: 0.5
                )
        )
    }
}
