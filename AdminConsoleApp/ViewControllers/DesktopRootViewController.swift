import UIKit
import WebKit

final class DesktopRootViewController: UIViewController {
    private let canvasView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusLabel = UILabel()
    private let captureBadgeView = UIView()
    private let captureBadgeLabel = UILabel()
    private let cursorView = UIView()
    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?
    private var windowViews: [UUID: UIView] = [:]
    private var terminalSelectionPreviews: [UUID: PhaseZeroTerminalSelection] = [:]
    private var browserWebViews: [UUID: WKWebView] = [:]
    private var browserDelegates: [UUID: BrowserNavigationDelegateProxy] = [:]
    private var browserLastAppliedCommandID: [UUID: Int] = [:]
    private var lastRenderedCanvasSize: CGSize = .zero

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

        if canvasView.bounds.size != lastRenderedCanvasSize {
            render(snapshot: latestSnapshot)
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    private func setupCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = UIColor(red: 0.10, green: 0.14, blue: 0.19, alpha: 1.0)

        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupHeader() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "External Desktop Scene"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Shared desktop surface on external display. Use iPhone controls to focus and maximize windows."
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.80)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        captureBadgeView.translatesAutoresizingMaskIntoConstraints = false
        captureBadgeView.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        captureBadgeView.layer.cornerRadius = 12
        captureBadgeView.layer.borderWidth = 1
        captureBadgeView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor

        captureBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        captureBadgeLabel.textColor = .white
        captureBadgeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        captureBadgeLabel.numberOfLines = 2
        captureBadgeLabel.text = "CAPTURE: AUTO"

