import CoreTypes
import FinderSyncBridge
import SVNCore
import SwiftUI

struct HistoryEntryRow: View {
    let entry: SVNHistoryEntry
    let localizer: MacSVNLocalizer
    let isSelected: Bool

    private var message: String {
        let trimmedMessage = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? localizer.emptyLogMessage : trimmedMessage
    }

    private var subtitle: String {
        let author = entry.author ?? localizer.unknownAuthorTitle
        if let date = entry.date {
            return "\(author) · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return author
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("r\(entry.revision)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(CommitPalette.accent)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .lineLimit(1)
            }

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CommitPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            (isSelected ? CommitPalette.rowSelection : CommitPalette.groupBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? CommitPalette.accent.opacity(0.35) : CommitPalette.subtleBorder,
                    lineWidth: 0.5
                )
        )
    }
}

struct RevisionDetailCard: View {
    let detail: SVNHistoryEntryDetail
    let localizer: MacSVNLocalizer

    private var message: String {
        let trimmedMessage = detail.entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedMessage.isEmpty ? localizer.emptyLogMessage : trimmedMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                InlineCapsule(text: "r\(detail.entry.revision)", tint: CommitPalette.accent)
                InlineCapsule(
                    text: detail.entry.author ?? localizer.unknownAuthorTitle,
                    tint: Color.orange
                )
            }

            if let date = detail.entry.date {
                SidebarInfoRow(
                    title: localizer.revisionDateTitle,
                    value: date.formatted(date: .abbreviated, time: .shortened)
                )
            }

            SidebarInfoRow(
                title: localizer.logMessageTitle,
                value: message
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.changedPathsTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)

                if detail.changedPaths.isEmpty {
                    Text(localizer.noChangedPathsDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CommitPalette.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(detail.changedPaths.prefix(12)) { changedPath in
                            HistoryChangedPathRow(changedPath: changedPath)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryChangedPathRow: View {
    let changedPath: SVNHistoryChangedPath

    private var actionTint: Color {
        switch changedPath.action.uppercased() {
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(changedPath.action.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(actionTint)
                .frame(width: 18, alignment: .leading)

            Text(changedPath.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(CommitPalette.textSecondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}
