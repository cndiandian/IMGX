import AppKit
import SwiftUI

/// Uses the native field editor so delete, selection and Tab retain standard Mac behavior.
struct DimensionField: NSViewRepresentable {
    let title: String
    let isWidth: Bool
    let placeholder: String
    let focusGroup: DimensionFocusGroup
    var validationMessage: String? = nil
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isWidth: isWidth, focusGroup: focusGroup) }
    func makeNSView(context: Context) -> NSTextField {
        let field = AccessibleDimensionTextField(string: text)
        field.placeholderString = placeholder
        field.setAccessibilityLabel(L10n.text(.customDimension, title))
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        if isWidth { focusGroup.width = field } else { focusGroup.height = field }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = placeholder
        field.setAccessibilityHelp(validationMessage ?? L10n.text(.dimensionHelp))
        field.toolTip = validationMessage
        if field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        let isWidth: Bool
        let focusGroup: DimensionFocusGroup
        init(text: Binding<String>, isWidth: Bool, focusGroup: DimensionFocusGroup) {
            self.text = text; self.isWidth = isWidth; self.focusGroup = focusGroup
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if isWidth, commandSelector == #selector(NSResponder.insertTab(_:)), let next = focusGroup.height {
                return control.window?.makeFirstResponder(next) ?? false
            }
            if !isWidth, commandSelector == #selector(NSResponder.insertBacktab(_:)), let previous = focusGroup.width {
                return control.window?.makeFirstResponder(previous) ?? false
            }
            return false
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

final class AccessibleDimensionTextField: NSTextField {
    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self) ?? false
    }
}

@MainActor final class DimensionFocusGroup {
    weak var width: NSTextField?
    weak var height: NSTextField?
}
