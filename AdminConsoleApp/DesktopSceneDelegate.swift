import UIKit
import DesktopDomain
import SSHKit

final class DesktopSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        SceneWindowConfiguration.apply(
            to: window,
            backgroundColor: .black,
            rootViewController: RebootExternalMirrorViewController(model: AppEnvironment.rebootModel)
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppEnvironment.rebootModel.clearExternalMirrorTerminalOverride()
    }
}

@MainActor
private final class RebootExternalMirrorViewController: UIViewController, UITextViewDelegate {
    private struct ViewportState {
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        var isUserPanning = false
        var stickToBottom = false
        var stickToRight = false
    }

    private let model: RebootAppModel
    private let outputView = UITextView()
    private var terminalObserverID: UUID?
    private var latestState: TerminalSurfaceState?
    private var cachedFontForGeometry: (columns: Int, rows: Int, size: CGFloat)?
    private var lastAppliedTerminalSize: TerminalSize?
    private var viewportState = ViewportState()
    private var lastRenderedAlternateScreen = false
    private let externalMinFontSize: CGFloat = 10
    private let externalMaxFontSize: CGFloat = 24

    init(model: RebootAppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.backgroundColor = .black
        outputView.textColor = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        outputView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        outputView.textContainerInset = .zero
        outputView.textContainer.lineFragmentPadding = 0
        outputView.textContainer.lineBreakMode = .byClipping
        outputView.textContainer.widthTracksTextView = false
        outputView.alwaysBounceHorizontal = true
        outputView.showsHorizontalScrollIndicator = true
        outputView.translatesAutoresizingMaskIntoConstraints = false
        outputView.delegate = self

        view.addSubview(outputView)

        NSLayoutConstraint.activate([
            outputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outputView.topAnchor.constraint(equalTo: view.topAnchor),
            outputView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if terminalObserverID == nil {
            terminalObserverID = model.addTerminalObserver { [weak self] state in
                self?.render(state)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cachedFontForGeometry = nil
        applyExternalMirrorGeometryIfNeeded()
        if let latestState {
            render(latestState)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let terminalObserverID {
            model.removeTerminalObserver(id: terminalObserverID)
            self.terminalObserverID = nil
        }
        model.clearExternalMirrorTerminalOverride()
    }

    private func render(_ state: TerminalSurfaceState) {
        latestState = state
        updateFontForExternalSurface(with: state)
        updateTextContainerWidth(for: state)
        let isAlternateScreen = state.buffer.isAlternateScreenActive
        let didEnterAlternateScreen = isAlternateScreen && !lastRenderedAlternateScreen
        lastRenderedAlternateScreen = isAlternateScreen
        if isAlternateScreen {
            if didEnterAlternateScreen {
                resetAlternateViewportForNewCanvas()
            }
            let previousOffset = outputView.contentOffset
            let hadHorizontalOverflowBeforeRender = didEnterAlternateScreen ? false : hasHorizontalOverflow(outputView)
            let hadVerticalOverflowBeforeRender = didEnterAlternateScreen ? false : hasVerticalOverflow(outputView)
            let wasNearRightBeforeRender = didEnterAlternateScreen ? false : isNearRight(outputView)
            let wasNearBottomBeforeRender = didEnterAlternateScreen ? false : isNearBottom(outputView)
            let styledLines = state.buffer.renderedStyledLines(
                insertingCursor: state.sessionState == .connected,
                forceCursor: true
            )
            outputView.attributedText = attributedTerminalText(
                from: styledLines,
                fallback: state.transcript.isEmpty ? state.statusMessage : state.transcript
            )
            outputView.layoutIfNeeded()
            restoreAlternateViewportAfterRender(
                previousOffset: previousOffset,
                forceTopLeft: didEnterAlternateScreen,
                hadHorizontalOverflowBeforeRender: hadHorizontalOverflowBeforeRender,
                hadVerticalOverflowBeforeRender: hadVerticalOverflowBeforeRender,
                wasNearRightBeforeRender: wasNearRightBeforeRender,
                wasNearBottomBeforeRender: wasNearBottomBeforeRender
            )
        } else {
            lastRenderedAlternateScreen = false
            outputView.text = renderableTerminalText(for: state)
            let maxOffsetY = max(
                -outputView.adjustedContentInset.top,
                outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
            )
            outputView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
        }
    }

    private func resetAlternateViewportForNewCanvas() {
        viewportState = ViewportState()
        let origin = CGPoint(
            x: -outputView.adjustedContentInset.left,
            y: -outputView.adjustedContentInset.top
        )
        outputView.setContentOffset(origin, animated: false)
    }

    private func renderableTerminalText(for state: TerminalSurfaceState) -> String {
        let includeCursor = state.sessionState == .connected
        let viewportLines = state.buffer.renderedViewportLinesPreservingColumns(insertingCursor: includeCursor)
        guard !viewportLines.isEmpty else {
            return state.transcript.isEmpty ? state.statusMessage : state.transcript
        }
        return viewportLines.joined(separator: "\n")
    }

    private func attributedTerminalText(from lines: [TerminalStyledLine], fallback: String) -> NSAttributedString {
        let font = outputView.font ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
        let defaultForeground = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        let defaultBackground = UIColor.black
        let noWrapParagraphStyle: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byClipping
            style.lineSpacing = 0
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            return style
        }()

        guard !lines.isEmpty else {
            return NSAttributedString(
                string: fallback,
                attributes: [
                    .font: font,
                    .foregroundColor: defaultForeground,
                    .paragraphStyle: noWrapParagraphStyle
                ]
            )
        }

        let rendered = NSMutableAttributedString()
        for (lineIndex, line) in lines.enumerated() {
            var lineBackground: UIColor = defaultBackground
            for cell in line.cells {
                let colors = resolvedCellColors(cell.style, defaultForeground: defaultForeground, defaultBackground: defaultBackground)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: colors.foreground,
                    .backgroundColor: colors.background,
                    .paragraphStyle: noWrapParagraphStyle
                ]
                lineBackground = colors.background
                if cell.style.isUnderlined {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                rendered.append(NSAttributedString(string: cell.character, attributes: attrs))
            }
            if lineIndex < lines.count - 1 {
                rendered.append(NSAttributedString(
                    string: "\n",
                    attributes: [
                        .font: font,
                        .foregroundColor: defaultForeground,
                        .backgroundColor: lineBackground,
                        .paragraphStyle: noWrapParagraphStyle
                    ]
                ))
            }
        }
        return rendered
    }

    private func resolvedCellColors(
        _ style: TerminalTextStyle,
        defaultForeground: UIColor,
        defaultBackground: UIColor
    ) -> (foreground: UIColor, background: UIColor) {
        let fg = resolvedColor(style.foreground, defaultColor: defaultForeground)
        let bg = resolvedColor(style.background, defaultColor: defaultBackground)
        if style.isInverse {
            return (foreground: bg, background: fg)
        }
        return (foreground: fg, background: bg)
    }

    private func resolvedColor(_ color: TerminalColor, defaultColor: UIColor) -> UIColor {
        switch color {
        case .default:
            return defaultColor
        case .rgb(let red, let green, let blue):
            return UIColor(
                red: CGFloat(max(0, min(255, red))) / 255,
                green: CGFloat(max(0, min(255, green))) / 255,
                blue: CGFloat(max(0, min(255, blue))) / 255,
                alpha: 1
            )
        case .ansi256(let code):
            return ansi256Color(code)
        }
    }

    private func ansi256Color(_ code: Int) -> UIColor {
        let normalized = max(0, min(255, code))
        if normalized < 16 {
            let palette: [UIColor] = [
                UIColor.black, UIColor(red: 0.80, green: 0.25, blue: 0.26, alpha: 1),
                UIColor(red: 0.34, green: 0.70, blue: 0.42, alpha: 1), UIColor(red: 0.90, green: 0.70, blue: 0.30, alpha: 1),
                UIColor(red: 0.36, green: 0.58, blue: 0.94, alpha: 1), UIColor(red: 0.73, green: 0.45, blue: 0.86, alpha: 1),
                UIColor(red: 0.33, green: 0.75, blue: 0.78, alpha: 1), UIColor(red: 0.80, green: 0.82, blue: 0.84, alpha: 1),
                UIColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 1), UIColor(red: 0.94, green: 0.45, blue: 0.46, alpha: 1),
                UIColor(red: 0.49, green: 0.83, blue: 0.56, alpha: 1), UIColor(red: 0.98, green: 0.80, blue: 0.44, alpha: 1),
                UIColor(red: 0.49, green: 0.69, blue: 0.98, alpha: 1), UIColor(red: 0.84, green: 0.61, blue: 0.95, alpha: 1),
                UIColor(red: 0.50, green: 0.88, blue: 0.90, alpha: 1), UIColor.white
            ]
            return palette[normalized]
        }

        if normalized < 232 {
            let v = normalized - 16
            let r = v / 36
            let g = (v / 6) % 6
            let b = v % 6
            func channel(_ value: Int) -> CGFloat {
                value == 0 ? 0 : CGFloat(55 + value * 40) / 255
            }
            return UIColor(red: channel(r), green: channel(g), blue: channel(b), alpha: 1)
        }

        let gray = CGFloat(8 + (normalized - 232) * 10) / 255
        return UIColor(white: gray, alpha: 1)
    }

    private func updateFontForExternalSurface(with state: TerminalSurfaceState) {
        let columns = max(20, state.buffer.columns)
        let rows = max(6, state.buffer.rows)
        let insets = outputView.textContainerInset
        let usableWidth = max(1, outputView.bounds.width - insets.left - insets.right)
        let usableHeight = max(1, outputView.bounds.height - insets.top - insets.bottom)
        let fixedPointSize = fittingMonospaceFontSize(
            columns: columns,
            rows: rows,
            usableWidth: usableWidth,
            usableHeight: usableHeight,
            minSize: externalMinFontSize,
            maxSize: externalMaxFontSize
        )
        if let cached = cachedFontForGeometry,
           cached.columns == columns,
           cached.rows == rows,
           abs(cached.size - fixedPointSize) < 0.01 {
            return
        }

        outputView.font = .monospacedSystemFont(ofSize: fixedPointSize, weight: .regular)
        cachedFontForGeometry = (columns: columns, rows: rows, size: fixedPointSize)
    }

    private func fittingMonospaceFontSize(
        columns: Int,
        rows: Int,
        usableWidth: CGFloat,
        usableHeight: CGFloat,
        minSize: CGFloat,
        maxSize: CGFloat
    ) -> CGFloat {
        var size = maxSize
        while size >= minSize {
            let metrics = monospaceMetrics(for: size)
            let requiredWidth = metrics.glyphWidth * CGFloat(columns)
            let requiredHeight = metrics.lineHeight * CGFloat(rows)
            if requiredWidth <= usableWidth && requiredHeight <= usableHeight {
                return size
            }
            size -= 0.5
        }
        return minSize
    }

    private func monospaceMetrics(for pointSize: CGFloat) -> (glyphWidth: CGFloat, lineHeight: CGFloat) {
        let font = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let sampleCount = 64
        let sample = String(repeating: "M", count: sampleCount)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        let glyphWidth = max(1, sampleWidth / CGFloat(sampleCount))
        let lineHeight = max(1, font.lineHeight)
        return (glyphWidth, lineHeight)
    }

    private func updateTextContainerWidth(for state: TerminalSurfaceState) {
        let font = outputView.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let sampleCount = 64
        let sample = String(repeating: "M", count: sampleCount)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        let glyphWidth = max(4.0, sampleWidth / CGFloat(sampleCount))
        let insets = outputView.textContainerInset
        let targetWidth = max(
            outputView.bounds.width - insets.left - insets.right,
            CGFloat(state.buffer.columns) * glyphWidth
        )
        outputView.textContainer.size = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
    }

    private func applyExternalMirrorGeometryIfNeeded() {
        let fallbackPixelWidth = 1920
        let fallbackPixelHeight = 1080

        let sceneScreen = view.window?.windowScene?.screen
        let sceneBounds = sceneScreen?.bounds ?? .zero
        let sceneScale = sceneScreen?.scale ?? UIScreen.main.scale

        let resolvedBounds: CGRect
        let resolvedScale: CGFloat
        if outputView.bounds.width > 200, outputView.bounds.height > 120 {
            resolvedBounds = outputView.bounds
            resolvedScale = sceneScale
        } else if sceneBounds.width > 200, sceneBounds.height > 120 {
            resolvedBounds = sceneBounds
            resolvedScale = sceneScale
        } else {
            resolvedBounds = CGRect(x: 0, y: 0, width: CGFloat(fallbackPixelWidth), height: CGFloat(fallbackPixelHeight))
            resolvedScale = 1
        }

        let profile = TerminalRenderProfileResolver.externalProfile(
            from: (resolvedBounds.width > 0 && resolvedBounds.height > 0)
                ? TerminalRenderProfileResolver.SurfaceBounds(
                    widthPoints: Double(resolvedBounds.width),
                    heightPoints: Double(resolvedBounds.height),
                    scale: Double(resolvedScale)
                )
                : nil,
            isAlternateScreen: latestState?.buffer.isAlternateScreenActive ?? false
        )
        let terminalSize = TerminalSize(
            columns: profile.columns,
            rows: profile.rows,
            pixelWidth: profile.pixelWidth,
            pixelHeight: profile.pixelHeight
        )

        guard terminalSize != lastAppliedTerminalSize else { return }
        lastAppliedTerminalSize = terminalSize
        model.resizeTerminalFromExternalMirror(
            columns: terminalSize.columns,
            rows: terminalSize.rows,
            pixelWidth: terminalSize.pixelWidth,
            pixelHeight: terminalSize.pixelHeight
        )
    }

    private func restoreAlternateViewportAfterRender(
        previousOffset: CGPoint,
        forceTopLeft: Bool,
        hadHorizontalOverflowBeforeRender: Bool,
        hadVerticalOverflowBeforeRender: Bool,
        wasNearRightBeforeRender: Bool,
        wasNearBottomBeforeRender: Bool
    ) {
        let minX = -outputView.adjustedContentInset.left
        let minY = -outputView.adjustedContentInset.top
        let maxX = max(
            minX,
            outputView.contentSize.width - outputView.bounds.width + outputView.adjustedContentInset.right
        )
        let maxY = max(
            minY,
            outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
        )

        var targetX = min(max(previousOffset.x, minX), maxX)
        var targetY = min(max(previousOffset.y, minY), maxY)

        if forceTopLeft {
            targetX = minX
            targetY = minY
        } else if !viewportState.isUserPanning {
            if viewportState.stickToRight || (hadHorizontalOverflowBeforeRender && wasNearRightBeforeRender) {
                targetX = maxX
            }
            if viewportState.stickToBottom || (hadVerticalOverflowBeforeRender && wasNearBottomBeforeRender) {
                targetY = maxY
            }
        }

        let target = CGPoint(x: targetX, y: targetY)
        outputView.setContentOffset(target, animated: false)

        viewportState.offsetX = targetX
        viewportState.offsetY = targetY
        viewportState.stickToRight = hasHorizontalOverflow(outputView) && targetX >= (maxX - 16)
        viewportState.stickToBottom = hasVerticalOverflow(outputView) && targetY >= (maxY - 16)
    }

    private func hasHorizontalOverflow(_ scrollView: UIScrollView, threshold: CGFloat = 1) -> Bool {
        scrollView.contentSize.width + scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right >
            scrollView.bounds.width + threshold
    }

    private func hasVerticalOverflow(_ scrollView: UIScrollView, threshold: CGFloat = 1) -> Bool {
        scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom >
            scrollView.bounds.height + threshold
    }

    private func isNearBottom(_ scrollView: UIScrollView, threshold: CGFloat = 16) -> Bool {
        guard hasVerticalOverflow(scrollView, threshold: threshold) else {
            return false
        }
        let maxOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        return scrollView.contentOffset.y >= (maxOffsetY - threshold)
    }

    private func isNearRight(_ scrollView: UIScrollView, threshold: CGFloat = 16) -> Bool {
        guard hasHorizontalOverflow(scrollView, threshold: threshold) else {
            return false
        }
        let maxOffsetX = max(
            -scrollView.adjustedContentInset.left,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        return scrollView.contentOffset.x >= (maxOffsetX - threshold)
    }
}

extension RebootExternalMirrorViewController {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        viewportState.isUserPanning = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        viewportState.offsetX = scrollView.contentOffset.x
        viewportState.offsetY = scrollView.contentOffset.y
        viewportState.stickToRight = isNearRight(scrollView)
        viewportState.stickToBottom = isNearBottom(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === outputView, !decelerate else { return }
        viewportState.isUserPanning = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        viewportState.isUserPanning = false
    }
}
