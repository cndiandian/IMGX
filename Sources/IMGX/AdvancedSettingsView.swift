import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var dimensionFocusGroup = DimensionFocusGroup()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.moreSettings)).font(.headline)
            if model.settings.format == .webp {
                Toggle(L10n.text(.webpLossless), isOn: $model.settings.lossless)
            }
            Text(model.settings.format == .jpeg ? L10n.text(.jpegTransparency) : L10n.text(.keepTransparency))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(L10n.text(.customSize)).fontWeight(.medium)
            if let size = model.selectedPixelSize {
                Text(L10n.text(.sourceDimensions, String(Int(size.width)), String(Int(size.height))))
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(alignment: .top, spacing: 16) {
                dimensionInput(L10n.text(.width), width: true)
                dimensionInput(L10n.text(.height), width: false)
            }
            if let error = model.dimensionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(L10n.text(.dimensionError, error))
            }
            Label(L10n.text(.linkedDimensions), systemImage: "link")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text(.dimensionHint))
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L10n.text(.done)) { isPresented = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 330)
        .disabled(model.isExporting)
    }

    private func dimensionInput(_ title: String, width: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(.dimensionLabel, title)).font(.caption).foregroundStyle(.secondary)
            DimensionField(title: title, isWidth: width, placeholder: originalDimension(width: width), focusGroup: dimensionFocusGroup, validationMessage: ImageSizing.validationMessage(width ? model.settings.width : model.settings.height),
                           text: Binding(get: { width ? model.settings.width : model.settings.height },
                                         set: { model.editDimension($0, width: width) }))
                .frame(height: 24)
                .overlay {
                    if ImageSizing.validationMessage(width ? model.settings.width : model.settings.height) != nil {
                        RoundedRectangle(cornerRadius: 5).stroke(.red, lineWidth: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func originalDimension(width: Bool) -> String {
        guard let size = model.selectedPixelSize else { return model.previewLoading ? L10n.text(.reading) : L10n.text(.unavailable) }
        return String(Int(width ? size.width : size.height))
    }

}
