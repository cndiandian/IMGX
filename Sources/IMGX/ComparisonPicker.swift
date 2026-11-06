import SwiftUI
import AppKit

struct ComparisonPicker: NSViewRepresentable {
    @Binding var selection: ComparisonMode
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ComparisonMode.allCases.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.selectedSegmentBezelColor = .darkGray
        control.setAccessibilityLabel(L10n.text(.comparison))
        control.toolTip = L10n.text(.toggleComparisonHelp)
        for index in ComparisonMode.allCases.indices { control.setWidth(58, forSegment: index) }
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = selection == .slider ? 0 : 1
    }
    @MainActor final class Coordinator: NSObject {
        var selection: Binding<ComparisonMode>
        init(selection: Binding<ComparisonMode>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) {
            selection.wrappedValue = sender.selectedSegment == 0 ? .slider : .split
        }
    }
}
