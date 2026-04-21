import UIKit

@MainActor
final class SSHTerminalSessionViewController: UIViewController, UITextFieldDelegate {
    private struct PendingRun {
        let token: String
        let command: String
    }

    private let statusLabel = UILabel()
    private let transcriptView = UITextView()
    private let commandField = UITextField()
    private let runCommandField = UITextField()
    private let runResultLabel = UILabel()
    private let commandLogLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let sendLineButton = UIButton(type: .system)
    private let runCommandButton = UIButton(type: .system)
    private let pasteButton = UIButton(type: .system)
    private var shortcutButtons: [UIButton] = []
    private let themeManager = AdminThemeManager.shared

    private var commandLogEntries: [String] = []
    private var updatesTask: Task<Void, Never>?
    private var pendingRun: PendingRun?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "SSH Session"

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.numberOfLines = 0
        statusLabel.text = "Preparing terminal session..."

        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        transcriptView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        transcriptView.layer.cornerRadius = 12
        transcriptView.layer.borderWidth = 1
        transcriptView.isEditable = false
        transcriptView.isSelectable = true

        commandField.borderStyle = .roundedRect
        commandField.placeholder = "Terminal input"
        commandField.autocapitalizationType = .none
        commandField.autocorrectionType = .no
        commandField.returnKeyType = .send
        commandField.delegate = self

        runCommandField.borderStyle = .roundedRect
        runCommandField.placeholder = "Run command with result"
        runCommandField.autocapitalizationType = .none
        runCommandField.autocorrectionType = .no
        runCommandField.returnKeyType = .go
        runCommandField.delegate = self

        runResultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        runResultLabel.numberOfLines = 0
        runResultLabel.text = "Run command mode: idle."

        commandLogLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandLogLabel.numberOfLines = 0
        commandLogLabel.text = "No input sent yet."

