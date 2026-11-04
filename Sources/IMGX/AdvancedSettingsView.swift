import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var dimensionFocusGroup = DimensionFocusGroup()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("更多设置").font(.headline)
            if model.settings.format == .webp {
                Toggle("WebP 无损压缩", isOn: $model.settings.lossless)
            }
            Text(model.settings.format == .jpeg ? "JPEG 不支持透明，透明区域将铺白。" : "当前格式保留透明通道。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("自定义尺寸").fontWeight(.medium)
            if let size = model.selectedPixelSize {
                Text("原始尺寸：\(Int(size.width)) × \(Int(size.height)) px")
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(alignment: .top, spacing: 16) {
                dimensionInput("宽度", width: true)
                dimensionInput("高度", width: false)
            }
            if let error = model.dimensionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("尺寸错误：\(error)")
            }
            Label("按当前图片等比联动，批量处理保持各图比例。", systemImage: "link")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("正整数 1～16383；均留空时使用原尺寸。")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { isPresented = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 330)
        .disabled(model.isExporting)
    }

    private func dimensionInput(_ title: String, width: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title)（px）").font(.caption).foregroundStyle(.secondary)
            DimensionField(title: title, placeholder: originalDimension(width: width), focusGroup: dimensionFocusGroup, validationMessage: ImageSizing.validationMessage(width ? model.settings.width : model.settings.height),
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
        guard let size = model.selectedPixelSize else { return model.previewLoading ? "读取中" : "不可用" }
        return String(Int(width ? size.width : size.height))
    }

}