        canvasView.addSubview(titleLabel)
        canvasView.addSubview(subtitleLabel)
        canvasView.addSubview(statusLabel)
        canvasView.addSubview(captureBadgeView)
        captureBadgeView.addSubview(captureBadgeLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: canvasView.leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: canvasView.safeAreaLayoutGuide.topAnchor, constant: 16),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: canvasView.trailingAnchor, constant: -28),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: canvasView.trailingAnchor, constant: -28),

            captureBadgeView.topAnchor.constraint(equalTo: canvasView.safeAreaLayoutGuide.topAnchor, constant: 20),
            captureBadgeView.trailingAnchor.constraint(equalTo: canvasView.trailingAnchor, constant: -20),
            captureBadgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),

            captureBadgeLabel.leadingAnchor.constraint(equalTo: captureBadgeView.leadingAnchor, constant: 12),
            captureBadgeLabel.trailingAnchor.constraint(equalTo: captureBadgeView.trailingAnchor, constant: -12),
            captureBadgeLabel.topAnchor.constraint(equalTo: captureBadgeView.topAnchor, constant: 8),
            captureBadgeLabel.bottomAnchor.constraint(equalTo: captureBadgeView.bottomAnchor, constant: -8)
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
        lastRenderedCanvasSize = canvasView.bounds.size
        statusLabel.text = """
        Revision \(snapshot.revision)
        Active mode: \(snapshot.activeWorkMode.rawValue.uppercased())
        \(snapshot.windows.count) windows available
        \(snapshot.isExternalDisplayConnected ? "Display active" : "Display inactive")
        Input capture: \(snapshot.inputCaptureMode.rawValue.capitalized)
        \(Int(snapshot.displayProfile.width)) x \(Int(snapshot.displayProfile.height)) @ \(String(format: "%.1f", snapshot.displayProfile.scale))x
        """
        captureBadgeLabel.text = captureBadgeText(for: snapshot)

        for view in windowViews.values {
            view.removeFromSuperview()
        }
        windowViews.removeAll()

        let liveBrowserWindowIDs = Set(
            snapshot.windows
                .filter { $0.kind == .browser }
                .map { $0.id.rawValue }
        )
        browserWebViews = browserWebViews.filter { liveBrowserWindowIDs.contains($0.key) }
        browserDelegates = browserDelegates.filter { liveBrowserWindowIDs.contains($0.key) }
        browserLastAppliedCommandID = browserLastAppliedCommandID.filter { liveBrowserWindowIDs.contains($0.key) }

        if let activeWindow = mirroredActiveWindow(in: snapshot) {
            let panel = makeWindowView(window: activeWindow, snapshot: snapshot)
            panel.frame = CGRect(
                x: 14,
                y: 72,
                width: max(canvasView.bounds.width - 28, 120),
                height: max(canvasView.bounds.height - 86, 120)
            )
            panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvasView.addSubview(panel)
            windowViews[activeWindow.id.rawValue] = panel
        } else {
            let emptyState = makeEmptyMirrorPlaceholder()
            canvasView.addSubview(emptyState)
            emptyState.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                emptyState.centerXAnchor.constraint(equalTo: canvasView.centerXAnchor),
                emptyState.centerYAnchor.constraint(equalTo: canvasView.centerYAnchor),
                emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: canvasView.leadingAnchor, constant: 24),
                emptyState.trailingAnchor.constraint(lessThanOrEqualTo: canvasView.trailingAnchor, constant: -24)
            ])
        }

        let cursorSize: CGFloat = 18
        cursorView.frame = CGRect(
            x: snapshot.cursor.x * canvasView.bounds.width - cursorSize / 2,
            y: snapshot.cursor.y * canvasView.bounds.height - cursorSize / 2,
            width: cursorSize,
            height: cursorSize
        )
        canvasView.bringSubviewToFront(cursorView)
        canvasView.bringSubviewToFront(captureBadgeView)
    }

    private func captureBadgeText(for snapshot: PhaseZeroSnapshot) -> String {
        let mode = snapshot.inputCaptureMode.rawValue.uppercased()
        let targetID = inputCaptureTargetID(in: snapshot)

        let destination = snapshot.windows.first(where: { $0.id == targetID })?.title ?? "NONE"

        return """
        CAPTURE: \(mode)
        TARGET: \(destination.uppercased())
        """
    }

    private func mirroredActiveWindow(in snapshot: PhaseZeroSnapshot) -> PhaseZeroWindow? {
        snapshot.windows.last(where: { $0.kind == snapshot.activeWorkMode.windowKind })
            ?? snapshot.windows.last
    }

    private func makeEmptyMirrorPlaceholder() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.font = .preferredFont(forTextStyle: .title3)
        label.text = "No active runtime for current mode.\nOpen SSH, VNC, or Browser on iPhone."
        return label
    }

    private func inputCaptureTargetID(in snapshot: PhaseZeroSnapshot) -> PhaseZeroWindowID? {
        switch snapshot.inputCaptureMode {
        case .automatic:
            return snapshot.focusedWindowID ?? snapshot.windows.last?.id
        case .terminal:
            return snapshot.windows.last(where: { $0.kind == .terminal })?.id
        case .vnc:
            return snapshot.windows.last(where: { $0.kind == .vnc })?.id
        }
    }

    private func makeWindowView(window: PhaseZeroWindow, snapshot: PhaseZeroSnapshot) -> UIView {
        let frame = normalizedFrame(window.frame)
        let panel = UIView(frame: frame)
        let isCaptureTarget = inputCaptureTargetID(in: snapshot) == window.id
        panel.backgroundColor = color(for: window.kind)
        panel.layer.cornerRadius = 18
        panel.layer.borderWidth = isCaptureTarget ? 3 : (window.isFocused ? 2 : 1)
        panel.layer.borderColor = isCaptureTarget
            ? UIColor.systemGreen.withAlphaComponent(0.95).cgColor
            : (window.isFocused
                ? UIColor.systemBlue.cgColor
                : UIColor.white.withAlphaComponent(0.10).cgColor)
        panel.layer.shadowColor = isCaptureTarget ? UIColor.systemGreen.cgColor : UIColor.clear.cgColor
        panel.layer.shadowOpacity = isCaptureTarget ? 0.38 : 0
        panel.layer.shadowRadius = isCaptureTarget ? 16 : 0
        panel.layer.shadowOffset = .zero

        let chrome = WindowChromeView()
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        chrome.layer.cornerRadius = 18
        chrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        chrome.windowID = window.id
        chrome.windowFrame = window.frame
        chrome.isWindowMaximized = window.isMaximized

        let chromePan = UIPanGestureRecognizer(target: self, action: #selector(handleWindowChromePan(_:)))
        chrome.addGestureRecognizer(chromePan)

        let chromeDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleWindowChromeDoubleTap(_:)))
        chromeDoubleTap.numberOfTapsRequired = 2
        chrome.addGestureRecognizer(chromeDoubleTap)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = window.title
        title.textColor = .white
        title.font = .preferredFont(forTextStyle: .headline)

        let captureChip = UILabel()
        captureChip.translatesAutoresizingMaskIntoConstraints = false
        captureChip.text = "INPUT"
        captureChip.textColor = .white
        captureChip.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        captureChip.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.78)
        captureChip.layer.cornerRadius = 8
        captureChip.layer.masksToBounds = true
        captureChip.textAlignment = .center
        captureChip.alpha = isCaptureTarget ? 1 : 0

        let controlsStack = UIStackView()
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .horizontal
        controlsStack.spacing = 8
        controlsStack.alignment = .center

        let maximizeButton = UIButton(type: .system)
        maximizeButton.translatesAutoresizingMaskIntoConstraints = false
        maximizeButton.tintColor = .white
        maximizeButton.setImage(UIImage(systemName: window.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"), for: .normal)
        maximizeButton.accessibilityLabel = window.isMaximized ? "Restore window" : "Maximize window"
        maximizeButton.addAction(UIAction { _ in
            Task {
                await AppEnvironment.phaseZero.toggleWindowMaximized(window.id)
                await AppEnvironment.phaseZero.focusWindow(window.id)
            }
        }, for: .touchUpInside)
        maximizeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        maximizeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = UIColor.systemRed.withAlphaComponent(0.92)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.accessibilityLabel = "Close window"
        closeButton.addAction(UIAction { _ in
            Task {
                await AppEnvironment.phaseZero.closeWindow(window.id)
            }
        }, for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        controlsStack.addArrangedSubview(maximizeButton)
        controlsStack.addArrangedSubview(closeButton)

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
        chrome.addSubview(captureChip)
        chrome.addSubview(controlsStack)
        panel.addSubview(subtitle)
        panel.addSubview(contentView)

        var reconnectIndicator: UIView?
        if window.kind == .vnc,
           let indicator = makeVNCReconnectIndicator(for: window.vncState) {
            indicator.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(indicator)
            reconnectIndicator = indicator
        }

        let resizeHandle = WindowResizeHandleView()
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.windowID = window.id
        resizeHandle.windowFrame = window.frame
        resizeHandle.isWindowMaximized = window.isMaximized
        panel.addSubview(resizeHandle)

        let resizeIcon = UIImageView(image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"))
        resizeIcon.translatesAutoresizingMaskIntoConstraints = false
        resizeIcon.tintColor = UIColor.white.withAlphaComponent(0.9)
        resizeIcon.contentMode = .scaleAspectFit
        resizeHandle.addSubview(resizeIcon)

        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleWindowResizePan(_:)))
        resizeHandle.addGestureRecognizer(resizePan)

        let captureChipWidthConstraint = captureChip.widthAnchor.constraint(
            equalToConstant: isCaptureTarget ? 50 : 0
        )

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: panel.topAnchor),
            chrome.heightAnchor.constraint(equalToConstant: 44),

            title.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),

            captureChip.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            captureChip.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
            captureChipWidthConstraint,
            captureChip.heightAnchor.constraint(equalToConstant: 18),

            controlsStack.leadingAnchor.constraint(greaterThanOrEqualTo: captureChip.trailingAnchor, constant: 8),

            controlsStack.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -12),
            controlsStack.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),

            subtitle.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            subtitle.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 16),

            contentView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            contentView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -16)
        ])

        if let reconnectIndicator {
            NSLayoutConstraint.activate([
                reconnectIndicator.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
                reconnectIndicator.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10)
            ])
        }

        NSLayoutConstraint.activate([
            resizeHandle.widthAnchor.constraint(equalToConstant: 28),
            resizeHandle.heightAnchor.constraint(equalToConstant: 28),
            resizeHandle.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            resizeHandle.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),

            resizeIcon.centerXAnchor.constraint(equalTo: resizeHandle.centerXAnchor),
            resizeIcon.centerYAnchor.constraint(equalTo: resizeHandle.centerYAnchor),
            resizeIcon.widthAnchor.constraint(equalToConstant: 14),
            resizeIcon.heightAnchor.constraint(equalToConstant: 14)
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
            let suffix = window.isMaximized ? " • Fullscreen" : ""
            return "\(terminalState.connectionTitle) • \(terminalState.statusMessage)\(suffix)"
        }

        if let filesState = window.filesState {
            let suffix = window.isMaximized ? " • Fullscreen" : ""
            return "\(filesState.currentPath) • \(filesState.statusMessage)\(suffix)"
        }

        if let browserState = window.browserState {
            let current = browserState.currentURLString ?? browserState.homeURLString
            let suffix = window.isMaximized ? " • Fullscreen" : ""
            return "\(current) • \(browserState.statusMessage)\(suffix)"
        }

        if let vncState = window.vncState {
            let suffix = window.isMaximized ? " • Fullscreen" : ""
            return "\(vncState.connectionTitle) • \(vncState.statusMessage)\(suffix)"
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
            return makeBrowserContent(window: window)
        case .vnc:
            return makeVNCContent(window: window)
        }
    }

    private func makeBrowserContent(window: PhaseZeroWindow) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        let badgeLabel = UILabel()
        badgeLabel.font = .preferredFont(forTextStyle: .caption1)
        badgeLabel.textColor = browserBadgeColor(for: window.browserState)
        badgeLabel.text = browserBadgeTitle(for: window.browserState)

        let metaLabel = UILabel()
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.74)
        metaLabel.numberOfLines = 0
        metaLabel.text = browserMetaText(window.browserState)

        let webViewContainer = UIView()
        webViewContainer.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        webViewContainer.layer.cornerRadius = 12
        webViewContainer.clipsToBounds = true

        let webView = browserWebView(for: window.id.rawValue)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
        ])
        webViewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        if let state = window.browserState {
            applyBrowserState(state, to: webView, windowID: window.id.rawValue)
            if let statusOverlay = browserStatusOverlay(for: state) {
                webViewContainer.addSubview(statusOverlay)
                NSLayoutConstraint.activate([
                    statusOverlay.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor, constant: 10),
                    statusOverlay.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor, constant: -10),
                    statusOverlay.topAnchor.constraint(equalTo: webViewContainer.topAnchor, constant: 10)
                ])
            }
        }

        [badgeLabel, metaLabel, webViewContainer].forEach(stack.addArrangedSubview)
        return stack
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
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        container.layer.cornerRadius = 12
        container.clipsToBounds = true

        if let image = vncFramebufferImage(window.vncState) {
            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
            container.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            let placeholder = UITextView()
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            placeholder.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            placeholder.backgroundColor = UIColor.black.withAlphaComponent(0.12)
            placeholder.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            placeholder.textContainer.lineFragmentPadding = 0
            placeholder.isEditable = false
            placeholder.isSelectable = true
            placeholder.isScrollEnabled = true
            placeholder.textColor = UIColor.white.withAlphaComponent(0.92)
            placeholder.text = window.vncState?.frame.renderedText ?? "No VNC framebuffer yet."
            container.addSubview(placeholder)

            NSLayoutConstraint.activate([
                placeholder.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                placeholder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                placeholder.topAnchor.constraint(equalTo: container.topAnchor),
                placeholder.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        if let state = window.vncState {
            let overlay = UILabel()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.font = .preferredFont(forTextStyle: .caption1)
            overlay.numberOfLines = 0
            overlay.textColor = .white
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.52)
            overlay.layer.cornerRadius = 8
            overlay.clipsToBounds = true
            overlay.text = " \(vncBadgeTitle(for: state)) • \(state.statusMessage) "
            container.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
                overlay.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
                overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
            ])
        }

        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        return container
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

    private func browserBadgeTitle(for state: PhaseZeroBrowserState?) -> String {
        guard let state else {
            return "Ready"
        }

        return state.isLoading ? "Loading" : "Active"
    }

    private func browserBadgeColor(for state: PhaseZeroBrowserState?) -> UIColor {
        guard let state else {
            return UIColor.white.withAlphaComponent(0.85)
        }

        return state.isLoading ? UIColor.systemOrange : UIColor.systemBlue
    }

    private func browserMetaText(_ state: PhaseZeroBrowserState?) -> String {
        guard let state else {
            return "Ready for browser runtime."
        }

        let current = state.currentURLString ?? state.homeURLString
        let title = state.pageTitle ?? "Untitled"
        return "\(title)\n\(current)\nBack: \(state.canGoBack ? "yes" : "no") • Forward: \(state.canGoForward ? "yes" : "no")\n\(state.statusMessage)"
    }

    private func browserStatusOverlay(for state: PhaseZeroBrowserState) -> UIView? {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6

        var hasContent = false
        if state.isLoading {
            let progress = UIProgressView(progressViewStyle: .default)
            progress.progress = 0.35
            progress.tintColor = .systemBlue
            progress.trackTintColor = UIColor.white.withAlphaComponent(0.22)
            stack.addArrangedSubview(progress)
            hasContent = true
        }

        if state.statusMessage.hasPrefix("Load failed:") || state.statusMessage.hasPrefix("Blocked:") {
            let label = UILabel()
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = .white
            label.text = state.statusMessage
            label.backgroundColor = UIColor.black.withAlphaComponent(0.48)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.textAlignment = .center
            stack.addArrangedSubview(label)
            hasContent = true
        }

        return hasContent ? stack : nil
    }

    private func browserWebView(for windowUUID: UUID) -> WKWebView {
        if let webView = browserWebViews[windowUUID] {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .onDrag

        let delegate = BrowserNavigationDelegateProxy { [weak self] event in
            self?.handleBrowserNavigationEvent(event, windowUUID: windowUUID)
        }
        webView.navigationDelegate = delegate

        browserWebViews[windowUUID] = webView
        browserDelegates[windowUUID] = delegate
        return webView
    }

    private func applyBrowserState(
        _ state: PhaseZeroBrowserState,
        to webView: WKWebView,
        windowID: UUID
    ) {
        applyBrowserCommandIfNeeded(state, to: webView, windowID: windowID)

        let targetURLString = state.currentURLString ?? state.homeURLString
        guard let targetURL = URL(string: targetURLString) else {
            return
        }

        if shouldLoadBrowserURL(targetURL, for: webView) {
            webView.load(URLRequest(url: targetURL))
        }
    }

    private func applyBrowserCommandIfNeeded(
        _ state: PhaseZeroBrowserState,
        to webView: WKWebView,
        windowID: UUID
    ) {
        guard let command = state.navigationCommand else {
            return
        }

        let commandID = state.navigationCommandID
        let lastApplied = browserLastAppliedCommandID[windowID] ?? 0
        guard commandID > lastApplied else {
            return
        }

        browserLastAppliedCommandID[windowID] = commandID
        switch command {
        case .reload:
            webView.reload()
        case .goBack:
            if webView.canGoBack {
                webView.goBack()
            }
        case .goForward:
            if webView.canGoForward {
                webView.goForward()
            }
        }

        let windowID = PhaseZeroWindowID(rawValue: windowID)
        Task {
            await AppEnvironment.phaseZero.acknowledgeBrowserNavigationCommand(
                windowID: windowID,
                commandID: commandID
            )
        }
    }

    private func shouldLoadBrowserURL(_ targetURL: URL, for webView: WKWebView) -> Bool {
        guard let currentURL = webView.url else {
            return true
        }

        return normalizedURLString(targetURL) != normalizedURLString(currentURL)
    }

    private func normalizedURLString(_ url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let normalized = components.url?.absoluteString {
            return normalized
        }

        return url.absoluteString
    }

    private func handleBrowserNavigationEvent(_ event: BrowserNavigationEvent, windowUUID: UUID) {
        let windowID = PhaseZeroWindowID(rawValue: windowUUID)
        Task {
            switch event {
            case .stateChanged(let snapshot):
                await AppEnvironment.phaseZero.syncBrowserHostState(
                    windowID: windowID,
                    urlString: snapshot.urlString,
                    title: snapshot.title,
                    isLoading: snapshot.isLoading,
                    canGoBack: snapshot.canGoBack,
                    canGoForward: snapshot.canGoForward
                )
            case .failed(let message):
                await AppEnvironment.phaseZero.reportBrowserNavigationFailure(
                    windowID: windowID,
                    message: message
                )
            case .blocked(let urlString, let reason):
                await AppEnvironment.phaseZero.reportBrowserNavigationBlocked(
                    windowID: windowID,
                    urlString: urlString,
                    reason: reason
                )
            }
        }
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

    private func makeVNCReconnectIndicator(for state: PhaseZeroVNCState?) -> UIView? {
        guard let state,
              state.sessionState == .connecting,
              let attempt = state.reconnectAttempt,
              let seconds = state.reconnectSecondsRemaining else {
            return nil
        }

        let container = UIView()
        container.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.22)
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.70).cgColor

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = UIColor.systemOrange
        label.text = "Reconnect #\(attempt) in \(seconds)s"

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5)
        ])

        return container
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
    private func handleWindowChromePan(_ gesture: UIPanGestureRecognizer) {
        guard let chromeView = gesture.view as? WindowChromeView else {
            return
        }

        if chromeView.isWindowMaximized {
            if gesture.state == .began {
                Task {
                    await AppEnvironment.phaseZero.toggleWindowMaximized(chromeView.windowID)
                    await AppEnvironment.phaseZero.focusWindow(chromeView.windowID)
                }
            }
            return
        }

        guard canvasView.bounds.width > 1, canvasView.bounds.height > 1 else {
            return
        }

        switch gesture.state {
        case .began:
            Task {
                await AppEnvironment.phaseZero.focusWindow(chromeView.windowID)
            }
        case .changed:
            let translation = gesture.translation(in: canvasView)
            let deltaX = Double(translation.x / canvasView.bounds.width)
            let deltaY = Double(translation.y / canvasView.bounds.height)
            let frame = chromeView.windowFrame
            let nextFrame = PhaseZeroRect(
                x: frame.x + deltaX,
                y: frame.y + deltaY,
                width: frame.width,
                height: frame.height
            )

            Task {
                await AppEnvironment.phaseZero.updateWindowFrame(chromeView.windowID, frame: nextFrame)
            }
        default:
            break
        }
    }

    @objc
    private func handleWindowChromeDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .recognized,
              let chromeView = gesture.view as? WindowChromeView else {
            return
        }

        Task {
            await AppEnvironment.phaseZero.toggleWindowMaximized(chromeView.windowID)
            await AppEnvironment.phaseZero.focusWindow(chromeView.windowID)
        }
    }

    @objc
    private func handleWindowResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let resizeHandle = gesture.view as? WindowResizeHandleView else {
            return
        }

        guard canvasView.bounds.width > 1, canvasView.bounds.height > 1 else {
            return
        }

        switch gesture.state {
        case .began:
            if resizeHandle.isWindowMaximized {
                Task {
                    await AppEnvironment.phaseZero.registerControlInput("Resize skipped: restore window first")
                }
                return
            }

            resizeHandle.initialFrame = resizeHandle.windowFrame
            Task {
                await AppEnvironment.phaseZero.focusWindow(resizeHandle.windowID)
            }
        case .changed:
            guard let initialFrame = resizeHandle.initialFrame else {
                return
            }

            let translation = gesture.translation(in: canvasView)
            let deltaWidth = Double(translation.x / canvasView.bounds.width)
            let deltaHeight = Double(translation.y / canvasView.bounds.height)
            let nextFrame = PhaseZeroRect(
                x: initialFrame.x,
                y: initialFrame.y,
                width: initialFrame.width + deltaWidth,
                height: initialFrame.height + deltaHeight
            )

            Task {
                await AppEnvironment.phaseZero.updateWindowFrame(resizeHandle.windowID, frame: nextFrame)
            }
        case .ended:
            resizeHandle.initialFrame = nil
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Window resized")
            }
        case .cancelled, .failed:
            resizeHandle.initialFrame = nil
        default:
            break
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

