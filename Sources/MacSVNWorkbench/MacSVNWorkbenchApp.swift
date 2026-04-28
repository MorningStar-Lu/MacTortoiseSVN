import SwiftUI

@main
struct MacTortoiseSVNApp: App {
    @StateObject private var model = WorkbenchModel()

    var body: some Scene {
        WindowGroup {
            WorkbenchRootView(model: model)
                .frame(
                    minWidth: WorkbenchLayout.minimumWindowSize.width,
                    minHeight: WorkbenchLayout.minimumWindowSize.height
                )
        }
        .windowResizability(.automatic)

        Settings {
            WorkbenchSettingsView(model: model)
        }
    }
}

enum WorkbenchWindowPreset: String, Codable, CaseIterable, Identifiable {
    case compact
    case spacious

    var id: String {
        rawValue
    }

    var defaultContentSize: CGSize {
        switch self {
        case .compact:
            return CGSize(width: 920, height: 640)
        case .spacious:
            return CGSize(width: 1360, height: 860)
        }
    }
}

struct WorkbenchPresentationPreferences: Codable, Equatable {
    var defaultWindowPreset: WorkbenchWindowPreset = .compact
    var hideDiffPreviewInCompactWindow = true
    var showSidebar = true

    var showChangeList = true
    var showCommitMessage = true
    var showDiffPreview = true
    var showInspector = true

    var showRepoOverview = true
    var showRepoBrowser = true
    var showFilePreview = true
    var showRecentHistory = true
    var showRevisionDetail = true
    var showQuickOptions = true
    var showStatusSection = true

    var showActionToolbar = true
    var showSidebarBookmarks = true
    var showSidebarNavigation = true
}

struct WorkbenchPresentationPreferencesStore {
    private static let defaultsKey = "MacTortoiseSVNWorkbenchPresentationPreferences"

    func load() -> WorkbenchPresentationPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let preferences = try? JSONDecoder().decode(WorkbenchPresentationPreferences.self, from: data)
        else {
            return WorkbenchPresentationPreferences()
        }

        return preferences
    }

    func save(_ preferences: WorkbenchPresentationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
