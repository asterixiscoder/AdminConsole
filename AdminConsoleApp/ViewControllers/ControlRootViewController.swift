import AppPlatform
import UIKit
import WebKit

final class ControlRootViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private let focusedLabel = UILabel()
    private let cursorLabel = UILabel()
    private let inputLabel = UILabel()
    private let trackpadView = UIView()
    private let trackpadCursor = UIView()
    private let keyboardHintLabel = UILabel()
    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "AdminConsole"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Browser Spike",
            style: .plain,
            target: self,
            action: #selector(openBrowserPrototype)
        )

        summaryLabel.text = "iPhone control scene for cursor, focus, shortcuts, and window orchestration."
        summaryLabel.font = .preferredFont(forTextStyle: .title3)
        summaryLabel.numberOfLines = 0

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0

        focusedLabel.font = .preferredFont(forTextStyle: .body)
        focusedLabel.numberOfLines = 0

        cursorLabel.font = .preferredFont(forTextStyle: .body)
        cursorLabel.numberOfLines = 0

        inputLabel.font = .preferredFont(forTextStyle: .body)
        inputLabel.numberOfLines = 0

        keyboardHintLabel.text = """
        Keyboard prototype
        Cmd+1 Terminal
        Cmd+2 Files
        Cmd+3 Browser
        Cmd+4 VNC
        Arrow keys move cursor
        """
        keyboardHintLabel.font = .preferredFont(forTextStyle: .footnote)
        keyboardHintLabel.numberOfLines = 0

        trackpadView.translatesAutoresizingMaskIntoConstraints = false
        trackpadView.backgroundColor = UIColor.secondarySystemBackground
        trackpadView.layer.cornerRadius = 22
        trackpadView.layer.borderWidth = 1
        trackpadView.layer.borderColor = UIColor.separator.cgColor

        trackpadCursor.translatesAutoresizingMaskIntoConstraints = false
        trackpadCursor.backgroundColor = .systemBlue
        trackpadCursor.layer.cornerRadius = 10
        trackpadCursor.layer.shadowColor = UIColor.systemBlue.cgColor
        trackpadCursor.layer.shadowOpacity = 0.3
        trackpadCursor.layer.shadowRadius = 8

        trackpadView.addSubview(trackpadCursor)

        let openButtons = makeButtonsRow()
        let infoCard = makeCard(arrangedSubviews: [summaryLabel, statusLabel, focusedLabel, cursorLabel, inputLabel])
        let trackpadCard = makeCard(arrangedSubviews: [trackpadView, keyboardHintLabel])
        let actionsCard = makeCard(arrangedSubviews: [openButtons])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18

        stackView.addArrangedSubview(infoCard)
        stackView.addArrangedSubview(trackpadCard)
        stackView.addArrangedSubview(actionsCard)
        scrollView.addSubview(stackView)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            trackpadView.heightAnchor.constraint(equalToConstant: 220),
        ])
        trackpadCursor.translatesAutoresizingMaskIntoConstraints = true
        trackpadCursor.frame = CGRect(x: 14, y: 14, width: 20, height: 20)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadPan(_:)))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTrackpadTap))
        trackpadView.addGestureRecognizer(panGesture)
        trackpadView.addGestureRecognizer(tapGesture)

        startUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let latestSnapshot else {
            return
        }

        applyTrackpadCursor(snapshot: latestSnapshot)
    }

    deinit {
        updatesTask?.cancel()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeKeyCommand("1", modifiers: .command, action: #selector(openTerminal), title: "Open Terminal"),
            makeKeyCommand("2", modifiers: .command, action: #selector(openFiles), title: "Open Files"),
            makeKeyCommand("3", modifiers: .command, action: #selector(openBrowserWindow), title: "Open Browser"),
            makeKeyCommand("4", modifiers: .command, action: #selector(openVNC), title: "Open VNC"),
            makeKeyCommand(UIKeyCommand.inputUpArrow, action: #selector(moveCursorUp), title: "Move Cursor Up"),
            makeKeyCommand(UIKeyCommand.inputDownArrow, action: #selector(moveCursorDown), title: "Move Cursor Down"),
            makeKeyCommand(UIKeyCommand.inputLeftArrow, action: #selector(moveCursorLeft), title: "Move Cursor Left"),
            makeKeyCommand(UIKeyCommand.inputRightArrow, action: #selector(moveCursorRight), title: "Move Cursor Right")
        ]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.compactMap(\.key).first {
            let keyName = key.charactersIgnoringModifiers.isEmpty ? key.characters : key.charactersIgnoringModifiers
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Key press: \(keyName)")
            }
        }

        super.pressesBegan(presses, with: event)
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
                    self.apply(snapshot: snapshot)
                }
            }
        }
    }

    private func apply(snapshot: PhaseZeroSnapshot) {
        statusLabel.text = """
        Revision: \(snapshot.revision)
        External display: \(snapshot.isExternalDisplayConnected ? "connected" : "disconnected")
        Resolution: \(Int(snapshot.displayProfile.width)) x \(Int(snapshot.displayProfile.height)) @ \(String(format: "%.1f", snapshot.displayProfile.scale))x
        """

        if let focusedID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedID }) {
            focusedLabel.text = "Focused window: \(focusedWindow.title)"
        } else {
            focusedLabel.text = "Focused window: none"
        }

        cursorLabel.text = "Cursor: x \(String(format: "%.2f", snapshot.cursor.x)), y \(String(format: "%.2f", snapshot.cursor.y))"
        inputLabel.text = "Last input: \(snapshot.lastInputDescription)"

        applyTrackpadCursor(snapshot: snapshot)
    }

    private func applyTrackpadCursor(snapshot: PhaseZeroSnapshot) {
        guard trackpadView.bounds.width > 0, trackpadView.bounds.height > 0 else {
            return
        }

        let x = snapshot.cursor.x * trackpadView.bounds.width
        let y = snapshot.cursor.y * trackpadView.bounds.height
        trackpadCursor.center = CGPoint(x: x, y: y)
    }

    private func makeCard(arrangedSubviews: [UIView]) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.secondarySystemBackground
        container.layer.cornerRadius = 20

        let stack = UIStackView(arrangedSubviews: arrangedSubviews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
        ])

        return container
    }

    private func makeButtonsRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let buttons: [(String, Selector)] = [
            ("Open Terminal Window", #selector(openTerminal)),
            ("Open Files Window", #selector(openFiles)),
            ("Open Browser Window", #selector(openBrowserWindow)),
            ("Open VNC Window", #selector(openVNC))
        ]

        for item in buttons {
            let button = UIButton(type: .system)
            button.configuration = .filled()
            button.configuration?.title = item.0
            button.addTarget(self, action: item.1, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        return stack
    }

    private func makeKeyCommand(
        _ input: String,
        modifiers: UIKeyModifierFlags = [],
        action: Selector,
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
        command.discoverabilityTitle = title
        return command
    }

    @objc
    private func handleTrackpadPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: trackpadView)
        let deltaX = Double(translation.x / max(trackpadView.bounds.width, 1)) * 0.6
        let deltaY = Double(translation.y / max(trackpadView.bounds.height, 1)) * 0.6

        gesture.setTranslation(.zero, in: trackpadView)

        Task {
            await AppEnvironment.phaseZero.moveCursor(deltaX: deltaX, deltaY: deltaY)
            await AppEnvironment.phaseZero.registerControlInput("Trackpad pan")
        }
    }

    @objc
    private func handleTrackpadTap() {
        Task {
            await AppEnvironment.phaseZero.registerControlInput("Trackpad tap")
        }
    }

    @objc
    private func openTerminal() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.terminal)
            await AppEnvironment.phaseZero.registerControlInput("Open terminal window")
        }
    }

    @objc
    private func openFiles() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.files)
            await AppEnvironment.phaseZero.registerControlInput("Open files window")
        }
    }

    @objc
    private func openBrowserWindow() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.browser)
            await AppEnvironment.phaseZero.registerControlInput("Open browser window")
        }
    }

    @objc
    private func openVNC() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.vnc)
            await AppEnvironment.phaseZero.registerControlInput("Open VNC window")
        }
    }

    @objc
    private func moveCursorUp() {
        moveCursor(deltaX: 0.0, deltaY: -0.03, description: "Keyboard cursor up")
    }

    @objc
    private func moveCursorDown() {
        moveCursor(deltaX: 0.0, deltaY: 0.03, description: "Keyboard cursor down")
    }

    @objc
    private func moveCursorLeft() {
        moveCursor(deltaX: -0.03, deltaY: 0.0, description: "Keyboard cursor left")
    }

    @objc
    private func moveCursorRight() {
        moveCursor(deltaX: 0.03, deltaY: 0.0, description: "Keyboard cursor right")
    }

    @objc
    private func openBrowserPrototype() {
        let viewController = BrowserPrototypeViewController()
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func moveCursor(deltaX: Double, deltaY: Double, description: String) {
        Task {
            await AppEnvironment.phaseZero.moveCursor(deltaX: deltaX, deltaY: deltaY)
            await AppEnvironment.phaseZero.registerControlInput(description)
        }
    }
}

private final class BrowserPrototypeViewController: UIViewController, UITextFieldDelegate, WKNavigationDelegate {
    private let addressField = UITextField()
    private let webView = WKWebView(frame: .zero)

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Browser Spike"
        view.backgroundColor = .systemBackground

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.borderStyle = .roundedRect
        addressField.placeholder = "https://developer.apple.com"
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.delegate = self
        addressField.returnKeyType = .go

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self

        view.addSubview(addressField)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            addressField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            addressField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 12),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        load(address: "https://developer.apple.com")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        load(address: textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        addressField.text = webView.url?.absoluteString
    }

    private func load(address: String) {
        let formattedAddress: String
        if address.hasPrefix("http://") || address.hasPrefix("https://") {
            formattedAddress = address
        } else {
            formattedAddress = "https://\(address)"
        }

        guard let url = URL(string: formattedAddress) else {
            return
        }

        addressField.text = formattedAddress
        webView.load(URLRequest(url: url))
    }
}
