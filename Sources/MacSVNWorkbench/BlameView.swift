import FinderSyncBridge
import SwiftUI

struct BlameView: View {
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
        .frame(minWidth: 700, minHeight: 500)
    }

    private var header: some View {
        HStack {
            Text(localizer.blameViewTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            if let path = model.blameTargetPath {
                Text("— \((path as NSString).lastPathComponent)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
            }

            Spacer()

            Button("Done") {
                model.isBlamePresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var content: some View {
        Group {
            if model.isLoadingBlame {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(localizer.blameViewTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(CommitPalette.textMuted)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.blameError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(CommitPalette.error)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.blameLines.isEmpty {
                VStack {
                    Spacer()
                    Text(localizer.blameEmptyState)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                blameTable
            }
        }
    }

    private var blameTable: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0) {
                blameHeaderRow
                ForEach(model.blameLines) { line in
                    blameRow(line)
                }
            }
            .padding(4)
        }
    }

    private var blameHeaderRow: some View {
        HStack(spacing: 0) {
            Text(localizer.blameColumnLine)
                .frame(width: 60, alignment: .trailing)
            Text(localizer.blameColumnRevision)
                .frame(width: 70, alignment: .trailing)
            Text(localizer.blameColumnAuthor)
                .frame(width: 120, alignment: .leading)
                .padding(.leading, 8)
            Text(localizer.blameColumnContent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(CommitPalette.textMuted)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(CommitPalette.groupBackground)
    }

    private func blameRow(_ line: BlameLine) -> some View {
        HStack(spacing: 0) {
            Text("\(line.lineNumber)")
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(CommitPalette.textMuted)

            Text("r\(line.revision)")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(CommitPalette.accent)

            Text(line.author ?? "—")
                .frame(width: 120, alignment: .leading)
                .padding(.leading, 8)
                .foregroundStyle(CommitPalette.textSecondary)

            Text(line.content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .foregroundStyle(CommitPalette.textPrimary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            line.lineNumber % 2 == 0
                ? CommitPalette.groupBackground.opacity(0.4)
                : Color.clear
        )
    }
}
