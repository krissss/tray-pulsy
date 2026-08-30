import AppKit
import Defaults
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - 皮肤 Tab
// ═══════════════════════════════════════════════════════════════

struct SkinDetail: View {
    @Environment(AppState.self) private var appState
    @Default(.skin) private var skin
    @Default(.externalSkinPath) private var externalSkinPath
    @Default(.reverseAnimationSpeed) private var reverseAnimationSpeed
    @Default(.skinAnimationSpeed) private var skinAnimationSpeed
    @Default(.pulsyColorTheme) private var pulsyColorTheme
    @Default(.pulsyWaveformStyle) private var pulsyWaveformStyle
    @Default(.pulsyLineWidth) private var pulsyLineWidth
    @Default(.pulsyGlowIntensity) private var pulsyGlowIntensity
    @Default(.pulsyAmplitudeSensitivity) private var pulsyAmplitudeSensitivity
    @Default(.onlineSkinManifestURL) private var onlineSkinManifestURL
    @State private var didRequestOnlineSkins = false
    @State private var manifestURLText = ""
    @State private var previewLoad = 20.0

    var body: some View {
        SettingsFormPage {
            previewLoadSection()

            Section {
                Picker(selection: $skinAnimationSpeed) {
                    ForEach(SkinAnimationSpeed.allCases, id: \.rawValue) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                } label: {
                    SettingsRowLabel(
                        title: L10n.skinAnimationSpeedLabel,
                        systemImage: "speedometer",
                        color: .pink
                    )
                }

                Toggle(isOn: $reverseAnimationSpeed) {
                    SettingsRowLabel(
                        title: L10n.skinReverseAnimationToggle,
                        systemImage: "arrow.up.arrow.down.circle",
                        color: .pink
                    )
                }
            } header: {
                Text(L10n.skinMotionHeader)
            } footer: {
                Text(L10n.skinMotionFooter)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 10)], spacing: 10) {
                    ForEach(appState.skinManager.allSkins) { s in
                        Button {
                            skin = s.id
                        } label: {
                            SkinThumbnail(
                                skin: s,
                                isSelected: skin == s.id,
                                previewLoad: previewLoad,
                                pulsyConfigToken: pulsyConfigToken
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.skinLibraryHeader)
            }

            onlineSkinsSection()

            pulsyConfigSection()

            Section {
                HStack(alignment: .center, spacing: 12) {
                    externalSkinPathLabel
                        .frame(width: 92, alignment: .leading)
                    externalSkinPathControls
                        .layoutPriority(1)
                }

                if !externalSkinPath.isEmpty {
                    let expanded = (externalSkinPath as NSString).expandingTildeInPath
                    if !FileManager.default.fileExists(atPath: expanded) {
                        Label(L10n.skinPathNotFound, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text(L10n.skinExtHeader)
            } footer: {
                Text(L10n.skinExtInfo)
            }
        }
        .task {
            guard !didRequestOnlineSkins else { return }
            didRequestOnlineSkins = true
            syncManifestURLTextFromDefaults()
            refreshOnlineSkins()
        }
    }

    /// Show Pulsy config section when pulsy skin is selected.
    private var showPulsyConfig: Bool { skin == "pulsy" }

    private var pulsyConfigToken: String {
        "\(pulsyColorTheme.rawValue)-\(pulsyWaveformStyle.rawValue)-\(pulsyLineWidth)-\(pulsyGlowIntensity)-\(pulsyAmplitudeSensitivity)"
    }

    private var externalSkinPathLabel: some View {
        SettingsRowLabel(
            title: L10n.skinPathLabel,
            systemImage: "folder",
            color: .pink
        )
    }

    private var externalSkinPathControls: some View {
        HStack(spacing: 8) {
            TextField("", text: $externalSkinPath, prompt: Text(L10n.skinPathPrompt))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)
                .layoutPriority(1)
                .accessibilityLabel(L10n.skinPathLabel)
            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    externalSkinPath = url.path
                }
            } label: {
                Label(L10n.skinBrowse, systemImage: "folder.badge.plus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Online Skin Section
// ═══════════════════════════════════════════════════════════════

private extension SkinDetail {
    var defaultManifestURLString: String {
        OnlineSkinCatalog.defaultManifestURL.absoluteString
    }

    var manifestURL: URL? {
        let trimmed = manifestURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmed.isEmpty ? defaultManifestURLString : trimmed
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            return nil
        }
        return url
    }

    func syncManifestURLTextFromDefaults() {
        let saved = onlineSkinManifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        manifestURLText = saved.isEmpty ? defaultManifestURLString : saved
    }

    func persistManifestURLOverride(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onlineSkinManifestURL = ""
            return
        }

        guard trimmed != defaultManifestURLString else {
            onlineSkinManifestURL = ""
            return
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            onlineSkinManifestURL = trimmed
            return
        }

        onlineSkinManifestURL = url.absoluteString == defaultManifestURLString ? "" : url.absoluteString
    }

    func refreshOnlineSkins() {
        guard let manifestURL else { return }
        persistManifestURLOverride(manifestURL.absoluteString)
        appState.onlineSkinCatalog.updateManifestURL(manifestURL)
        Task { await appState.onlineSkinCatalog.refresh() }
    }

    @ViewBuilder
    func previewLoadSection() -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SettingsRowLabel(
                        title: L10n.skinPreviewLoadLabel,
                        systemImage: "gauge.with.dots.needle.67percent",
                        color: .pink
                    )

                    Spacer(minLength: 12)

                    SettingsValueBadge(text: "\(Int(previewLoad.rounded()))%", color: .pink)
                }

                HStack(spacing: 8) {
                    Text("0%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, alignment: .leading)

                    SingleValueSlider(value: $previewLoad, range: 0...100, step: 1, color: .pink)
                        .layoutPriority(1)
                        .accessibilityLabel(L10n.skinPreviewLoadLabel)
                        .accessibilityValue("\(Int(previewLoad.rounded()))%")

                    Text("100%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.secondary.opacity(0.075), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    func onlineSkinsSection() -> some View {
        let catalog = appState.onlineSkinCatalog

        Section {
            onlineCatalogToolbar(catalog: catalog)

            if catalog.isRefreshing && catalog.skins.isEmpty {
                onlineCatalogStatus(L10n.skinOnlineLoading, systemImage: "hourglass", color: .secondary)
            } else if manifestURL == nil {
                onlineCatalogStatus(L10n.skinOnlineInvalidManifestURL, systemImage: "exclamationmark.triangle.fill", color: .orange)
            } else if catalog.skins.isEmpty {
                onlineCatalogStatus(L10n.skinOnlineEmpty, systemImage: "tray", color: .secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 172, maximum: 240), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(catalog.skins) { item in
                        OnlineSkinTile(item: item, previewLoad: previewLoad)
                    }
                }
                .padding(.vertical, 4)
            }

            if let errorMessage = catalog.errorMessage, !errorMessage.isEmpty {
                onlineCatalogStatus(errorMessage, systemImage: "exclamationmark.triangle.fill", color: .orange)
            }
        } header: {
            Text(L10n.skinOnlineHeader)
        } footer: {
            Text(L10n.skinOnlineFooter)
        }
    }

    func onlineCatalogToolbar(catalog: OnlineSkinCatalog) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.secondary.opacity(0.075))
                }
                .accessibilityHidden(true)

            ManifestURLTextField(
                text: $manifestURLText,
                placeholder: defaultManifestURLString,
                onTextChange: persistManifestURLOverride,
                onSubmit: refreshOnlineSkins
            )
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.secondary.opacity(0.045))
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(manifestURL == nil ? Color.orange.opacity(0.28) : .secondary.opacity(0.08), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .layoutPriority(1)
                .accessibilityLabel(L10n.skinOnlineManifestURL)

            Button {
                refreshOnlineSkins()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(.rect(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.pink.opacity(0.08))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.pink.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .disabled(catalog.isRefreshing || manifestURL == nil)
            .help(L10n.skinOnlineRefresh)
            .accessibilityLabel(L10n.skinOnlineRefresh)
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.04))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.075), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    func onlineCatalogStatus(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct ManifestURLTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.refusesFirstResponder = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.cell?.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.textColor = .labelColor
        textField.placeholderString = placeholder
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ManifestURLTextField

        init(_ parent: ManifestURLTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
            parent.onTextChange(textField.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.onSubmit()
            return true
        }
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(forBounds: super.drawingRect(forBounds: rect))
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func centeredRect(forBounds rect: NSRect) -> NSRect {
        guard let font else { return rect }
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let yOffset = max(0, floor((rect.height - textHeight) / 2))
        return NSRect(x: rect.minX, y: rect.minY + yOffset, width: rect.width, height: textHeight)
    }
}

private struct OnlineSkinTile: View {
    @Environment(AppState.self) private var appState
    let item: OnlineSkinCatalogItem
    let previewLoad: Double

    private var catalog: OnlineSkinCatalog { appState.onlineSkinCatalog }
    private var isInstalled: Bool { catalog.isInstalled(item.id) }
    private var isInstalling: Bool { catalog.isInstalling(item.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                OnlineSkinPreview(item: item, previewLoad: previewLoad)

                if isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                        .background {
                            Circle()
                                .fill(.background)
                                .frame(width: 10, height: 10)
                        }
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.id)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if isInstalled {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .accessibilityLabel(L10n.skinOnlineInstalled)
                    }
                }

                Text(L10n.skinOnlineAuthor(item.author))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .layoutPriority(1)

            VStack(spacing: 6) {
                Button {
                    if isInstalled {
                        appState.deleteOnlineSkin(item)
                    } else {
                        Task { await appState.installOnlineSkin(item) }
                    }
                } label: {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background {
                            Circle()
                                .fill(actionColor.opacity(0.09))
                        }
                        .overlay {
                            Circle()
                                .stroke(actionColor.opacity(0.14), lineWidth: 1)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(actionColor)
                .disabled(isInstalling)
                .help(actionLabel)
                .accessibilityLabel(actionLabel)

                if let url = catalog.sourceURL(for: item) {
                    Link(destination: url) {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 26, height: 22)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(.secondary.opacity(0.07))
                            }
                            .contentShape(.capsule)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .help(L10n.skinOnlineSource)
                    .accessibilityLabel(L10n.skinOnlineSource)
                }
            }
        }
        .padding(9)
        .frame(minHeight: 72)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isInstalled ? Color.accentColor.opacity(0.06) : .secondary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isInstalled ? Color.accentColor.opacity(0.18) : .secondary.opacity(0.075), lineWidth: 1)
        }
    }

    private var actionLabel: String {
        if isInstalling { return L10n.skinOnlineLoading }
        return isInstalled ? L10n.skinOnlineDelete : L10n.skinOnlineInstall
    }

    private var actionSystemImage: String {
        if isInstalling { return "hourglass" }
        return isInstalled ? "trash" : "arrow.down.circle"
    }

    private var actionColor: Color {
        if isInstalling { return .secondary }
        return isInstalled ? .red : .accentColor
    }
}