        sendButton.configuration = .filled()
        sendButton.configuration?.title = "Send"
        sendButton.addTarget(self, action: #selector(sendRawInput), for: .touchUpInside)

        sendLineButton.configuration = .tinted()
        sendLineButton.configuration?.title = "Send + Enter"
        sendLineButton.addTarget(self, action: #selector(sendInputLine), for: .touchUpInside)

        let sendRow = UIStackView(arrangedSubviews: [sendButton, sendLineButton])
        sendRow.axis = .horizontal
        sendRow.spacing = 8
        sendRow.distribution = .fillEqually

        runCommandButton.configuration = .filled()
        runCommandButton.configuration?.title = "Run Command"
        runCommandButton.addTarget(self, action: #selector(executeScriptedCommand), for: .touchUpInside)

        let shortcutsRow = UIStackView(arrangedSubviews: [
            shortcutButton(title: "Esc", action: #selector(sendEscape)),
            shortcutButton(title: "Tab", action: #selector(sendTab)),
            shortcutButton(title: "Ctrl+C", action: #selector(sendCtrlC)),
            shortcutButton(title: "↑", action: #selector(sendArrowUp)),
            shortcutButton(title: "↓", action: #selector(sendArrowDown))
        ])
        shortcutsRow.axis = .horizontal
        shortcutsRow.spacing = 8
        shortcutsRow.distribution = .fillEqually
        shortcutButtons = shortcutsRow.arrangedSubviews.compactMap { $0 as? UIButton }

        pasteButton.configuration = .plain()
        pasteButton.configuration?.title = "Paste Clipboard"
        pasteButton.addTarget(self, action: #selector(pasteClipboard), for: .touchUpInside)

        let container = UIStackView(arrangedSubviews: [
            statusLabel,
            transcriptView,
            commandField,
            sendRow,
            runCommandField,
            runCommandButton,
            runResultLabel,
            shortcutsRow,
            pasteButton,
            commandLogLabel
        ])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 12

        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            transcriptView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])

        bindTheme()
        applyTheme()
        startUpdates()
    }

    deinit {
        updatesTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === runCommandField {
            executeScriptedCommand()
        } else {
            sendInputLine()
        }
        return true
    }

    private func startUpdates() {
        updatesTask = Task { [weak self] in
            guard let self else {
                return
            }

            await AppEnvironment.phaseZero.startIfNeeded()
            let current = await AppEnvironment.phaseZero.currentSnapshot()
            if !current.windows.contains(where: { $0.kind == .terminal }) {
                _ = await AppEnvironment.phaseZero.openWindow(.terminal)
            }
            await AppEnvironment.phaseZero.setActiveWorkMode(.ssh)

            let stream = await AppEnvironment.phaseZero.snapshots()
            for await snapshot in stream {
                await MainActor.run {
                    self.apply(snapshot: snapshot)
                }
            }
        }
    }

    private func apply(snapshot: PhaseZeroSnapshot) {
        guard let terminalState = terminalState(in: snapshot) else {
            statusLabel.text = "No SSH terminal window available."
            transcriptView.text = "Open SSH connection from the Connect form."
            return
        }

        statusLabel.text = """
        \(terminalState.connectionTitle)
        State: \(terminalState.sessionState.rawValue.capitalized)  Status: \(terminalState.statusMessage)
        """
        transcriptView.text = terminalState.transcript
        consumeRunResultIfPresent(in: terminalState.transcript)
        scrollTranscriptToBottom()
    }

    private func terminalState(in snapshot: PhaseZeroSnapshot) -> PhaseZeroTerminalState? {
        if let focusedID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.id == focusedID && $0.kind == .terminal })?.terminalState {
            return focused
        }

        return snapshot.windows.last(where: { $0.kind == .terminal })?.terminalState
    }

    private func shortcutButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .plain()
        button.configuration?.title = title
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func appendCommandLog(_ entry: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        commandLogEntries.append("\(stamp)  \(entry)")
        commandLogEntries = Array(commandLogEntries.suffix(6))
        commandLogLabel.text = commandLogEntries.joined(separator: "\n")
    }

    private func sendTerminalText(_ text: String, label: String) {
        Task {
            await AppEnvironment.phaseZero.sendInputToFocusedTerminal(text)
            await MainActor.run {
                self.appendCommandLog(label)
            }
        }
    }

    private func scrollTranscriptToBottom() {
        let length = transcriptView.text.utf16.count
        guard length > 0 else {
            return
        }

        transcriptView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
    }

    private func consumeRunResultIfPresent(in transcript: String) {
        guard let pendingRun else {
            return
        }

        let escapedToken = NSRegularExpression.escapedPattern(for: pendingRun.token)
        let pattern = "__AC_RESULT__:\(escapedToken):(\\d+):(\\d+)s"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let match = regex.firstMatch(in: transcript, options: [], range: range),
              let codeRange = Range(match.range(at: 1), in: transcript),
              let durationRange = Range(match.range(at: 2), in: transcript) else {
            return
        }

        let exitCode = Int(transcript[codeRange]) ?? -1
        let durationSeconds = Int(transcript[durationRange]) ?? 0
        runResultLabel.text = "Last run: `\(pendingRun.command)` -> exit \(exitCode), duration \(durationSeconds)s"
        self.pendingRun = nil
    }

    private func wrappedCommandForExecution(_ command: String, token: String) -> String {
        let escapedCommand = shellSingleQuoted(command)
        return "__ac_start=$(date +%s); /bin/sh -lc '\(escapedCommand)'; __ac_code=$?; __ac_end=$(date +%s); printf \"\\n__AC_RESULT__:\(token):%d:%ds\\n\" \"$__ac_code\" \"$((__ac_end-__ac_start))\""
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func bindTheme() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .adminThemeDidChange,
            object: nil
        )
    }

    @objc
    private func handleThemeChange() {
        applyTheme()
    }

    private func applyTheme() {
        let theme = themeManager.theme(for: traitCollection)
        view.backgroundColor = theme.backgroundPrimary
        statusLabel.textColor = theme.textSecondary
        transcriptView.textColor = theme.textPrimary
        transcriptView.backgroundColor = theme.surfaceSecondary
        transcriptView.layer.borderColor = theme.strokeSubtle.cgColor
        commandField.backgroundColor = theme.surfacePrimary
        commandField.textColor = theme.textPrimary
        commandField.tintColor = theme.accent
        commandField.keyboardAppearance = themeManager.resolvedStyle(for: traitCollection) == .lightOps ? .light : .dark
        runCommandField.backgroundColor = theme.surfacePrimary
        runCommandField.textColor = theme.textPrimary
        runCommandField.tintColor = theme.accent
        runCommandField.keyboardAppearance = themeManager.resolvedStyle(for: traitCollection) == .lightOps ? .light : .dark
        runResultLabel.textColor = theme.textSecondary
        commandLogLabel.textColor = theme.textSecondary
        sendButton.configuration?.baseForegroundColor = .white
        sendButton.configuration?.baseBackgroundColor = theme.accent
        sendLineButton.configuration?.baseForegroundColor = theme.textPrimary
        sendLineButton.configuration?.baseBackgroundColor = theme.accentMuted
        runCommandButton.configuration?.baseForegroundColor = .white
        runCommandButton.configuration?.baseBackgroundColor = theme.statusSuccess
        pasteButton.configuration?.baseForegroundColor = theme.textPrimary
        for button in shortcutButtons {
            button.configuration?.baseForegroundColor = theme.textPrimary
            button.configuration?.baseBackgroundColor = theme.surfacePrimary
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        applyTheme()
    }

    @objc
    private func sendRawInput() {
        guard let text = commandField.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        commandField.text = nil
        sendTerminalText(text, label: text)
    }

    @objc
    private func sendInputLine() {
        guard let text = commandField.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        commandField.text = nil
        sendTerminalText(text + "\n", label: text + "↵")
    }

    @objc
    private func executeScriptedCommand() {
        guard let command = runCommandField.text,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let wrapped = wrappedCommandForExecution(command, token: token)
        pendingRun = PendingRun(token: token, command: command)
        runResultLabel.text = "Running: `\(command)` ..."
        runCommandField.text = nil
        sendTerminalText(wrapped + "\n", label: "Run: \(command)")
    }

    @objc
    private func sendEscape() {
        sendTerminalText("\u{001B}", label: "Esc")
    }

    @objc
    private func sendTab() {
        sendTerminalText("\t", label: "Tab")
    }

    @objc
    private func sendCtrlC() {
        sendTerminalText("\u{0003}", label: "Ctrl+C")
    }

    @objc
    private func sendArrowUp() {
        sendTerminalText("\u{001B}[A", label: "ArrowUp")
    }

    @objc
    private func sendArrowDown() {
        sendTerminalText("\u{001B}[B", label: "ArrowDown")
    }

    @objc
    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.isEmpty else {
            return
        }

        sendTerminalText(text, label: "Paste")
    }
}
