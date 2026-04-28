import CoreTypes
import FinderSyncBridge
import SwiftUI

struct ChangeOutlineRow: View {
    let node: ChangeTreeNode
    let localizer: MacSVNLocalizer
    let selectedPaths: Set<String>
    let onSetNodeSelection: (ChangeTreeNode, Bool) -> Void
    let onToggleEntry: (String) -> Void

    private var selectionState: SelectionIndicatorState {
        node.selectionState(in: selectedPaths)
    }

    private var isSelectable: Bool {
        if node.isFolder {
            return node.actionableCount > 0
        }

        return node.entry?.isActionable == true
    }

    var body: some View {
        HStack(spacing: 10) {
            SelectionToggleButton(
                state: selectionState,
                isEnabled: isSelectable
            ) {
                if node.isFolder {
                    onSetNodeSelection(node, selectionState != .all)
                } else if let entry = node.entry {
                    onToggleEntry(entry.id)
                }
            }

            Image(systemName: node.isFolder ? "folder" : (node.entry?.isDirectory == true ? "folder" : "doc.text"))
                .foregroundStyle(node.isFolder ? CommitPalette.folderTint : CommitPalette.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.titleText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CommitPalette.textPrimary)
                    .lineLimit(1)

                Text(node.subtitleText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let entry = node.entry, entry.item.propertyModified {
                InlineCapsule(text: localizer.props, tint: .orange)
            }

            if let entry = node.entry {
                StatusBadge(status: entry.status, localizer: localizer)
            } else if node.actionableCount > 0 {
                Text(node.summaryText(localizer: localizer))
                    .font(.system(size: 11))
                    .foregroundStyle(CommitPalette.textMuted)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
