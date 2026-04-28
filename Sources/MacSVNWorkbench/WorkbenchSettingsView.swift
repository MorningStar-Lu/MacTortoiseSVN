import FinderSyncBridge
import SwiftUI

struct WorkbenchSettingsView: View {
    @ObservedObject var model: WorkbenchModel

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(localizer.displaySettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(localizer.defaultWindowPresetTitle, selection: $model.defaultWindowPreset) {
                            Text(localizer.compactWindowPresetTitle).tag(WorkbenchWindowPreset.compact)
                            Text(localizer.spaciousWindowPresetTitle).tag(WorkbenchWindowPreset.spacious)
                        }
                        .pickerStyle(.radioGroup)

                        Toggle(localizer.hideDiffPreviewInCompactTitle, isOn: $model.hideDiffPreviewInCompactWindow)

                        Text(localizer.finderLaunchPreferenceHint)
                            .font(.system(size: 12))
                            .foregroundStyle(CommitPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(localizer.sidebarSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(localizer.showSidebarTitle, isOn: $model.isSidebarVisible)
                        Toggle(localizer.showSidebarBookmarksTitle, isOn: $model.visibilityPrefs.showSidebarBookmarks)
                            .disabled(!model.isSidebarVisible)
                        Toggle(localizer.showSidebarNavigationTitle, isOn: $model.visibilityPrefs.showSidebarNavigation)
                            .disabled(!model.isSidebarVisible)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(localizer.workspaceSettingsTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(localizer.showActionToolbarTitle, isOn: $model.visibilityPrefs.showActionToolbar)
                        Toggle(localizer.showChangeListTitle, isOn: $model.visibilityPrefs.showChangeList)
                        Toggle(localizer.showCommitMessageTitle, isOn: $model.visibilityPrefs.showCommitMessage)
                        Toggle(localizer.showDiffPreviewTitle, isOn: $model.visibilityPrefs.showDiffPreview)
                        Toggle(localizer.showInspectorTitle, isOn: $model.visibilityPrefs.showInspector)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(width: 460)
    }
}