private struct OnlineSkinPreview: View {
    @Environment(AppState.self) private var appState
    @Default(.reverseAnimationSpeed) private var reverseAnimationSpeed
    @Default(.skinAnimationSpeed) private var skinAnimationSpeed
    let item: OnlineSkinCatalogItem
    let previewLoad: Double

    @State private var previewImage: NSImage?
    @State private var frameCache: [NSImage] = []
    @State private var animator: TrayAnimator?
    @State private var didFail = false

    private var catalog: OnlineSkinCatalog { appState.onlineSkinCatalog }
    private var animationID: String { "\(item.id)-\(item.frames.joined(separator: "|"))" }
    private let maxCachedFrames = 24

    var body: some View {
        ZStack {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 40, height: 40)
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityLabel(L10n.skinOnlinePreview)
        .task(id: animationID) {
            await loadPreviewFrames()
        }
        .onChange(of: previewLoad) {
            animator?.updateValue(previewLoad)
        }
        .onChange(of: reverseAnimationSpeed) {
            animator?.setReverseAnimationSpeed(reverseAnimationSpeed)
        }
        .onChange(of: skinAnimationSpeed) {
            animator?.setSkinAnimationSpeed(skinAnimationSpeed)
        }
        .onDisappear {
            stopAnimation()
            frameCache.removeAll(keepingCapacity: false)
        }
    }

