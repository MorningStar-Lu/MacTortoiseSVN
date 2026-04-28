import AppKit
import CoreTypes
import FinderSyncBridge
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

struct HeaderMetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CommitPalette.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct ToolbarActionButton: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? CommitPalette.textPrimary : CommitPalette.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? CommitPalette.textPrimary : CommitPalette.textMuted)
                .frame(width: 34, height: 34)
                .background(CommitPalette.toolbarFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }
}

struct SelectionToggleButton: View {
    let state: SelectionIndicatorState
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.systemImageName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? state.tint : CommitPalette.textMuted)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct CommitMessageEditor: View {
    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding?

    init(
        text: Binding<String>,
        placeholder: String,
        isFocused: FocusState<Bool>.Binding? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .fill(CommitPalette.editorBackground)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CommitPalette.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            editorField
        }
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorField: some View {
        if let isFocused {
            TextEditor(text: $text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(10)
                .focused(isFocused)
        } else {
            TextEditor(text: $text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(10)
        }
    }
}

struct CommitPanel<HeaderTrailing: View, Content: View>: View {
    let title: String
    let headerTrailing: HeaderTrailing
    let content: Content

    init(
        title: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        Section(
            header: VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CommitPalette.textPrimary)

                    Spacer(minLength: 0)
                    headerTrailing
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

                Divider()
                    .overlay(CommitPalette.border)
            }
            .background(
                .ultraThinMaterial,
                in: UnevenRoundedRectangle(topLeadingRadius: CommitPalette.panelCornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: CommitPalette.panelCornerRadius, style: .continuous)
            )
            .background(
                CommitPalette.panelBackground,
                in: UnevenRoundedRectangle(topLeadingRadius: CommitPalette.panelCornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: CommitPalette.panelCornerRadius, style: .continuous)
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: CommitPalette.panelCornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: CommitPalette.panelCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.15), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        ) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    .ultraThinMaterial,
                    in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: CommitPalette.panelCornerRadius, bottomTrailingRadius: CommitPalette.panelCornerRadius, topTrailingRadius: 0, style: .continuous)
                )
                .background(
                    CommitPalette.panelBackground,
                    in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: CommitPalette.panelCornerRadius, bottomTrailingRadius: CommitPalette.panelCornerRadius, topTrailingRadius: 0, style: .continuous)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: CommitPalette.panelCornerRadius, bottomTrailingRadius: CommitPalette.panelCornerRadius, topTrailingRadius: 0, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.clear, Color.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: CommitPalette.panelShadowRadius,
                    x: 0,
                    y: CommitPalette.panelShadowYOffset
                )
                .padding(.bottom, CommitPalette.workspaceGap)
        }
        .padding(.horizontal, CommitPalette.panelInset)
    }
}

extension CommitPanel where HeaderTrailing == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, headerTrailing: { EmptyView() }, content: content)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}

struct SidebarMetricRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(CommitPalette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

struct SidebarInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CommitPalette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InlineCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct DiffTextPreview: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(CommitPalette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
        }
        .background(
            CommitPalette.editorBackground,
            in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}

struct DiffMetadataCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommitPalette.chromeCornerRadius, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorder, lineWidth: 0.5)
        )
    }
}

struct FooterActionButtonModifier: ViewModifier {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(kind == .primary ? Color.white : CommitPalette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundColor, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        kind == .primary
                            ? LinearGradient(colors: [Color.primary.opacity(0.15), Color.clear], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [CommitPalette.subtleBorder, Color.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: backgroundColor.opacity(kind == .primary ? 0.3 : 0.05), radius: kind == .primary ? 8 : 4, x: 0, y: 3)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return CommitPalette.primaryButton
        case .secondary:
            return CommitPalette.toolbarFill
        }
    }
}

struct StatusBadge: View {
    let status: VersionControlStatus
    let localizer: MacSVNLocalizer

    var body: some View {
        Text(localizer.title(for: status))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.color, in: Capsule())
    }
}
