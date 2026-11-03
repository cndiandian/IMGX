import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "inset.left.half.square.dashed")
                .font(.system(size: 56, weight: .light))
                .accessibilityHidden(true)
            Text("IMGX").font(.largeTitle.bold())
            Text("图片压缩与转换").font(.title2)
            Text("本地处理 · 多格式输出 · 保留原文件")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