    private func loadPreviewFrames() async {
        stopAnimation()
        previewImage = nil
        frameCache.removeAll(keepingCapacity: false)
        didFail = false

        guard !item.frames.isEmpty else {
            didFail = true
            return
        }

        var frames: [NSImage] = []
        let frameCount = min(item.frames.count, maxCachedFrames)
        for index in 0..<frameCount {
            do {
                let data = try await catalog.previewFrameData(for: item, frameIndex: index)
                if Task.isCancelled { return }
                guard let image = NSImage(data: data) else {
                    didFail = true
                    return
                }
                // Preserve the image's TRUE pixel dimensions so aspect ratio is
                // correct when drawn. Previously we forced 18×18, which discarded
                // the real ratio and stretched non-square sprites (Mario 15×21,
                // Mega Man 25×24) into a square → distortion. Mirrors the fix in
                // SkinManager.loadFrames so online + local skins render identically.
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    image.size = NSSize(width: cg.width, height: cg.height)
                }
                frames.append(image)
                if previewImage == nil {
                    previewImage = image
                }
            } catch {
                if Task.isCancelled { return }
                didFail = true
                return
            }
        }

        guard !frames.isEmpty else {
            didFail = true
            return
        }
        frameCache = frames
        startAnimation(with: frames)
    }

    private func startAnimation(with frames: [NSImage]) {
        stopAnimation()
        previewImage = frames.first
        didFail = false
        guard frames.count > 1 else { return }

        let animator = TrayAnimator(initialFrames: frames)
        animator.setFPSLimit(.fps20)
        animator.setReverseAnimationSpeed(reverseAnimationSpeed)
        animator.setSkinAnimationSpeed(skinAnimationSpeed)
        animator.onFrameUpdate = { [weak animator] image in
            _ = animator
            MainActor.assumeIsolated {
                previewImage = image
            }
        }
        animator.updateValue(previewLoad)
        animator.start()
        self.animator = animator
    }

    private func stopAnimation() {
        animator?.stop()
        animator = nil
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Pulsy Configuration Section
// ═══════════════════════════════════════════════════════════════

private extension SkinDetail {
    @ViewBuilder
    func pulsyConfigSection() -> some View {
        if showPulsyConfig {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        PulsyThemeStrip(selectedTheme: pulsyColorTheme)
                        VStack(alignment: .leading, spacing: 6) {
                            Picker(L10n.pulsySettingsColorTheme, selection: $pulsyColorTheme) {
                                ForEach(PulsyColorTheme.allCases, id: \.self) { theme in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(nsColor: theme.iconColor))
                                            .frame(width: 10, height: 10)
                                        Text(theme.displayName)
                                    }
                                    .tag(theme)
                                }
                            }

                            Picker(L10n.pulsySettingsWaveform, selection: $pulsyWaveformStyle) {
                                ForEach(PulsyWaveformStyle.allCases, id: \.self) { style in
                                    Label(style.displayName, systemImage: style.systemImage)
                                        .tag(style)
                                }
                            }
                        }
                    }

                    Divider()

                    PulsySliderRow(
                        title: L10n.pulsySettingsLineWidth,
                        systemImage: "lineweight",
                        value: String(format: "%.1f", pulsyLineWidth),
                        sliderValue: $pulsyLineWidth,
                        range: 0.5...2.0,
                        step: 0.1
                    )

                    PulsySliderRow(
                        title: L10n.pulsySettingsGlowIntensity,
                        systemImage: "sparkles",
                        value: String(format: "%.1f", pulsyGlowIntensity),
                        sliderValue: $pulsyGlowIntensity,
                        range: 0...1.0,
                        step: 0.1
                    )

                    PulsySliderRow(
                        title: L10n.pulsySettingsAmplitudeSensitivity,
                        systemImage: "waveform.path.ecg",
                        value: String(format: "%.2f", pulsyAmplitudeSensitivity),
                        sliderValue: $pulsyAmplitudeSensitivity,
                        range: 0.2...1.0,
                        step: 0.05
                    )
                }
            } header: {
                Text(L10n.pulsySettingsHeader)
            }
        }
    }
}

