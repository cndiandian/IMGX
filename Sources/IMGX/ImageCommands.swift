import SwiftUI

struct ImageActions {
    var add: () -> Void
    var canAdd: Bool
    var reset: () -> Void
    var hasImages: Bool
    var export: () -> Void
    var canExport: Bool
    var remove: () -> Void
    var clear: () -> Void
    var canManageFiles: Bool
    var showAdvanced: () -> Void
    var canChangeSettings: Bool
    var comparison: Binding<ComparisonMode>
}

struct ImageActionsKey: FocusedValueKey { typealias Value = ImageActions }
extension FocusedValues {
    var imageActions: ImageActions? {
        get { self[ImageActionsKey.self] }
        set { self[ImageActionsKey.self] = newValue }
    }
}

struct ImageCommands: Commands {
    @FocusedValue(\.imageActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("添加图片") { actions?.add() }
                .keyboardShortcut("o").disabled(actions?.canAdd != true)
            Button("导出全部图片") { actions?.export() }
                .keyboardShortcut(.return, modifiers: .command).disabled(actions?.canExport != true)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("移除选中图片") { actions?.remove() }.disabled(actions?.canManageFiles != true)
            Button("清空图片列表") { actions?.clear() }.disabled(actions?.canManageFiles != true)
        }
        CommandGroup(after: .toolbar) {
            Picker("对比方式", selection: Binding(get: { actions?.comparison.wrappedValue ?? .slider },
                                                set: { actions?.comparison.wrappedValue = $0 })) {
                ForEach(ComparisonMode.allCases) { Text($0.rawValue).tag($0) }
            }.disabled(actions?.hasImages != true)
            Button("适应窗口") { actions?.reset() }
                .keyboardShortcut("0").disabled(actions?.hasImages != true)
            Divider()
            Button("更多图像设置") { actions?.showAdvanced() }.disabled(actions?.canChangeSettings != true)
        }
    }
}
