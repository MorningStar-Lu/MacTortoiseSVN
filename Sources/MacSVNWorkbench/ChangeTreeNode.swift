import CoreTypes
import FinderSyncBridge
import Foundation
import SwiftUI

struct ChangeTreeNode: Identifiable {
    let id: String
    let name: String
    let relativePath: String
    let absolutePath: String
    let entry: WorkbenchModel.Entry?
    let children: [ChangeTreeNode]?
    let actionableCount: Int
    let dirtyCount: Int
    let unversionedCount: Int
    let itemCount: Int

    var isFolder: Bool {
        hasChildren || entry?.isDirectory == true
    }

    var hasChildren: Bool {
        !(children?.isEmpty ?? true)
    }

    var titleText: String {
        if relativePath == "." {
            return entry?.displayName ?? name
        }

        return name
    }

    var subtitleText: String {
        if let entry {
            return entry.relativePath == "." ? absolutePath : entry.relativePath
        }

        return relativePath
    }

    func selectionState(in selectedPaths: Set<String>) -> SelectionIndicatorState {
        let selectedCount = selectedActionableCount(in: selectedPaths)
        if selectedCount == 0 {
            return .none
        }
        if selectedCount >= actionableCount {
            return .all
        }
        return .partial
    }

    private func selectedActionableCount(in selectedPaths: Set<String>) -> Int {
        guard actionableCount > 0 else {
            return 0
        }

        if !isFolder {
            return selectedPaths.contains(absolutePath) ? 1 : 0
        }

        let prefix = absolutePath + "/"
        return selectedPaths.reduce(into: 0) { result, path in
            if path == absolutePath || path.hasPrefix(prefix) {
                result += 1
            }
        }
    }

    func summaryText(localizer: MacSVNLocalizer) -> String {
        localizer.treeSummaryText(
            changed: dirtyCount,
            unversioned: unversionedCount,
            total: itemCount
        )
    }

    static func build(
        from entries: [WorkbenchModel.Entry],
        rootPath: String
    ) -> [ChangeTreeNode] {
        let root = MutableChangeTreeNode(name: "", relativePath: "", absolutePath: rootPath)

        for entry in entries.sorted(by: { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }) {
            if entry.relativePath == "." {
                root.children["."] = MutableChangeTreeNode(
                    name: entry.displayName,
                    relativePath: ".",
                    absolutePath: entry.id,
                    entry: entry
                )
                continue
            }

            let normalizedPath = entry.relativePath == "." ? entry.displayName : entry.relativePath
            let components = normalizedPath
                .split(separator: "/")
                .map(String.init)

            guard !components.isEmpty else {
                continue
            }

            var currentNode = root
            var accumulatedComponents: [String] = []
            var accumulatedAbsolutePath = rootPath

            for (index, component) in components.enumerated() {
                accumulatedComponents.append(component)
                let currentPath = accumulatedComponents.joined(separator: "/")
                accumulatedAbsolutePath += "/" + component
                let isLast = index == components.count - 1

                if let existingNode = currentNode.children[component] {
                    currentNode = existingNode
                    if isLast {
                        currentNode.entry = entry
                    }
                    continue
                }

                let newNode = MutableChangeTreeNode(
                    name: component,
                    relativePath: currentPath,
                    absolutePath: accumulatedAbsolutePath,
                    entry: isLast ? entry : nil
                )
                currentNode.children[component] = newNode
                currentNode = newNode
            }
        }

        return root.children.values
            .map { $0.freeze() }
            .sorted(by: ChangeTreeNode.treeSort)
    }

    static func treeSort(lhs: ChangeTreeNode, rhs: ChangeTreeNode) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder && !rhs.isFolder
        }
        if lhs.dirtyCount != rhs.dirtyCount {
            return lhs.dirtyCount > rhs.dirtyCount
        }
        if lhs.unversionedCount != rhs.unversionedCount {
            return lhs.unversionedCount > rhs.unversionedCount
        }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }
}

final class MutableChangeTreeNode {
    let name: String
    let relativePath: String
    let absolutePath: String
    var entry: WorkbenchModel.Entry?
    var children: [String: MutableChangeTreeNode]

    init(
        name: String,
        relativePath: String,
        absolutePath: String,
        entry: WorkbenchModel.Entry? = nil,
        children: [String: MutableChangeTreeNode] = [:]
    ) {
        self.name = name
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.entry = entry
        self.children = children
    }

    func freeze() -> ChangeTreeNode {
        let frozenChildren = children.values
            .map { $0.freeze() }
            .sorted(by: ChangeTreeNode.treeSort)

        let actionableCount = (entry?.isActionable == true ? 1 : 0) + frozenChildren.reduce(0) { $0 + $1.actionableCount }
        let dirtyCount = (entry?.canCommit == true ? 1 : 0) + frozenChildren.reduce(0) { $0 + $1.dirtyCount }
        let unversionedCount = (entry?.canAdd == true ? 1 : 0) + frozenChildren.reduce(0) { $0 + $1.unversionedCount }
        let itemCount = (entry == nil ? 0 : 1) + frozenChildren.reduce(0) { $0 + $1.itemCount }

        return ChangeTreeNode(
            id: absolutePath,
            name: name,
            relativePath: relativePath,
            absolutePath: absolutePath,
            entry: entry,
            children: frozenChildren.isEmpty ? nil : frozenChildren,
            actionableCount: actionableCount,
            dirtyCount: dirtyCount,
            unversionedCount: unversionedCount,
            itemCount: itemCount
        )
    }
}

enum SelectionIndicatorState {
    case none
    case partial
    case all

    var systemImageName: String {
        switch self {
        case .none:
            return "square"
        case .partial:
            return "minus.square.fill"
        case .all:
            return "checkmark.square.fill"
        }
    }

    var tint: Color {
        switch self {
        case .none:
            return CommitPalette.textMuted
        case .partial:
            return Color.orange
        case .all:
            return CommitPalette.accent
        }
    }
}