private struct PulsyThemeStrip: View {
    let selectedTheme: PulsyColorTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(selectedTheme.gradientStops.enumerated()), id: \.offset) { _, color in
                Rectangle()
                    .fill(Color(nsColor: color))
            }
        }
        .frame(width: 56, height: 38)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color(nsColor: selectedTheme.iconColor).opacity(0.25), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

private struct PulsySliderRow: View {
    let title: String
    let systemImage: String
    let value: String
    @Binding var sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        SettingsInsetPanel(spacing: 9) {
            HStack(spacing: 10) {
                SettingsRowLabel(
                    title: title,
                    systemImage: systemImage,
                    color: .pink
                )
                Spacer()
                SettingsValueBadge(text: value, color: .pink)
            }
            SingleValueSlider(value: $sliderValue, range: range, step: step, color: .pink)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - 指标 Tab
// ═══════════════════════════════════════════════════════════════

struct MetricsDetail: View {
    @Default(.thresholds) private var thresholds
    @Default(.floatingWindowEnabled) private var floatingWindowEnabled
    @Default(.floatingWindowAlwaysOnTop) private var floatingWindowAlwaysOnTop
    @Default(.floatingWindowShowsSkin) private var floatingWindowShowsSkin
    @Default(.floatingWindowMetricsLayout) private var floatingWindowMetricsLayout
    @Default(.floatingWindowBackgroundColor) private var floatingWindowBackgroundColor
    @Default(.floatingWindowBackgroundOpacity) private var floatingWindowBackgroundOpacity
    @Default(.floatingWindowTextColor) private var floatingWindowTextColor

    private var floatingWindowBackgroundColorBinding: Binding<Color> {
        Binding(
            get: { floatingWindowBackgroundColor.color },
            set: { floatingWindowBackgroundColor = FloatingWindowColor(color: $0) }
        )
    }

    private var floatingWindowTextColorBinding: Binding<Color> {
        Binding(
            get: { floatingWindowTextColor.color },
            set: { floatingWindowTextColor = FloatingWindowColor(color: $0) }
        )
    }

    private var floatingWindowBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { min(max(floatingWindowBackgroundOpacity, 0.15), 1) },
            set: { floatingWindowBackgroundOpacity = min(max($0, 0.15), 1) }
        )
    }

