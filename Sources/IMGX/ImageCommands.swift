import SwiftUI

struct ImageActions {
    var add: () -> Void
    var canAdd: Bool
    var reset: () -> Void
    var hasImages: Bool
    var export: () -> Void
    var canExport: Bool
    var copyResult: () -> Void
    var canCopyResult: Bool
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
            Button(L10n.text(.addImages)) { actions?.add() }
                .keyboardShortcut("o").disabled(actions?.canAdd != true)
            Button(L10n.text(.exportAll)) { actions?.export() }
                .keyboardShortcut(.return, modifiers: .command).disabled(actions?.canExport != true)
        }
        CommandGroup(after: .pasteboard) {
            Button(L10n.text(.copyCurrentResult)) { actions?.copyResult() }
                .disabled(actions?.canCopyResult != true)
            Divider()
            Button(L10n.text(.removeImage)) { actions?.remove() }.disabled(actions?.canManageFiles != true)
            Button(L10n.text(.clearImages)) { actions?.clear() }.disabled(actions?.canManageFiles != true)
        }
        CommandGroup(after: .toolbar) {
            Picker(L10n.text(.comparison), selection: Binding(get: { actions?.comparison.wrappedValue ?? .slider },
                                                set: { actions?.comparison.wrappedValue = $0 })) {
                ForEach(ComparisonMode.allCases) { Text($0.title).tag($0) }
            }.disabled(actions?.hasImages != true)
            Button(L10n.text(.fit)) { actions?.reset() }
                .keyboardShortcut("0").disabled(actions?.hasImages != true)
            Divider()
            Button(L10n.text(.moreImageSettings)) { actions?.showAdvanced() }.disabled(actions?.canChangeSettings != true)
        }
    }
}
