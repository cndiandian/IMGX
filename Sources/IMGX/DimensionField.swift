import AppKit
import SwiftUI

/// Uses the native field editor so delete, selection and Tab retain standard Mac behavior.
struct DimensionField: NSViewRepresentable {
    let title: String
    let focusGroup: DimensionFocusGroup
    var validationMessage: String? = nil
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text, title: title, focusGroup: focusGroup) }
    func makeNSView(context: Context) -> NSTextField {
        let field = AccessibleDimensionTextField(string: text)
        field.placeholderString = title
        field.setAccessibilityLabel("自定义\(title)")
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        if title == "宽度" { focusGroup.width = field } else { focusGroup.height = field }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        field.setAccessibilityHelp(validationMessage ?? "像素，正整数 1 到 16383；留空时可使用原尺寸。")
        field.toolTip = validationMessage
        if field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        let title: String
        let focusGroup: DimensionFocusGroup
        init(text: Binding<String>, title: String, focusGroup: DimensionFocusGroup) {
            self.text = text; self.title = title; self.focusGroup = focusGroup
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if title == "宽度", commandSelector == #selector(NSResponder.insertTab(_:)), let next = focusGroup.height {
                return control.window?.makeFirstResponder(next) ?? false
            }
            if title == "高度", commandSelector == #selector(NSResponder.insertBacktab(_:)), let previous = focusGroup.width {
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
