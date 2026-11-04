import AppKit
import SwiftUI

struct BrandIcon: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: NSImage(systemSymbolName: "inset.left.half.square.dashed.micro", accessibilityDescription: nil)
              ?? NSImage(systemSymbolName: "inset.left.half.square", accessibilityDescription: nil)
              ?? NSImage(systemSymbolName: "square.lefthalf.filled", accessibilityDescription: nil)!)
            .resizable().scaledToFit()
            .frame(width: size * 0.54, height: size * 0.54)
            .foregroundStyle(Color(white: 0.18))
            .frame(width: size, height: size)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: size * 0.23))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.1), radius: size * 0.08, y: size * 0.04)
            .accessibilityHidden(true)
    }
}
