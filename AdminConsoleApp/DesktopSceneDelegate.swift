import UIKit
import DesktopDomain

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
}

@MainActor
private final class RebootExternalMirrorViewController: UIViewController {
    private let model: RebootAppModel
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let outputView = UITextView()
    private var terminalObserverID: UUID?
    private var isFirstRender = true

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

        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        titleLabel.textColor = UIColor(red: 0.86, green: 0.89, blue: 0.95, alpha: 1)
        titleLabel.text = "Terminal Mirror"
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = UIColor(red: 0.55, green: 0.67, blue: 0.84, alpha: 1)
        statusLabel.numberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1)
        outputView.textColor = UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1)
        outputView.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        outputView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        outputView.textContainer.lineFragmentPadding = 0
        outputView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(statusLabel)
        view.addSubview(outputView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            outputView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            outputView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            outputView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14),
            outputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let terminalObserverID {
            model.removeTerminalObserver(id: terminalObserverID)
            self.terminalObserverID = nil
        }
    }

    private func render(_ state: TerminalSurfaceState) {
        let title = state.connectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title.isEmpty ? "Terminal Mirror" : title
        statusLabel.text = state.statusMessage

        outputView.text = state.transcript.isEmpty ? state.statusMessage : state.transcript

        if isFirstRender {
            outputView.setContentOffset(.zero, animated: false)
            isFirstRender = false
        } else {
            let maxOffsetY = max(
                -outputView.adjustedContentInset.top,
                outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
            )
            outputView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
        }
    }
}
