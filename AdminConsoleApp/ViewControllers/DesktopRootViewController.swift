import AppPlatform
import UIKit

final class DesktopRootViewController: UIViewController {
    private let canvasView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusLabel = UILabel()
    private let cursorView = UIView()
    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?
    private var windowViews: [UUID: UIView] = [:]
    private var terminalSelectionPreviews: [UUID: PhaseZeroTerminalSelection] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0)
        setupCanvas()
        setupHeader()
        setupCursor()
        setupTapToFocus()
        startUpdates()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let latestSnapshot else {
            return
        }

        render(snapshot: latestSnapshot)
    }

    deinit {
        updatesTask?.cancel()
    }

    private func setupCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = UIColor(red: 0.10, green: 0.14, blue: 0.19, alpha: 1.0)
        canvasView.layer.cornerRadius = 24
        canvasView.layer.borderWidth = 1
        canvasView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            canvasView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            canvasView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func setupHeader() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "External Desktop Scene"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Shared desktop surface driven by DesktopStore and rendered on the external display."
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.80)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        canvasView.addSubview(titleLabel)
        canvasView.addSubview(subtitleLabel)
        canvasView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: canvasView.leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: canvasView.topAnchor, constant: 24),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: canvasView.trailingAnchor, constant: -28),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: canvasView.trailingAnchor, constant: -28)
        ])
    }

    private func setupCursor() {
        cursorView.translatesAutoresizingMaskIntoConstraints = false
        cursorView.backgroundColor = .systemBlue
        cursorView.layer.cornerRadius = 9
        cursorView.layer.borderWidth = 2
        cursorView.layer.borderColor = UIColor.white.cgColor
        cursorView.layer.shadowColor = UIColor.systemBlue.cgColor
        cursorView.layer.shadowOpacity = 0.5
        cursorView.layer.shadowRadius = 14

        canvasView.addSubview(cursorView)
    }

    private func setupTapToFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCanvasTap(_:)))
        canvasView.addGestureRecognizer(tapGesture)
    }

    private func startUpdates() {
        updatesTask = Task { [weak self] in
            guard let self else {
                return
            }

            await AppEnvironment.phaseZero.startIfNeeded()
            let stream = await AppEnvironment.phaseZero.snapshots()

            for await snapshot in stream {
                await MainActor.run {
                    self.latestSnapshot = snapshot
                    self.render(snapshot: snapshot)
                }
            }
        }
    }

    private func render(snapshot: PhaseZeroSnapshot) {
        statusLabel.text = """
        Revision \(snapshot.revision)
        \(snapshot.windows.count) windows
        \(snapshot.isExternalDisplayConnected ? "Display active" : "Display inactive")
        \(Int(snapshot.displayProfile.width)) x \(Int(snapshot.displayProfile.height)) @ \(String(format: "%.1f", snapshot.displayProfile.scale))x
        """

        for view in windowViews.values {
            view.removeFromSuperview()
        }
        windowViews.removeAll()

        for window in snapshot.windows {
            let panel = makeWindowView(window: window, snapshot: snapshot)
            canvasView.addSubview(panel)
            windowViews[window.id.rawValue] = panel
        }

        let cursorSize: CGFloat = 18
        cursorView.frame = CGRect(
            x: snapshot.cursor.x * canvasView.bounds.width - cursorSize / 2,
            y: snapshot.cursor.y * canvasView.bounds.height - cursorSize / 2,
            width: cursorSize,
            height: cursorSize
        )
        canvasView.bringSubviewToFront(cursorView)
    }

    private func makeWindowView(window: PhaseZeroWindow, snapshot: PhaseZeroSnapshot) -> UIView {
        let frame = normalizedFrame(window.frame)
        let panel = UIView(frame: frame)
        panel.backgroundColor = color(for: window.kind)
        panel.layer.cornerRadius = 18
        panel.layer.borderWidth = window.isFocused ? 2 : 1
        panel.layer.borderColor = window.isFocused
            ? UIColor.systemBlue.cgColor
            : UIColor.white.withAlphaComponent(0.10).cgColor

        let chrome = UIView()
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        chrome.layer.cornerRadius = 18
        chrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = window.title
        title.textColor = .white
        title.font = .preferredFont(forTextStyle: .headline)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = windowSubtitle(window: window, snapshot: snapshot)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.66)
        subtitle.font = .preferredFont(forTextStyle: .footnote)
        subtitle.numberOfLines = 2

        let contentView = windowContentView(window: window)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(chrome)
        chrome.addSubview(title)
        panel.addSubview(subtitle)
        panel.addSubview(contentView)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: panel.topAnchor),
            chrome.heightAnchor.constraint(equalToConstant: 44),

            title.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),

            subtitle.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            subtitle.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 16),

            contentView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            contentView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -16)
        ])

        return panel
    }

    private func normalizedFrame(_ rect: PhaseZeroRect) -> CGRect {
        let width = rect.width * canvasView.bounds.width
        let height = rect.height * canvasView.bounds.height
        let x = rect.x * canvasView.bounds.width
        let y = rect.y * canvasView.bounds.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func color(for kind: PhaseZeroWindowKind) -> UIColor {
        switch kind {
        case .terminal:
            return UIColor(red: 0.16, green: 0.20, blue: 0.15, alpha: 1.0)
        case .files:
            return UIColor(red: 0.18, green: 0.16, blue: 0.22, alpha: 1.0)
        case .browser:
            return UIColor(red: 0.13, green: 0.18, blue: 0.24, alpha: 1.0)
        case .vnc:
            return UIColor(red: 0.19, green: 0.15, blue: 0.14, alpha: 1.0)
        }
    }

    private func windowSubtitle(window: PhaseZeroWindow, snapshot: PhaseZeroSnapshot) -> String {
        if let terminalState = window.terminalState {
            return "\(terminalState.connectionTitle) • \(terminalState.statusMessage)"
        }

        if let filesState = window.filesState {
            return "\(filesState.currentPath) • \(filesState.statusMessage)"
        }

        if let vncState = window.vncState {
            return "\(vncState.connectionTitle) • \(vncState.statusMessage)"
        }

        return window.id.rawValue.uuidString.prefix(8) + " • " + snapshot.lastInputDescription
    }

    private func windowContentView(window: PhaseZeroWindow) -> UIView {
        switch window.kind {
        case .terminal:
            return makeTerminalContent(window: window)
        case .files:
            return makeFilesContent(window: window)
        case .browser:
            return makePlaceholderContent(
                title: "Browser runtime placeholder",
                detail: "The web module remains hosted in-app. The next step is promoting the Browser spike into a managed desktop window."
            )
        case .vnc:
            return makeVNCContent(window: window)
        }
    }

    private func makeTerminalContent(window: PhaseZeroWindow) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        let badgeLabel = UILabel()
        badgeLabel.font = .preferredFont(forTextStyle: .caption1)
        badgeLabel.textColor = badgeColor(for: window.terminalState)
        badgeLabel.text = badgeTitle(for: window.terminalState)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.74)
        metaLabel.numberOfLines = 0
        metaLabel.text = terminalMetaText(window.terminalState)

        let transcriptView = TerminalViewportTextView()
        transcriptView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        transcriptView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        transcriptView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        transcriptView.textContainer.lineFragmentPadding = 0
        transcriptView.layer.cornerRadius = 12
        transcriptView.isEditable = false
        transcriptView.isSelectable = false
        transcriptView.isScrollEnabled = false
        transcriptView.windowID = window.id
        transcriptView.terminalState = window.terminalState
        transcriptView.selectionPreview = terminalSelectionPreviews[window.id.rawValue] ?? window.terminalState?.selection
        transcriptView.attributedText = terminalAttributedPreview(window.terminalState, selection: transcriptView.selectionPreview)
        transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let selectionGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTerminalSelectionGesture(_:)))
        selectionGesture.minimumPressDuration = 0
        selectionGesture.allowableMovement = .greatestFiniteMagnitude
        transcriptView.addGestureRecognizer(selectionGesture)

        [badgeLabel, metaLabel, transcriptView].forEach(stack.addArrangedSubview)
        return stack
    }

    private func makeFilesContent(window: PhaseZeroWindow) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        let pathLabel = UILabel()
        pathLabel.font = .preferredFont(forTextStyle: .caption1)
        pathLabel.textColor = UIColor.systemTeal
        pathLabel.numberOfLines = 0
        pathLabel.text = filesPathText(window.filesState)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.74)
        metaLabel.numberOfLines = 0
        metaLabel.text = filesMetaText(window.filesState)

        let entriesView = UITextView()
        entriesView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        entriesView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        entriesView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        entriesView.textContainer.lineFragmentPadding = 0
        entriesView.layer.cornerRadius = 12
        entriesView.isEditable = false
        entriesView.isSelectable = true
        entriesView.isScrollEnabled = true
        entriesView.textColor = UIColor.white.withAlphaComponent(0.92)
        entriesView.text = filesEntriesText(window.filesState)
        entriesView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let previewLabel = UILabel()
        previewLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        previewLabel.textColor = UIColor.white.withAlphaComponent(0.80)
        previewLabel.numberOfLines = 0
        previewLabel.text = filesPreviewText(window.filesState)

        [pathLabel, metaLabel, entriesView, previewLabel].forEach(stack.addArrangedSubview)
        return stack
    }

    private func makeVNCContent(window: PhaseZeroWindow) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        let badgeLabel = UILabel()
        badgeLabel.font = .preferredFont(forTextStyle: .caption1)
        badgeLabel.textColor = vncBadgeColor(for: window.vncState)
        badgeLabel.text = vncBadgeTitle(for: window.vncState)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.74)
        metaLabel.numberOfLines = 0
        metaLabel.text = vncMetaText(window.vncState)

        if let image = vncFramebufferImage(window.vncState) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 12
            imageView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
            stack.addArrangedSubview(imageView)
        }

        let framebufferView = UITextView()
        framebufferView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        framebufferView.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        framebufferView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        framebufferView.textContainer.lineFragmentPadding = 0
        framebufferView.layer.cornerRadius = 12
        framebufferView.isEditable = false
        framebufferView.isSelectable = true
        framebufferView.isScrollEnabled = true
        framebufferView.textColor = UIColor.white.withAlphaComponent(0.92)
        framebufferView.text = window.vncState?.frame.renderedText ?? "No VNC framebuffer yet."
        framebufferView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

        [badgeLabel, metaLabel, framebufferView].forEach(stack.addArrangedSubview)
        return stack
    }

    private func makePlaceholderContent(title: String, detail: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        [titleLabel, detailLabel].forEach(stack.addArrangedSubview)
        return stack
    }

    private func badgeTitle(for state: PhaseZeroTerminalState?) -> String {
        switch state?.sessionState {
        case .idle?:
            return "Idle"
        case .connecting?:
            return "Connecting"
        case .connected?:
            return "Connected"
        case .failed?:
            return "Ended"
        case nil:
            return "Ready"
        }
    }

    private func badgeColor(for state: PhaseZeroTerminalState?) -> UIColor {
        switch state?.sessionState {
        case .idle?:
            return UIColor.white.withAlphaComponent(0.85)
        case .connecting?:
            return UIColor.systemOrange
        case .connected?:
            return UIColor.systemGreen
        case .failed?:
            return UIColor.systemRed
        case nil:
            return UIColor.white.withAlphaComponent(0.85)
        }
    }

    private func terminalMetaText(_ state: PhaseZeroTerminalState?) -> String {
        guard let state else {
            return "Ready for SSH runtime."
        }

        if let screenTitle = state.screenTitle, !screenTitle.isEmpty {
            return "\(state.connectionTitle)\nTitle: \(screenTitle)\n\(state.columns) x \(state.rows) • \(state.statusMessage)"
        }

        return "\(state.connectionTitle)\n\(state.columns) x \(state.rows) • \(state.statusMessage)"
    }

    private func filesPathText(_ state: PhaseZeroFilesState?) -> String {
        guard let state else {
            return "Workspace unavailable"
        }

        return "Workspace: \(state.workspaceName)\nPath: \(state.currentPath)"
    }

    private func filesMetaText(_ state: PhaseZeroFilesState?) -> String {
        guard let state else {
            return "No files runtime yet."
        }

        let selected = state.selectedEntry?.name ?? "none"
        return "Items: \(state.entries.count)\nSelected: \(selected)\n\(state.statusMessage)"
    }

    private func vncBadgeTitle(for state: PhaseZeroVNCState?) -> String {
        switch state?.sessionState {
        case .idle?:
            return "Idle"
        case .connecting?:
            return "Connecting"
        case .connected?:
            return "Connected"
        case .failed?:
            return "Ended"
        case nil:
            return "Ready"
        }
    }

    private func vncBadgeColor(for state: PhaseZeroVNCState?) -> UIColor {
        switch state?.sessionState {
        case .idle?:
            return UIColor.white.withAlphaComponent(0.85)
        case .connecting?:
            return UIColor.systemOrange
        case .connected?:
            return UIColor.systemGreen
        case .failed?:
            return UIColor.systemRed
        case nil:
            return UIColor.white.withAlphaComponent(0.85)
        }
    }

    private func vncMetaText(_ state: PhaseZeroVNCState?) -> String {
        guard let state else {
            return "Ready for VNC runtime."
        }

        let events = state.recentEvents.suffix(3).joined(separator: " | ")
        let clipboardState = state.remoteClipboardText?.isEmpty == false ? "available" : "empty"
        let activeButtons = state.activePointerButtons.isEmpty ? "none" : state.activePointerButtons.joined(separator: ", ")
        return "\(state.connectionTitle)\nQuality: \(state.qualityPreset) • Trackpad: \(state.isTrackpadModeEnabled ? "on" : "off") • Bells: \(state.bellCount)\nButtons: \(activeButtons) • Clipboard: \(clipboardState)\n\(state.statusMessage)\n\(events)"
    }

    private func vncFramebufferImage(_ state: PhaseZeroVNCState?) -> UIImage? {
        guard let frame = state?.frame, frame.hasPixelBuffer else {
            return nil
        }

        let bytesPerRow = frame.pixelWidth * MemoryLayout<UInt32>.size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        let data = frame.rgbaPixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: frame.pixelWidth,
                height: frame.pixelHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func filesEntriesText(_ state: PhaseZeroFilesState?) -> String {
        guard let state else {
            return "No files screen yet."
        }

        if state.entries.isEmpty {
            return "Folder is empty."
        }

        return state.entries.prefix(12).map { entry in
            let prefix = entry.kind == .directory ? "[DIR]" : "[FILE]"
            let marker = entry.id == state.selectedEntryID ? ">" : " "
            return "\(marker) \(prefix) \(entry.name)"
        }.joined(separator: "\n")
    }

    private func filesPreviewText(_ state: PhaseZeroFilesState?) -> String {
        state?.previewText ?? "No preview available."
    }

    private func terminalAttributedPreview(
        _ state: PhaseZeroTerminalState?,
        selection: PhaseZeroTerminalSelection? = nil
    ) -> NSAttributedString {
        guard let state else {
            return NSAttributedString(
                string: "No terminal screen yet.",
                attributes: [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                ]
            )
        }

        let attributed = NSMutableAttributedString()
        let lines = state.buffer.renderedStyledLines(insertingCursor: state.sessionState == .connected)
        let effectiveSelection = selection ?? state.selection

        for (lineIndex, line) in lines.enumerated() {
            for (columnIndex, cell) in line.cells.enumerated() {
                let point = PhaseZeroTerminalGridPoint(row: lineIndex, column: columnIndex)
                attributed.append(
                    NSAttributedString(
                        string: cell.character,
                        attributes: terminalAttributes(
                            for: cell.style,
                            isSelected: effectiveSelection.map { state.buffer.contains(point, in: $0) } ?? false
                        )
                    )
                )
            }

            if lineIndex < lines.count - 1 {
                attributed.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: terminalAttributes(for: .default)
                    )
                )
            }
        }

        return attributed
    }

    private func terminalAttributes(
        for style: PhaseZeroTerminalTextStyle,
        isSelected: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        let fontSize: CGFloat = 13
        let baseForeground = terminalUIColor(for: style.foreground, fallback: UIColor.white.withAlphaComponent(0.92))
        let baseBackground = terminalUIColor(for: style.background, fallback: .clear)
        let foreground = style.isInverse ? baseBackground.resolvedVisibleColor(fallback: UIColor.white.withAlphaComponent(0.92)) : baseForeground
        let background = style.isInverse ? baseForeground : baseBackground
        let resolvedForeground = isSelected ? UIColor.white : foreground
        let resolvedBackground = isSelected ? UIColor.systemBlue.withAlphaComponent(0.45) : background

        var attributes: [NSAttributedString.Key: Any] = [
            .font: terminalFont(size: fontSize, style: style),
            .foregroundColor: resolvedForeground
        ]

        if !resolvedBackground.isFullyTransparent {
            attributes[.backgroundColor] = resolvedBackground
        }

        if style.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attributes
    }

    private func terminalFont(size: CGFloat, style: PhaseZeroTerminalTextStyle) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.monospaced) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)

        var traits: UIFontDescriptor.SymbolicTraits = []
        if style.isBold {
            traits.insert(.traitBold)
        }
        if style.isItalic {
            traits.insert(.traitItalic)
        }

        let finalDescriptor = descriptor.withSymbolicTraits(traits) ?? descriptor
        return UIFont(descriptor: finalDescriptor, size: size)
    }

    private func terminalUIColor(for color: PhaseZeroTerminalColor, fallback: UIColor) -> UIColor {
        switch color {
        case .default:
            return fallback
        case .ansi256(let index):
            return terminalANSIColor(index: index)
        case .rgb(let red, let green, let blue):
            return UIColor(
                red: CGFloat(red) / 255.0,
                green: CGFloat(green) / 255.0,
                blue: CGFloat(blue) / 255.0,
                alpha: 1.0
            )
        }
    }

    private func terminalANSIColor(index: Int) -> UIColor {
        let palette16: [UIColor] = [
            UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
            UIColor(red: 0.80, green: 0.24, blue: 0.22, alpha: 1.0),
            UIColor(red: 0.35, green: 0.69, blue: 0.30, alpha: 1.0),
            UIColor(red: 0.84, green: 0.67, blue: 0.25, alpha: 1.0),
            UIColor(red: 0.30, green: 0.49, blue: 0.85, alpha: 1.0),
            UIColor(red: 0.69, green: 0.35, blue: 0.78, alpha: 1.0),
            UIColor(red: 0.28, green: 0.67, blue: 0.71, alpha: 1.0),
            UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
            UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1.0),
            UIColor(red: 0.95, green: 0.36, blue: 0.34, alpha: 1.0),
            UIColor(red: 0.49, green: 0.86, blue: 0.39, alpha: 1.0),
            UIColor(red: 0.98, green: 0.83, blue: 0.37, alpha: 1.0),
            UIColor(red: 0.42, green: 0.62, blue: 0.97, alpha: 1.0),
            UIColor(red: 0.83, green: 0.52, blue: 0.95, alpha: 1.0),
            UIColor(red: 0.43, green: 0.84, blue: 0.88, alpha: 1.0),
            UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)
        ]

        let clamped = max(0, min(255, index))
        if clamped < palette16.count {
            return palette16[clamped]
        }

        if clamped >= 16 && clamped <= 231 {
            let cubeIndex = clamped - 16
            let red = cubeIndex / 36
            let green = (cubeIndex % 36) / 6
            let blue = cubeIndex % 6
            let values: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return UIColor(
                red: values[red] / 255.0,
                green: values[green] / 255.0,
                blue: values[blue] / 255.0,
                alpha: 1.0
            )
        }

        let gray = CGFloat(8 + (clamped - 232) * 10) / 255.0
        return UIColor(red: gray, green: gray, blue: gray, alpha: 1.0)
    }

    @objc
    private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
        guard let latestSnapshot else {
            return
        }

        let point = gesture.location(in: canvasView)
        let normalizedPoint = CGPoint(
            x: point.x / max(canvasView.bounds.width, 1),
            y: point.y / max(canvasView.bounds.height, 1)
        )

        guard let selectedWindow = latestSnapshot.windows.reversed().first(where: { window in
            let frame = window.frame
            return normalizedPoint.x >= frame.x &&
                normalizedPoint.x <= frame.x + frame.width &&
                normalizedPoint.y >= frame.y &&
                normalizedPoint.y <= frame.y + frame.height
        }) else {
            return
        }

        Task {
            await AppEnvironment.phaseZero.focusWindow(selectedWindow.id)
            await AppEnvironment.phaseZero.registerControlInput("Desktop tap focus: \(selectedWindow.title)")
        }
    }

    @objc
    private func handleTerminalSelectionGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let transcriptView = gesture.view as? TerminalViewportTextView,
              let terminalState = transcriptView.terminalState else {
            return
        }

        let point = gesture.location(in: transcriptView)
        let geometry = TerminalSelectionGeometry(
            columns: terminalState.columns,
            rows: terminalState.rows,
            viewportSize: transcriptView.bounds.size,
            insets: TerminalViewportInsets(
                top: transcriptView.textContainerInset.top,
                left: transcriptView.textContainerInset.left,
                bottom: transcriptView.textContainerInset.bottom,
                right: transcriptView.textContainerInset.right
            )
        )

        switch gesture.state {
        case .began:
            let anchor = geometry.gridPoint(for: point)
            let selection = PhaseZeroTerminalSelection(anchor: anchor, focus: anchor)
            transcriptView.selectionAnchor = anchor
            transcriptView.selectionPreview = selection
            terminalSelectionPreviews[transcriptView.windowID.rawValue] = selection
            transcriptView.attributedText = terminalAttributedPreview(terminalState, selection: selection)
            Task {
                await AppEnvironment.phaseZero.focusWindow(transcriptView.windowID)
            }
        case .changed:
            guard let anchor = transcriptView.selectionAnchor else {
                return
            }

            let selection = PhaseZeroTerminalSelection(anchor: anchor, focus: geometry.gridPoint(for: point))
            transcriptView.selectionPreview = selection
            terminalSelectionPreviews[transcriptView.windowID.rawValue] = selection
            transcriptView.attributedText = terminalAttributedPreview(terminalState, selection: selection)
        case .ended:
            let selection = transcriptView.selectionPreview
            if let selection {
                terminalSelectionPreviews.removeValue(forKey: transcriptView.windowID.rawValue)
                Task {
                    await AppEnvironment.phaseZero.focusWindow(transcriptView.windowID)
                    await AppEnvironment.phaseZero.updateFocusedTerminalSelection(selection)
                    await AppEnvironment.phaseZero.registerControlInput("Terminal selection updated")
                }
            }
            transcriptView.selectionAnchor = nil
            transcriptView.selectionPreview = nil
        case .cancelled, .failed:
            terminalSelectionPreviews.removeValue(forKey: transcriptView.windowID.rawValue)
            transcriptView.selectionAnchor = nil
            transcriptView.selectionPreview = nil
            transcriptView.attributedText = terminalAttributedPreview(terminalState, selection: terminalState.selection)
        default:
            break
        }
    }
}

private extension UIColor {
    var isFullyTransparent: Bool {
        cgColor.alpha == 0
    }

    func resolvedVisibleColor(fallback: UIColor) -> UIColor {
        if isFullyTransparent {
            return fallback
        }
        return self
    }
}

private final class TerminalViewportTextView: UITextView {
    var windowID: PhaseZeroWindowID = PhaseZeroWindowID()
    var terminalState: PhaseZeroTerminalState?
    var selectionAnchor: PhaseZeroTerminalGridPoint?
    var selectionPreview: PhaseZeroTerminalSelection?
}
