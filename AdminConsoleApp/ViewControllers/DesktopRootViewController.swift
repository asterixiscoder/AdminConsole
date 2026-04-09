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
            let panel = makeWindowPlaceholder(window: window, snapshot: snapshot)
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

    private func makeWindowPlaceholder(window: PhaseZeroWindow, snapshot: PhaseZeroSnapshot) -> UIView {
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

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = window.title
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)

        let detailLabel = UILabel()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.text = window.id.rawValue.uuidString.prefix(8) + " • " + snapshot.lastInputDescription
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.66)
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.numberOfLines = 2

        panel.addSubview(chrome)
        chrome.addSubview(label)
        panel.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: panel.topAnchor),
            chrome.heightAnchor.constraint(equalToConstant: 44),

            label.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            detailLabel.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 16)
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
}