    var body: some View {
        SettingsFormPage {
            Section {
                Toggle(isOn: $floatingWindowEnabled) {
                    SettingsRowLabel(
                        title: L10n.floatingWindowToggle,
                        systemImage: "rectangle.on.rectangle.circle",
                        color: .teal
                    )
                }

                if floatingWindowEnabled {
                    Toggle(isOn: $floatingWindowAlwaysOnTop) {
                        SettingsRowLabel(
                            title: L10n.floatingWindowAlwaysOnTop,
                            systemImage: "pin.circle.fill",
                            color: .teal
                        )
                    }

                    Toggle(isOn: $floatingWindowShowsSkin) {
                        SettingsRowLabel(
                            title: L10n.floatingWindowShowSkin,
                            systemImage: "sparkles.rectangle.stack",
                            color: .teal
                        )
                    }

                    Picker(selection: $floatingWindowMetricsLayout) {
                        ForEach(FloatingWindowMetricsLayout.allCases) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    } label: {
                        SettingsRowLabel(
                            title: L10n.floatingWindowLayout,
                            systemImage: "rectangle.split.2x1",
                            color: .teal
                        )
                    }
                    .pickerStyle(.segmented)

                    ColorPicker(selection: floatingWindowBackgroundColorBinding, supportsOpacity: false) {
                        SettingsRowLabel(
                            title: L10n.floatingWindowBackgroundColor,
                            systemImage: "paintpalette.fill",
                            color: .teal
                        )
                    }

                    ColorPicker(selection: floatingWindowTextColorBinding, supportsOpacity: false) {
                        SettingsRowLabel(
                            title: L10n.floatingWindowTextColor,
                            systemImage: "textformat",
                            color: .teal
                        )
                    }

                    SettingsInsetPanel(spacing: 9) {
                        HStack(spacing: 10) {
                            SettingsRowLabel(
                                title: L10n.floatingWindowBackgroundOpacity,
                                systemImage: "circle.lefthalf.filled",
                                color: .teal
                            )
                            Spacer()
                            SettingsValueBadge(
                                text: "\(Int((floatingWindowBackgroundOpacityBinding.wrappedValue * 100).rounded()))%",
                                color: .teal
                            )
                        }
                        SingleValueSlider(
                            value: floatingWindowBackgroundOpacityBinding,
                            range: 0.15...1,
                            step: 0.05,
                            color: .teal
                        )
                    }
                }
            } header: {
                Text(L10n.floatingWindowHeader)
            } footer: {
                Text(L10n.floatingWindowFooter)
            }

            Section {
                ForEach(MetricDisplayItem.allCases) { item in
                    MetricRowView(item: item)
                }
            } header: {
                Text(L10n.metricsHeader)
            } footer: {
                Text(L10n.metricsFooter)
            }
        }
    }
}

// MARK: - Metric Row (toggle + thresholds combined)

