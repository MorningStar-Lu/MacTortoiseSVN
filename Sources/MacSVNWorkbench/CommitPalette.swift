import SwiftUI

enum CommitPalette {
    static let workspaceGap: CGFloat = 16
    static let panelInset: CGFloat = 4
    static let panelGutter: CGFloat = 16
    static let panelShadowRadius: CGFloat = 8
    static let panelShadowYOffset: CGFloat = 3
    static let panelCornerRadius: CGFloat = 20
    static let chromeCornerRadius: CGFloat = 16
    static let windowBackground = Color.clear
    static let chromeBackground = Color(nsColor: .windowBackgroundColor).opacity(0.45)
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let panelHeaderBackground = Color.clear
    static let listBackground = Color(nsColor: .textBackgroundColor).opacity(0.5)
    static let groupBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
    static let rowBackground = Color.clear
    static let rowSelection = accent.opacity(0.15)
    static let selectedBackground = accent.opacity(0.15)
    static let editorBackground = Color(nsColor: .textBackgroundColor).opacity(0.45)
    static let toolbarFill = Color(nsColor: .quaternaryLabelColor).opacity(0.2)
    static let primaryButton = Color(red: 0.1, green: 0.5, blue: 0.95)
    static let accent = Color(red: 0.1, green: 0.5, blue: 0.95)
    static let folderTint = Color.cyan
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textMuted = Color(nsColor: .tertiaryLabelColor)
    static let border = Color.primary.opacity(0.12)
    static let error = Color(nsColor: .systemRed)
    static let subtleBorder = Color.primary.opacity(0.1)
    static let subtleBorderLight = Color.primary.opacity(0.08)
}
