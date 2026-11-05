import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = AppModel()
    @State private var dropTargeted = false
    @State private var advanced = false
    @FocusState private var sidebarFocused: Bool
    @State private var resetCanvas = UUID()
    @State private var comparisonMode: ComparisonMode = .slider
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            if !model.items.isEmpty {
                sidebar.frame(width: 236)
                Divider()
            }
            Group {
                if model.items.isEmpty { emptyState }
                else {
                    VStack(spacing: 0) {
                        resultBar
                        Divider()
                        previewCanvas
                        Divider()
                        settingsBar
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            if model.items.isEmpty {
                windowDragArea.frame(height: 54)
            }
        }
        .background(KeyboardBridge(isEditing: advanced, remove: { model.removeSelected() }).frame(width: 0, height: 0))
        .blur(radius: dropTargeted && !model.isExporting ? 2 : 0)
        .overlay(alignment: .bottom) {
            if model.isImporting {
                importProgress.padding(.horizontal, 24).padding(.bottom, model.items.isEmpty ? 24 : 84)
            } else { toast.padding(24) }
        }
        .overlay {
            if dropTargeted && !model.isExporting { dropOverlay }
        }
        .onDeleteCommand { if !advanced { model.removeSelected() } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            guard !model.isExporting else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await ImageFileDrop.fileURL(from: provider) { urls.append(url) }
                }
                await model.add(urls)
            }
            return true
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["IMGX_DEV_SMALL_WINDOW"] == "1" {
                NSApp.windows.first(where: { $0.canBecomeMain })?.setContentSize(NSSize(width: 1000, height: 700))
            }
            if let input = ProcessInfo.processInfo.environment["IMGX_DEV_INPUTS"] {
                await model.add(input.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
            }
            #endif
        }
        .focusedSceneValue(\.imageActions, ImageActions(
            add: { model.chooseImages() },
            canAdd: !model.isExporting,
            reset: { resetCanvas = UUID() },
            hasImages: !model.items.isEmpty,
            export: { model.chooseExportDirectory() },
            canExport: !model.items.isEmpty && !model.isExporting && !model.isImporting,
            remove: { model.removeSelected() },
            clear: { model.clear() },
            canManageFiles: !model.items.isEmpty && !model.isExporting && !advanced,
            showAdvanced: { advanced = true },
            canChangeSettings: !model.items.isEmpty && !model.isExporting,
            comparison: $comparisonMode
        ))
    }

    private var resultBar: some View {
        HStack(spacing: 14) {
            Text("预览").font(.system(size: 13, weight: .semibold))
            if model.isExporting && !model.isChoosingExportDestination {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在导出 · 已处理 \(model.completedCount)/\(model.items.count)")
                        .font(.caption).monospacedDigit()
                    ProgressView(value: Double(model.completedCount), total: Double(max(1, model.items.count)))
                        .progressViewStyle(.linear).tint(.primary)
                        .accessibilityLabel("导出进度")
                        .accessibilityValue("已处理 \(model.completedCount) 张，共 \(model.items.count) 张")
                }
                .frame(width: 180)
            } else if let preview = model.preview {
                HStack(spacing: 8) {
                    if model.selected?.pageNumber != nil {
                        Text("当前页").foregroundStyle(.secondary)
                    } else {
                        Text(byteString(model.selected?.originalBytes ?? 0)).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    Text(byteString(Int64(preview.data.count))).fontWeight(.medium)
                    if model.selected?.pageNumber == nil {
                        let original = Double(model.selected?.originalBytes ?? 0)
                        let difference = original > 0 ? (1 - Double(preview.data.count) / original) * 100 : 0
                        Text(difference >= 0 ? "减少 \(difference, specifier: "%.1f")%" : "增加 \(-difference, specifier: "%.1f")%")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background((difference >= 0 ? Color.green : .orange).opacity(0.16), in: Capsule())
                    }
                }
                .font(.system(size: 12)).monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("预览结果")
                .accessibilityValue("\(model.selected?.pageNumber == nil ? "原图 " + byteString(model.selected?.originalBytes ?? 0) : "PDF 当前页")，输出 \(byteString(Int64(preview.data.count)))；原图 \(preview.original.width) 乘 \(preview.original.height) 像素，输出 \(preview.decoded.width) 乘 \(preview.decoded.height) 像素")
                .help("原图 \(preview.original.width)×\(preview.original.height) px → 输出 \(preview.decoded.width)×\(preview.decoded.height) px")
            } else if model.previewLoading { Text("正在生成预览…").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            ComparisonPicker(selection: $comparisonMode).frame(width: 108, height: 26)
            Button("适应窗口") { resetCanvas = UUID() }.font(.system(size: 12))
        }
        .padding(.horizontal, 20).frame(height: 54)
        .background { windowDragArea }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("编码预览结果")
    }

    private var previewCanvas: some View {
        ZStack {
            ComparisonCanvas(result: model.preview, imageID: model.selectedID, mode: comparisonMode,
                             resetID: resetCanvas, remove: { model.removeSelected() })
            if model.previewLoading { ProgressView().controlSize(.regular).accessibilityLabel("正在生成编码预览").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            else if model.preview == nil { ContentUnavailableView("无法生成预览", systemImage: "exclamationmark.triangle", description: Text("检查图片或调整参数后重试")) }
            if model.preview != nil {
                VStack {
                    HStack {
                        previewLabel("原图")
                        Spacer()
                        previewLabel("转换结果")
                    }
                    Spacer()
                }.padding(16).allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    private var settingsBar: some View {
        HStack(spacing: 16) {
            Picker("格式", selection: $model.settings.format) {
                ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 130)
            HStack(spacing: 8) {
                Text("质量").foregroundStyle(.secondary)
                Slider(value: $model.settings.quality, in: 1...100, step: 1).tint(.primary)
                    .disabled(!model.settings.usesQuality).frame(minWidth: 60, maxWidth: 110)
                    .accessibilityLabel("压缩质量")
                    .accessibilityValue(model.settings.usesQuality ? "\(Int(model.settings.quality))，范围 1 到 100" : "无损，当前模式不使用质量参数")
                    .help(model.settings.usesQuality ? "压缩质量：\(Int(model.settings.quality))（1～100）" : "PNG 和 WebP 无损模式不使用质量参数")
                Text(model.settings.usesQuality ? "\(Int(model.settings.quality))" : "无损")
                    .monospacedDigit().frame(width: 28)
            }
            Picker("尺寸", selection: $model.settings.size) {
                ForEach(SizePreset.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 140)
            Button { advanced.toggle() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 32, height: 32)
            }
                .accessibilityLabel("更多设置").buttonStyle(.borderless)
                .help("更多设置")
                .popover(isPresented: $advanced) { AdvancedSettingsView(model: model, isPresented: $advanced) }
            Spacer(minLength: 0)
            Button(model.isChoosingExportDestination ? "选择保存位置" : model.isExporting ? "已处理 \(model.completedCount)/\(model.items.count)" : "导出 \(model.items.count) 张图片") {
                NSApp.keyWindow?.makeFirstResponder(nil)
                model.chooseExportDirectory()
            }
            .buttonStyle(.bordered).controlSize(.large).focusEffectDisabled()
            .disabled(model.isExporting || model.isImporting)
            .help("选择文件夹后导出全部图片，保留导入的文件夹层级（⌘Return）")
        }
        .font(.system(size: 12)).padding(.horizontal, 20).frame(height: 68)
        .disabled(model.isExporting)
        .onChange(of: model.settings.size) { _, preset in if preset == .custom { advanced = true } }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 84).padding(.bottom, 24)
            Text("图片压缩与转换").font(.system(size: 27, weight: .semibold))
            Text("本地处理 · 多格式输出 · 保留原文件")
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 10)
            Button("选择图片") { model.chooseImages() }
                .buttonStyle(.bordered).controlSize(.large).focusEffectDisabled()
                .padding(.top, 30)
            Text("或将图片、PDF、文件夹拖到窗口中").foregroundStyle(.secondary).padding(.top, 16)
            Text("JPG · JPEG · PNG · WebP · HEIC · PDF")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("IMGX").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(model.items.count) 张").foregroundStyle(.secondary).font(.caption)
            }
            .frame(height: 40)
            .padding(.top, 36)
            .background { windowDragArea }
            Button { model.chooseImages() } label: {
                Label("添加图片", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .controlSize(.large).disabled(model.isExporting)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.items) { item in
                            Button { model.selectedID = item.id; sidebarFocused = true } label: {
                                fileCard(item)
                            }
                            .buttonStyle(.plain).focusEffectDisabled().id(item.id)
                            .accessibilityLabel("\(item.relativePath)，\(byteString(item.originalBytes))，\(item.status.label)")
                            .accessibilityAddTraits(item.id == model.selectedID ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .focusable()
                .focused($sidebarFocused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                .onDeleteCommand { if !advanced { model.removeSelected() } }
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            HStack {
                Button { model.removeSelected() } label: {
                    Image(systemName: "minus.circle").frame(width: 32, height: 32)
                }
                .accessibilityLabel("移除选中图片")
                .help("从列表移除选中图片，保留原文件（Delete）")
                Spacer()
                Button("清空列表") { model.clear() }.font(.caption)
            }
            .buttonStyle(.borderless).disabled(model.isExporting)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("图片列表")
    }

    private var windowDragArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .accessibilityHidden(true)
    }

    private func fileCard(_ item: ImageItem) -> some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = item.thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .frame(width: 44, height: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.middle).help(item.relativePath)
                if !item.relativeDirectory.isEmpty {
                    Text(item.relativeDirectory.joined(separator: "/"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text((item.pageNumber == nil ? "" : "PDF 原文件 · ") + byteString(item.originalBytes)).font(.system(size: 11)).foregroundStyle(.secondary)
                Label(item.status.label, systemImage: item.status.symbol)
                    .labelStyle(.titleAndIcon).font(.caption).lineLimit(1)
                    .foregroundStyle(item.status.isFailure ? Color.primary : Color.secondary)
                    .help(item.status.label)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.id == model.selectedID ? Color.primary.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if contrast == .increased && item.id == model.selectedID {
                RoundedRectangle(cornerRadius: 10).stroke(.primary, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private var dropOverlay: some View {
        ZStack {
            if reduceTransparency { Rectangle().fill(Color(nsColor: .windowBackgroundColor)) }
            else { Rectangle().fill(.regularMaterial) }
            RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(16)
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 40))
                Text("松开以添加图片、PDF 或文件夹").font(.title2.weight(.semibold))
                Text("JPG · JPEG · PNG · WebP · HEIC · PDF").foregroundStyle(.secondary)
                Text("本地处理，保留原文件").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
    }

    private var importProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).accessibilityLabel("正在导入")
            Text("正在读取图片、PDF 与文件夹").font(.callout)
            Button("取消") { model.cancelImport() }.buttonStyle(.borderless).focusEffectDisabled()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast, !(advanced && model.dimensionError != nil && message.kind == .previewError) {
            HStack(spacing: 12) {
                Image(systemName: message.kind == .previewError ? "exclamationmark.triangle" : "info.circle")
                Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                Button { model.dismissToast() } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .accessibilityLabel("关闭提示").help("关闭提示")
                .buttonStyle(.borderless)
            }
            .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            .frame(maxWidth: 680)
        }
    }
}
