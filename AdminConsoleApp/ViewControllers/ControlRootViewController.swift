import AppPlatform
import UIKit
import WebKit

final class ControlRootViewController: UIViewController, UITextFieldDelegate {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private let focusedLabel = UILabel()
    private let cursorLabel = UILabel()
    private let inputLabel = UILabel()
    private let terminalStatusLabel = UILabel()
    private let terminalPreviewLabel = UILabel()
    private let trackpadView = UIView()
    private let trackpadCursor = UIView()
    private let keyboardHintLabel = UILabel()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let commandField = UITextField()
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

        summaryLabel.text = "iPhone control scene for cursor, focus, shortcuts, terminal orchestration, and SSH input."
        summaryLabel.font = .preferredFont(forTextStyle: .title3)
        summaryLabel.numberOfLines = 0

        [statusLabel, focusedLabel, cursorLabel, inputLabel, terminalStatusLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .body)
            label.numberOfLines = 0
        }

        terminalPreviewLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalPreviewLabel.textColor = .secondaryLabel
        terminalPreviewLabel.numberOfLines = 0
        terminalPreviewLabel.text = "No terminal output yet."

        keyboardHintLabel.text = """
        Keyboard prototype
        Cmd+1 Terminal
        Cmd+2 Files
        Cmd+3 Browser
        Cmd+4 VNC
        Arrow keys move cursor unless terminal focus is active
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

        let infoCard = makeCard(
            arrangedSubviews: [
                summaryLabel,
                statusLabel,
                focusedLabel,
                cursorLabel,
                inputLabel,
                terminalStatusLabel,
                terminalPreviewLabel
            ]
        )
        let trackpadCard = makeCard(arrangedSubviews: [trackpadView, keyboardHintLabel])
        let actionsCard = makeCard(arrangedSubviews: [makeButtonsRow()])
        let sshCard = makeCard(arrangedSubviews: [makeSSHControls()])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18

        [infoCard, trackpadCard, actionsCard, sshCard].forEach(stackView.addArrangedSubview)
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

            trackpadView.heightAnchor.constraint(equalToConstant: 220)
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
        var commands = [
            makeKeyCommand("1", modifiers: .command, action: #selector(openTerminal), title: "Open Terminal"),
            makeKeyCommand("2", modifiers: .command, action: #selector(openFiles), title: "Open Files"),
            makeKeyCommand("3", modifiers: .command, action: #selector(openBrowserWindow), title: "Open Browser"),
            makeKeyCommand("4", modifiers: .command, action: #selector(openVNC), title: "Open VNC")
        ]

        if !routesHardwareKeyboardToTerminal {
            commands.append(makeKeyCommand(UIKeyCommand.inputUpArrow, action: #selector(moveCursorUp), title: "Move Cursor Up"))
            commands.append(makeKeyCommand(UIKeyCommand.inputDownArrow, action: #selector(moveCursorDown), title: "Move Cursor Down"))
            commands.append(makeKeyCommand(UIKeyCommand.inputLeftArrow, action: #selector(moveCursorLeft), title: "Move Cursor Left"))
            commands.append(makeKeyCommand(UIKeyCommand.inputRightArrow, action: #selector(moveCursorRight), title: "Move Cursor Right"))
        }

        return commands
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.compactMap(\.key).first {
            if routesHardwareKeyboardToTerminal,
               let terminalInput = terminalInput(for: key) {
                Task {
                    await AppEnvironment.phaseZero.sendInputToFocusedTerminal(terminalInput)
                }
                return
            }

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
        terminalStatusLabel.text = terminalStatusText(snapshot: snapshot)
        terminalPreviewLabel.text = terminalPreview(snapshot: snapshot)

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

    private func makeSSHControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.text = "SSH Terminal"

        configureField(hostField, placeholder: "Host", textContentType: .URL)
        configureField(portField, placeholder: "Port", keyboardType: .numberPad)
        portField.text = "22"
        configureField(usernameField, placeholder: "Username", textContentType: .username)
        configureField(passwordField, placeholder: "Password (optional if saved)", textContentType: .password)
        passwordField.isSecureTextEntry = true
        configureField(commandField, placeholder: "Command to send to focused terminal")
        commandField.returnKeyType = .send

        let connectButton = UIButton(type: .system)
        connectButton.configuration = .filled()
        connectButton.configuration?.title = "Connect Focused Terminal"
        connectButton.addTarget(self, action: #selector(connectSSH), for: .touchUpInside)

        let sendButton = UIButton(type: .system)
        sendButton.configuration = .tinted()
        sendButton.configuration?.title = "Send Command"
        sendButton.addTarget(self, action: #selector(sendCommandToTerminal), for: .touchUpInside)

        [
            titleLabel,
            hostField,
            portField,
            usernameField,
            passwordField,
            connectButton,
            commandField,
            sendButton
        ].forEach(stack.addArrangedSubview)

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
    private func connectSSH() {
        view.endEditing(true)

        guard let request = makeSSHRequest() else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("SSH connect skipped: invalid form")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.connectFocusedTerminal(using: request)
        }
    }

    @objc
    private func sendCommandToTerminal() {
        guard let text = commandField.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let command = text.hasSuffix("\n") ? text : text + "\n"
        commandField.text = nil

        Task {
            await AppEnvironment.phaseZero.sendInputToFocusedTerminal(command)
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

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case commandField:
            sendCommandToTerminal()
        case passwordField:
            connectSSH()
        default:
            textField.resignFirstResponder()
        }

        return true
    }

    private var routesHardwareKeyboardToTerminal: Bool {
        guard let terminalWindow = focusedTerminalWindow(snapshot: latestSnapshot),
              let terminalState = terminalWindow.terminalState else {
            return false
        }

        return terminalState.sessionState == .connected
    }

    private func configureField(
        _ textField: UITextField,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil
    ) {
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.returnKeyType = .done
        textField.textContentType = textContentType
    }

    private func makeSSHRequest() -> PhaseZeroSSHConnectionRequest? {
        let host = hostField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        let port = Int(portField.text ?? "") ?? 22

        guard !host.isEmpty, !username.isEmpty else {
            return nil
        }

        let profile = latestSnapshot?.displayProfile
        let width = Int((profile?.width ?? 1440) * (profile?.scale ?? 1.0))
        let height = Int((profile?.height ?? 900) * (profile?.scale ?? 1.0))
        let columns = max(80, Int((profile?.width ?? 1440) / 10))
        let rows = max(24, Int((profile?.height ?? 900) / 22))

        return PhaseZeroSSHConnectionRequest(
            host: host,
            port: port,
            username: username,
            password: password,
            columns: columns,
            rows: rows,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private func focusedTerminalWindow(snapshot: PhaseZeroSnapshot?) -> PhaseZeroWindow? {
        guard let snapshot else {
            return nil
        }

        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID && $0.kind == .terminal }) {
            return focusedWindow
        }

        return snapshot.windows.last(where: { $0.kind == .terminal })
    }

    private func terminalStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let terminalWindow = focusedTerminalWindow(snapshot: snapshot),
              let terminalState = terminalWindow.terminalState else {
            return "Terminal: no terminal window selected"
        }

        return """
        Terminal: \(terminalState.connectionTitle)
        State: \(terminalState.sessionState.rawValue.capitalized)
        Status: \(terminalState.statusMessage)
        Grid: \(terminalState.columns) x \(terminalState.rows)
        """
    }

    private func terminalPreview(snapshot: PhaseZeroSnapshot) -> String {
        guard let terminalState = focusedTerminalWindow(snapshot: snapshot)?.terminalState else {
            return "No terminal output yet."
        }

        let lines = terminalState.transcript.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(10).joined(separator: "\n")
    }

    private func terminalInput(for key: UIKey) -> String? {
        if key.modifierFlags.contains(.command) {
            return nil
        }

        switch key.keyCode {
        case .keyboardReturnOrEnter:
            return "\n"
        case .keyboardDeleteOrBackspace:
            return "\u{7F}"
        case .keyboardTab:
            return "\t"
        case .keyboardUpArrow:
            return "\u{001B}[A"
        case .keyboardDownArrow:
            return "\u{001B}[B"
        case .keyboardRightArrow:
            return "\u{001B}[C"
        case .keyboardLeftArrow:
            return "\u{001B}[D"
        default:
            return key.characters.isEmpty ? nil : key.characters
        }
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