private struct MetricRowView: View {
    let item: MetricDisplayItem
    @Default(.speedSource) private var speedSource
    @Default(.metricMonitorItems) private var metricMonitorItems
    @Default(.metricDisplayItems) private var metricDisplayItems
    @Default(.floatingWindowEnabled) private var floatingWindowEnabled
    @Default(.floatingWindowMetricItems) private var floatingWindowMetricItems
    @Default(.thresholds) private var thresholds
    @Default(.spikeDeltas) private var spikeDeltas
    @State private var isAdvancedExpanded = false

    private var isMonitored: Bool {
        metricMonitorItems.contains(item)
    }

    private var selectedFloatingMetricItems: Set<MetricDisplayItem> {
        floatingWindowEnabled && floatingWindowMetricItems.isEmpty
            ? Defaults.Keys.defaultFloatingWindowMetricItems
            : floatingWindowMetricItems
    }

    private var mode: MetricManagementMode {
        if metricDisplayItems.contains(item) {
            return .menuBar
        }
        if metricMonitorItems.contains(item) {
            return .monitorOnly
        }
        return .off
    }

    private var modeBinding: Binding<MetricManagementMode> {
        Binding(
            get: { mode },
            set: { newMode in
                switch newMode {
                case .off:
                    metricMonitorItems.remove(item)
                    metricDisplayItems.remove(item)
                    var items = selectedFloatingMetricItems
                    items.remove(item)
                    floatingWindowMetricItems = items
                    if items.isEmpty {
                        floatingWindowEnabled = false
                    }
                    if item.requiredMetric == speedSource.requiredMetric,
                       let nextSource = SpeedSource.firstAvailable(in: metricMonitorItems) {
                        speedSource = nextSource
                    }
                    withAnimation(ContainedExpansionMotion.layoutAnimation(expanding: false)) {
                        isAdvancedExpanded = false
                    }
                case .monitorOnly:
                    metricMonitorItems.insert(item)
                    metricDisplayItems.remove(item)
                case .menuBar:
                    metricMonitorItems.insert(item)
                    metricDisplayItems.insert(item)
                }
            }
        )
    }

