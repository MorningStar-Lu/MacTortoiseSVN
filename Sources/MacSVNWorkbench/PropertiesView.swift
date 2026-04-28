import FinderSyncBridge
import SwiftUI

struct PropertiesView: View {
    @ObservedObject var model: WorkbenchModel
    @State private var newPropertyName = ""
    @State private var newPropertyValue = ""
    @State private var isAddingProperty = false
    @State private var editingProperty: SVNPropertyEntry?
    @State private var editValue = ""

    private var localizer: MacSVNLocalizer {
        model.localizer
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private var header: some View {
        HStack {
            Text(localizer.propertiesViewTitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CommitPalette.textPrimary)

            if let path = model.propertiesTargetPath {
                Text("— \((path as NSString).lastPathComponent)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
            }

            Spacer()

            Button {
                isAddingProperty.toggle()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(localizer.propertiesAddTitle)

            Button("Done") {
                model.isPropertiesPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if isAddingProperty {
                addPropertyRow
                Divider()
            }

            if model.isLoadingProperties {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.propertiesError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(CommitPalette.error)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.propertyList.isEmpty {
                VStack {
                    Spacer()
                    Text(localizer.propertiesEmptyState)
                        .font(.system(size: 13))
                        .foregroundStyle(CommitPalette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                propertyTable
            }
        }
    }

    private var addPropertyRow: some View {
        HStack(spacing: 8) {
            TextField(localizer.propertiesNameColumn, text: $newPropertyName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            TextField(localizer.propertiesValueColumn, text: $newPropertyValue)
                .textFieldStyle(.roundedBorder)

            Button(localizer.propertiesAddTitle) {
                guard let path = model.propertiesTargetPath,
                      !newPropertyName.isEmpty else { return }
                model.setProperty(path: path, name: newPropertyName, value: newPropertyValue)
                newPropertyName = ""
                newPropertyValue = ""
                isAddingProperty = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newPropertyName.isEmpty)

            Button(localizer.cancelTitle) {
                isAddingProperty = false
                newPropertyName = ""
                newPropertyValue = ""
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var propertyTable: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.propertyList) { property in
                    propertyRow(property)
                }
            }
            .padding(8)
        }
    }

    private func propertyRow(_ property: SVNPropertyEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(property.name)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(CommitPalette.accent)

                Spacer()

                if editingProperty?.id == property.id {
                    Button(localizer.confirmDeleteButtonTitle) {
                        guard let path = model.propertiesTargetPath else { return }
                        model.setProperty(path: path, name: property.name, value: editValue)
                        editingProperty = nil
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)

                    Button(localizer.cancelTitle) {
                        editingProperty = nil
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        editingProperty = property
                        editValue = property.value
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        guard let path = model.propertiesTargetPath else { return }
                        model.deleteProperty(path: path, name: property.name)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            if editingProperty?.id == property.id {
                TextEditor(text: $editValue)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(CommitPalette.editorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(property.value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CommitPalette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(CommitPalette.groupBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CommitPalette.subtleBorderLight, lineWidth: 0.5)
        )
    }
}
