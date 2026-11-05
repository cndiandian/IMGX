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
            Text(L10n.text(.preview)).font(.system(size: 13, weight: .semibold))
            if model.isExporting && !model.isChoosingExportDestination {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(.exportingProgress, String(model.completedCount), String(model.items.count)))
                        .font(.caption).monospacedDigit()
                    ProgressView(value: Double(model.completedCount), total: Double(max(1, model.items.count)))
                        .progressViewStyle(.linear).tint(.primary)
                        .accessibilityLabel(L10n.text(.exportProgress))
                        .accessibilityValue(L10n.text(.processedCount, String(model.completedCount), String(model.items.count)))
                }
                .frame(width: 180)
            } else if let preview = model.preview {
                HStack(spacing: 8) {
                    if model.selected?.pageNumber != nil {
                        Text(L10n.text(.currentPage)).foregroundStyle(.secondary)
                    } else {
                        Text(byteString(model.selected?.originalBytes ?? 0)).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    Text(byteString(Int64(preview.data.count))).fontWeight(.medium)
                    if model.selected?.pageNumber == nil {
                        let original = Double(model.selected?.originalBytes ?? 0)
                        let difference = original > 0 ? (1 - Double(preview.data.count) / original) * 100 : 0
                        Text(L10n.text(difference >= 0 ? .reduction : .increase, String(format: "%.1f", locale: Locale(identifier: L10n.language.rawValue), abs(difference))))
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background((difference >= 0 ? Color.green : .orange).opacity(0.16), in: Capsule())
                    }
                }
                .font(.system(size: 12)).monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(L10n.text(.previewResult))
                .accessibilityValue(L10n.text(.previewAccessibility, model.selected?.pageNumber == nil ? L10n.text(.original) + " " + byteString(model.selected?.originalBytes ?? 0) : L10n.text(.pdfCurrentPage), byteString(Int64(preview.data.count)), String(preview.original.width), String(preview.original.height), String(preview.decoded.width), String(preview.decoded.height)))
                .help(L10n.text(.previewSizeHelp, String(preview.original.width), String(preview.original.height), String(preview.decoded.width), String(preview.decoded.height)))
            } else if model.previewLoading { Text(L10n.text(.previewLoading)).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            ComparisonPicker(selection: $comparisonMode).frame(width: 128, height: 26)
            Button(L10n.text(.fit)) { resetCanvas = UUID() }.font(.system(size: 12))
        }
        .padding(.horizontal, 20).frame(height: 54)
        .background { windowDragArea }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(.encodedPreview))
    }

    private var previewCanvas: some View {
        ZStack {
            ComparisonCanvas(result: model.preview, imageID: model.selectedID, mode: comparisonMode,
                             resetID: resetCanvas, remove: { model.removeSelected() })
            if model.previewLoading { ProgressView().controlSize(.regular).accessibilityLabel(L10n.text(.encodingPreview)).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            else if model.preview == nil { ContentUnavailableView(L10n.text(.previewUnavailable), systemImage: "exclamationmark.triangle", description: Text(L10n.text(.previewRetry))) }
            if model.preview != nil {
                VStack {
                    HStack {
                        previewLabel(L10n.text(.original))
                        Spacer()
                        previewLabel(L10n.text(.result))
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
            Picker(L10n.text(.format), selection: $model.settings.format) {
                ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 130)
            HStack(spacing: 8) {
                Text(L10n.text(.quality)).foregroundStyle(.secondary)
                Slider(value: $model.settings.quality, in: 1...100, step: 1).tint(.primary)
                    .disabled(!model.settings.usesQuality).frame(minWidth: 60, maxWidth: 110)
                    .accessibilityLabel(L10n.text(.compressionQuality))
                    .accessibilityValue(model.settings.usesQuality ? L10n.text(.qualityRange, String(Int(model.settings.quality))) : L10n.text(.losslessRange))
                    .help(model.settings.usesQuality ? L10n.text(.qualityHelp, String(Int(model.settings.quality))) : L10n.text(.losslessHelp))
                Text(model.settings.usesQuality ? "\(Int(model.settings.quality))" : L10n.text(.lossless))
                    .monospacedDigit().fixedSize(horizontal: true, vertical: false).frame(minWidth: 28)
            }
            Picker(L10n.text(.size), selection: $model.settings.size) {
                ForEach(SizePreset.allCases) { Text($0.title).tag($0) }
            }.frame(width: 140)
            Button { advanced.toggle() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 32, height: 32)
            }
                .accessibilityLabel(L10n.text(.moreSettings)).buttonStyle(.borderless)
                .help(L10n.text(.moreSettings))
                .popover(isPresented: $advanced) { AdvancedSettingsView(model: model, isPresented: $advanced) }
            Spacer(minLength: 0)
            Button(model.isChoosingExportDestination ? L10n.text(.chooseDestination) : model.isExporting ? L10n.text(.processedShort, String(model.completedCount), String(model.items.count)) : L10n.text(.exportCount, String(model.items.count))) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                model.chooseExportDirectory()
            }
            .buttonStyle(.bordered).controlSize(.large).focusEffectDisabled()
            .disabled(model.isExporting || model.isImporting)
            .help(L10n.text(.exportHelp))
        }
        .font(.system(size: 12)).padding(.horizontal, 20).frame(height: 68)
        .disabled(model.isExporting)
        .onChange(of: model.settings.size) { _, preset in if preset == .custom { advanced = true } }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            BrandIcon(size: 84).padding(.bottom, 24)
            Text(L10n.text(.emptyTitle)).font(.system(size: 27, weight: .semibold))
            Text(L10n.text(.emptySubtitle))
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 10)
            Button(L10n.text(.chooseImages)) { model.chooseImages() }
                .buttonStyle(.bordered).controlSize(.large).focusEffectDisabled()
                .padding(.top, 30)
            Text(L10n.text(.dropHint)).foregroundStyle(.secondary).padding(.top, 16)
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
                Text(L10n.text(.imageCount, String(model.items.count))).foregroundStyle(.secondary).font(.caption)
            }
            .frame(height: 40)
            .padding(.top, 36)
            .background { windowDragArea }
            Button { model.chooseImages() } label: {
                Label(L10n.text(.addImages), systemImage: "plus").frame(maxWidth: .infinity)
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
                .accessibilityLabel(L10n.text(.removeImage))
                .help(L10n.text(.removeHelp))
                Spacer()
                Button(L10n.text(.clearList)) { model.clear() }.font(.caption)
            }
            .buttonStyle(.borderless).disabled(model.isExporting)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(.imageList))
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
                Text((item.pageNumber == nil ? "" : L10n.text(.pdfFilePrefix)) + byteString(item.originalBytes)).font(.system(size: 11)).foregroundStyle(.secondary)
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
                Text(L10n.text(.releaseToAdd)).font(.title2.weight(.semibold))
                Text("JPG · JPEG · PNG · WebP · HEIC · PDF").foregroundStyle(.secondary)
                Text(L10n.text(.localOriginals)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
    }

    private var importProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).accessibilityLabel(L10n.text(.importing))
            Text(L10n.text(.readingInputs)).font(.callout)
            Button(L10n.text(.cancel)) { model.cancelImport() }.buttonStyle(.borderless).focusEffectDisabled()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func openExportDirectory(_ directory: URL) {
        if !NSWorkspace.shared.open(directory) {
            model.notify(L10n.text(.cannotOpenDirectory))
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast, !(advanced && model.dimensionError != nil && message.kind == .previewError) {
            HStack(spacing: 12) {
                Image(systemName: message.kind == .previewError ? "exclamationmark.triangle" : "info.circle")
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text).textSelection(.enabled)
                    if let directory = message.exportDirectory {
                        HStack(spacing: 12) {
                            Text(L10n.text(.savedTo)).foregroundStyle(.secondary).fixedSize()
                            Button { openExportDirectory(directory) } label: {
                                Text(directory.path).underline()
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            .buttonStyle(.plain).focusEffectDisabled()
                            .accessibilityLabel(L10n.text(.openDirectoryPath, directory.path))
                            .help(directory.path)
                            Button(L10n.text(.openDirectory)) { openExportDirectory(directory) }
                                .buttonStyle(.bordered).focusEffectDisabled().fixedSize()
                        }
                    }
                }
                .font(.system(size: 12))
                Button { model.dismissToast() } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .accessibilityLabel(L10n.text(.closeNotice)).help(L10n.text(.closeNotice))
                .buttonStyle(.borderless)
            }
            .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
            .frame(maxWidth: 680)
        }
    }
}
