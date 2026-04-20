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
        window.backgroundColor = .black
        window.rootViewController = RebootExternalMirrorViewController(model: AppEnvironment.rebootModel)
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppEnvironment.rebootModel.clearExternalMirrorTerminalOverride()
    }
}

@MainActor
private final class RebootExternalMirrorViewController: UIViewController {
    private let model: RebootAppModel
    private let outputView = UITextView()
    private var terminalObserverID: UUID?
    private var lastAppliedTerminalSize: TerminalSize?

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
        outputView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 4)
        outputView.textContainer.lineFragmentPadding = 0
        outputView.textContainer.lineBreakMode = .byCharWrapping
        outputView.translatesAutoresizingMaskIntoConstraints = false

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
        applyTerminalGeometryIfNeeded()
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
        outputView.text = state.transcript.isEmpty ? state.statusMessage : state.transcript
        applyTerminalGeometryIfNeeded()

        let maxOffsetY = max(
            -outputView.adjustedContentInset.top,
            outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
        )
        outputView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
    }

    private func applyTerminalGeometryIfNeeded() {
        guard outputView.bounds.width > 200, outputView.bounds.height > 160 else {
            return
        }

        let font = outputView.font ?? .monospacedSystemFont(ofSize: 16, weight: .regular)
        let insets = outputView.textContainerInset
        let linePadding = outputView.textContainer.lineFragmentPadding * 2
        let usableWidth = max(0, outputView.bounds.width - insets.left - insets.right - linePadding)
        let usableHeight = max(0, outputView.bounds.height - insets.top - insets.bottom)
        // Slightly bias toward wider usable cols: UIKit text metrics tend to
        // overestimate mono glyph advance for terminal PTY sizing.
        let glyphWidth = max(3.5, measuredMonospaceGlyphWidth(for: font) * 0.82)
        let rowHeight = max(10.0, font.lineHeight)

        let columns = Int(floor(usableWidth / glyphWidth)) + 1
        let rows = Int(floor(usableHeight / rowHeight))
        let screenScale = view.window?.screen.scale ?? UIScreen.main.scale
        let terminalSize = TerminalSize(
            columns: max(80, min(320, columns)),
            rows: max(24, rows),
            pixelWidth: Int(outputView.bounds.width * screenScale),
            pixelHeight: Int(outputView.bounds.height * screenScale)
        )

        guard terminalSize != lastAppliedTerminalSize else {
            return
        }
        lastAppliedTerminalSize = terminalSize
        model.resizeTerminalFromExternalMirror(
            columns: terminalSize.columns,
            rows: terminalSize.rows,
            pixelWidth: terminalSize.pixelWidth,
            pixelHeight: terminalSize.pixelHeight
        )
    }

    private func measuredMonospaceGlyphWidth(for font: UIFont) -> CGFloat {
        let sampleCount = 64
        let sample = String(repeating: "M", count: sampleCount)
        let sampleWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        let perGlyph = sampleWidth / CGFloat(sampleCount)
        return perGlyph.isFinite ? perGlyph : 8.0
    }
}