    private var floatingMetricBinding: Binding<Bool> {
        Binding(
            get: {
                floatingWindowEnabled && selectedFloatingMetricItems.contains(item)
            },
            set: { isEnabled in
                var items = selectedFloatingMetricItems
                if isEnabled {
                    items.insert(item)
                    floatingWindowMetricItems = items
                    metricMonitorItems.insert(item)
                    floatingWindowEnabled = true
                } else {
                    items.remove(item)
                    floatingWindowMetricItems = items
                    if items.isEmpty {
                        floatingWindowEnabled = false
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricHeaderRow

            if isMonitored {
                VStack(spacing: 0) {
                    SettingsDisclosureButton(
                        title: L10n.metricsAdvancedSettings,
                        systemImage: "slider.horizontal.3",
                        isExpanded: isAdvancedExpanded,
                        color: Color(nsColor: item.accentColor)
                    ) {
                        isAdvancedExpanded.toggle()
                    }

                    ContainedExpansion(isExpanded: isAdvancedExpanded, topSpacing: 2) {
                        SettingsInsetPanel(spacing: 12) {
                            DualThresholdSlider(
                                title: L10n.metricsColorThresholdLabel,
                                description: L10n.metricsColorThresholdDescription,
                                warning: Binding(
                                    get: { thresholds[keyPath: item.thresholdKeyPath].warning },
                                    set: { thresholds[keyPath: item.thresholdKeyPath].warning = $0 }
                                ),
                                critical: Binding(
                                    get: { thresholds[keyPath: item.thresholdKeyPath].critical },
                                    set: { thresholds[keyPath: item.thresholdKeyPath].critical = $0 }
                                ),
                                range: sliderRange,
                                step: sliderStep,
                                formatLabel: valueLabel
                            )
                            if item.supportsSpikeDiagnostics, let deltaKeyPath = item.spikeDeltaKeyPath {
                                SingleThresholdSlider(
                                    label: L10n.metricsSpikeDeltaLabel,
                                    description: L10n.metricsSpikeDeltaDescription,
                                    value: Binding(
                                        get: { spikeDeltas[keyPath: deltaKeyPath] },
                                        set: { spikeDeltas[keyPath: deltaKeyPath] = $0 }
                                    ),
                                    range: spikeDeltaRange,
                                    step: spikeDeltaStep,
                                    formatLabel: valueLabel
                                )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    // MARK: - Slider helpers

    private var metricHeaderRow: some View {
        HStack(spacing: 12) {
            metricLabel
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                floatingMetricToggle
                modePicker
            }
        }
    }

    private var metricLabel: some View {
        SettingsRowLabel(
            title: item.displayName,
            systemImage: item.chartIcon,
            color: Color(nsColor: item.accentColor)
        )
    }

    private var modePicker: some View {
        Picker(L10n.metricsModePickerLabel, selection: modeBinding) {
            ForEach(MetricManagementMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 220)
    }

    private var floatingMetricToggle: some View {
        Toggle(isOn: floatingMetricBinding) {
            Text(L10n.metricsFloatingWindow)
                .lineLimit(1)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("\(item.displayName) \(L10n.metricsFloatingWindow)")
    }

    private var isPercent: Bool {
        switch item {
        case .cpu, .gpu, .memory, .disk: return true
        case .networkDown, .networkUp:   return false
        }
    }

    private var sliderRange: ClosedRange<Double> {
        isPercent ? 0...100 : 0...20_000_000
    }

    private var sliderStep: Double {
        isPercent ? 5 : 1_000_000
    }

    private var spikeDeltaRange: ClosedRange<Double> {
        isPercent ? 0...50 : 0...10_000_000
    }

    private var spikeDeltaStep: Double {
        isPercent ? 1 : 250_000
    }

    private func valueLabel(for bytesOrPercent: Double) -> String {
        if isPercent {
            return "\(Int(bytesOrPercent))%"
        }
        let mb = bytesOrPercent / 1_000_000
        if mb >= 1 {
            return String(format: "%.0fM", mb)
        }
        return "\(Int(bytesOrPercent / 1_000))K"
    }

}

private enum MetricManagementMode: String, CaseIterable, Identifiable {
    case off
    case monitorOnly
    case menuBar

    var id: Self { self }

    var label: String {
        switch self {
        case .off:         return L10n.metricsModeOff
        case .monitorOnly: return L10n.metricsModeMonitorOnly
        case .menuBar:     return L10n.metricsModeMenuBar
        }
    }
}

// MARK: - Threshold Sliders

private struct DualThresholdSlider: View {
    let title: String
    let description: String
    @Binding var warning: Double
    @Binding var critical: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    SettingsValueBadge(text: L10n.metricsWarningThreshold(formatLabel(warning)), color: .orange)
                    SettingsValueBadge(text: L10n.metricsCriticalThreshold(formatLabel(critical)), color: .red)
                }
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let warningX = xPosition(for: warning, width: width)
                let criticalX = xPosition(for: critical, width: width)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 7)

                    Capsule(style: .continuous)
                        .fill(.yellow.opacity(0.28))
                        .frame(width: max(criticalX - warningX, 0), height: 7)
                        .offset(x: warningX)

                    Capsule(style: .continuous)
                        .fill(.red.opacity(0.28))
                        .frame(width: max(width - criticalX, 0), height: 7)
                        .offset(x: criticalX)

                    ThresholdHandle(color: .yellow)
                        .position(x: warningX, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    warning = min(value(for: gesture.location.x, width: width), critical - step)
                                }
                        )

                    ThresholdHandle(color: .red)
                        .position(x: criticalX, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    critical = max(value(for: gesture.location.x, width: width), warning + step)
                                }
                        )
                }
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .frame(height: 22)
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func value(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct SingleThresholdSlider: View {
    let label: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                SettingsValueBadge(text: "+\(formatLabel(value))", color: .accentColor)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let x = xPosition(for: value, width: width)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 7)

                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.28))
                        .frame(width: x, height: 7)

                    ThresholdHandle(color: .accentColor)
                        .position(x: x, y: 11)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    value = steppedValue(for: gesture.location.x, width: width)
                                }
                        )
                }
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .frame(height: 22)
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func steppedValue(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct SingleValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let x = xPosition(for: value, width: width)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 7)

                Capsule(style: .continuous)
                    .fill(color.opacity(0.28))
                    .frame(width: x, height: 7)

                ThresholdHandle(color: color)
                    .position(x: x, y: 11)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                value = steppedValue(for: gesture.location.x, width: width)
                            }
                    )
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .frame(height: 22)
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * min(max(fraction, 0), 1)
    }

    private func steppedValue(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct ThresholdHandle: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(.background)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
    }
}