private final class WindowChromeView: UIView {
    var windowID: PhaseZeroWindowID = PhaseZeroWindowID()
    var windowFrame: PhaseZeroRect = .defaultWindow
    var isWindowMaximized: Bool = false
}

private final class WindowResizeHandleView: UIView {
    var windowID: PhaseZeroWindowID = PhaseZeroWindowID()
    var windowFrame: PhaseZeroRect = .defaultWindow
    var isWindowMaximized: Bool = false
    var initialFrame: PhaseZeroRect?
}

private struct BrowserNavigationSnapshot {
    let urlString: String?
    let title: String?
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

private enum BrowserNavigationEvent {
    case stateChanged(BrowserNavigationSnapshot)
    case failed(String)
    case blocked(urlString: String?, reason: String)
}

private final class BrowserNavigationDelegateProxy: NSObject, WKNavigationDelegate {
    private let onEvent: (BrowserNavigationEvent) -> Void

    init(onEvent: @escaping (BrowserNavigationEvent) -> Void) {
        self.onEvent = onEvent
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onEvent(.stateChanged(snapshot(from: webView)))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        onEvent(.stateChanged(snapshot(from: webView)))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onEvent(.stateChanged(snapshot(from: webView)))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            onEvent(.blocked(urlString: nil, reason: "Missing URL"))
            return
        }

        guard Self.isAllowed(url: url) else {
            decisionHandler(.cancel)
            onEvent(
                .blocked(
                    urlString: url.absoluteString,
                    reason: "Scheme \(url.scheme?.lowercased() ?? "unknown") is not allowed"
                )
            )
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onEvent(.failed(error.localizedDescription))
        onEvent(.stateChanged(snapshot(from: webView)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onEvent(.failed(error.localizedDescription))
        onEvent(.stateChanged(snapshot(from: webView)))
    }

    private func snapshot(from webView: WKWebView) -> BrowserNavigationSnapshot {
        BrowserNavigationSnapshot(
            urlString: webView.url?.absoluteString,
            title: webView.title,
            isLoading: webView.isLoading,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    private static func isAllowed(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }
}
