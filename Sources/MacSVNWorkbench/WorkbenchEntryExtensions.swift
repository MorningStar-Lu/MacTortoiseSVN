import CoreTypes
import SwiftUI

struct WorkbenchEntryExtensions {
    private init() {}
}

extension WorkbenchModel.Entry {
    var displayName: String {
        if relativePath == "." {
            return (item.path as NSString).lastPathComponent
        }
        return (relativePath as NSString).lastPathComponent
    }

    var groupDirectoryPath: String {
        if isDirectory {
            return relativePath
        }
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty ? "." : directory
    }
}

extension VersionControlStatus {
    var color: Color {
        switch self {
        case .normal:
            return Color.gray
        case .modified:
            return Color.orange
        case .added:
            return Color.green
        case .deleted:
            return Color.red
        case .conflicted:
            return Color.pink
        case .ignored:
            return CommitPalette.textMuted
        case .external:
            return Color.indigo
        case .locked:
            return Color.purple
        case .missing:
            return Color.brown
        case .replaced:
            return Color.mint
        case .incomplete:
            return Color.yellow
        case .obstructed:
            return Color(red: 0.36, green: 0.42, blue: 0.46)
        case .unversioned:
            return Color.blue
        }
    }
}
