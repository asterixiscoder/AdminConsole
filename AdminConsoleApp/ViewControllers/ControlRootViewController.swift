import UniformTypeIdentifiers
import UIKit
import WebKit
import InputKit

final class ControlRootViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let workModeControl = UISegmentedControl(items: ["SSH", "VNC", "Browser"])
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private let focusedLabel = UILabel()
    private let cursorLabel = UILabel()
    private let inputLabel = UILabel()
    private let inputCaptureStatusLabel = UILabel()
    private let inputCaptureControl = UISegmentedControl(items: ["Auto", "Terminal", "VNC"])
    private let terminalStatusLabel = UILabel()
    private let terminalPreviewView = UITextView()
    private let browserStatusLabel = UILabel()
    private let browserPreviewView = UITextView()
    private let filesStatusLabel = UILabel()
    private let filesPreviewView = UITextView()
    private let vncStatusLabel = UILabel()
    private let vncPreviewView = UITextView()
    private let filesEntriesStack = UIStackView()
    private let newFolderField = UITextField()
    private let renameEntryField = UITextField()
    private let trackpadView = UIView()
    private let trackpadCursor = UIView()
    private let miniDockContainer = UIView()
    private let miniDockContentStack = UIStackView()
    private let miniDockToggleButton = UIButton(type: .system)
    private let keyboardHintLabel = UILabel()
    private let softModifierStatusLabel = UILabel()
    private let softKeyboardPresetControl = UISegmentedControl(items: ["Terminal", "VNC"])
    private let softControlButton = UIButton(type: .system)
    private let softAlternateButton = UIButton(type: .system)
    private let terminalDockStack = UIStackView()
    private let vncDockStack = UIStackView()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let commandField = UITextField()
    private let vncHostField = UITextField()
    private let vncPortField = UITextField()
    private let vncPasswordField = UITextField()
    private let vncInputField = UITextField()
    private let browserURLField = UITextField()
    private let displayWidthField = UITextField()
    private let displayHeightField = UITextField()
    private let displayScaleField = UITextField()
    private let displayStatusLabel = UILabel()
    private let vncQualityControl = UISegmentedControl(items: ["Low", "Balanced", "High"])
    private let vncTrackpadSwitch = UISwitch()
    private let vncDragButton = UIButton(type: .system)
    private var softControlModifierLatched = false
    private var softAlternateModifierLatched = false
    private weak var activeSoftRepeatButton: SoftRepeatKeyButton?
    private var softRepeatDelayWorkItem: DispatchWorkItem?
    private var softRepeatTimer: Timer?
    private var miniDockCollapsedWidthConstraint: NSLayoutConstraint?
    private var miniDockExpandedWidthConstraint: NSLayoutConstraint?
    private var isMiniDockCollapsed = false
    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?
    private var isAwaitingFilesExport = false
    private var sshCardView: UIView?
    private var vncCardView: UIView?
    private var browserCardView: UIView?
    private var filesCardView: UIView?

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

        workModeControl.selectedSegmentIndex = 0
        workModeControl.addTarget(self, action: #selector(workModeChanged), for: .valueChanged)

        [statusLabel, focusedLabel, cursorLabel, inputLabel, inputCaptureStatusLabel, terminalStatusLabel, browserStatusLabel, filesStatusLabel, vncStatusLabel, displayStatusLabel, softModifierStatusLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .body)
            label.numberOfLines = 0
        }

        terminalPreviewView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalPreviewView.textColor = .secondaryLabel
        terminalPreviewView.text = "No terminal output yet."
        terminalPreviewView.backgroundColor = .clear
        terminalPreviewView.isEditable = false
        terminalPreviewView.isSelectable = true
        terminalPreviewView.isScrollEnabled = true
        terminalPreviewView.textContainerInset = .zero
        terminalPreviewView.textContainer.lineFragmentPadding = 0
        terminalPreviewView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        browserPreviewView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        browserPreviewView.textColor = .secondaryLabel
        browserPreviewView.text = "No browser window selected."
        browserPreviewView.backgroundColor = .clear
        browserPreviewView.isEditable = false
        browserPreviewView.isSelectable = true
        browserPreviewView.isScrollEnabled = true
        browserPreviewView.textContainerInset = .zero
        browserPreviewView.textContainer.lineFragmentPadding = 0
        browserPreviewView.heightAnchor.constraint(equalToConstant: 140).isActive = true

        filesPreviewView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        filesPreviewView.textColor = .secondaryLabel
        filesPreviewView.text = "No files window selected."
        filesPreviewView.backgroundColor = .clear
        filesPreviewView.isEditable = false
        filesPreviewView.isSelectable = true
        filesPreviewView.isScrollEnabled = true
        filesPreviewView.textContainerInset = .zero
        filesPreviewView.textContainer.lineFragmentPadding = 0
        filesPreviewView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        vncPreviewView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        vncPreviewView.textColor = .secondaryLabel
        vncPreviewView.text = "No VNC window selected."
        vncPreviewView.backgroundColor = .clear
        vncPreviewView.isEditable = false
        vncPreviewView.isSelectable = true
        vncPreviewView.isScrollEnabled = true
        vncPreviewView.textContainerInset = .zero
        vncPreviewView.textContainer.lineFragmentPadding = 0
        vncPreviewView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        filesEntriesStack.axis = .vertical
        filesEntriesStack.spacing = 8

        keyboardHintLabel.text = """
        Keyboard prototype
        Cmd+1 Terminal
        Cmd+2 Files
        Cmd+3 Browser
        Cmd+4 VNC
        Cmd+5 Capture Auto
        Cmd+6 Capture Terminal
        Cmd+7 Capture VNC
        Cmd+M Toggle fullscreen focused window
        Cmd+V Paste clipboard to terminal
        Arrow keys move cursor unless terminal or VNC focus is active
        Soft keyboard dock presets: Terminal / VNC
        Ctrl/Alt are latched modifiers, Enter/Backspace and arrows support hold-to-repeat
        Drag mode keeps the primary VNC mouse button pressed while you move
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
        setupTrackpadMiniDock()

        let infoCard = makeCard(
            arrangedSubviews: [
                workModeControl,
                summaryLabel,
                statusLabel,
                focusedLabel,
                cursorLabel,
                inputLabel,
                terminalStatusLabel,
                terminalPreviewView
            ]
        )
        let trackpadCard = makeCard(arrangedSubviews: [trackpadView, makeSoftKeyboardControls(), keyboardHintLabel])
        let actionsCard = makeCard(arrangedSubviews: [makeButtonsRow()])
        let displayCard = makeCard(arrangedSubviews: [makeDisplayControls()])
        let sshCard = makeCard(arrangedSubviews: [makeSSHControls()])
        let browserCard = makeCard(arrangedSubviews: [makeBrowserControls()])
        let filesCard = makeCard(arrangedSubviews: [makeFilesControls()])
        let vncCard = makeCard(arrangedSubviews: [makeVNCControls()])
        sshCardView = sshCard
        vncCardView = vncCard
        browserCardView = browserCard
        filesCardView = filesCard

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18

        [infoCard, trackpadCard, actionsCard, displayCard, sshCard, browserCard, filesCard, vncCard].forEach(stackView.addArrangedSubview)
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
        panGesture.delegate = self
        tapGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        tapGesture.cancelsTouchesInView = false
        trackpadView.addGestureRecognizer(panGesture)
        trackpadView.addGestureRecognizer(tapGesture)

        updateSoftModifierUI()
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
        stopSoftRepeat()
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            makeKeyCommand("1", modifiers: .command, action: #selector(openTerminal), title: "Open Terminal"),
            makeKeyCommand("2", modifiers: .command, action: #selector(openFiles), title: "Open Files"),
            makeKeyCommand("3", modifiers: .command, action: #selector(openBrowserWindow), title: "Open Browser"),
            makeKeyCommand("4", modifiers: .command, action: #selector(openVNC), title: "Open VNC"),
            makeKeyCommand("5", modifiers: .command, action: #selector(setCaptureAutomatic), title: "Input Capture Automatic"),
            makeKeyCommand("6", modifiers: .command, action: #selector(setCaptureTerminal), title: "Input Capture Terminal"),
            makeKeyCommand("7", modifiers: .command, action: #selector(setCaptureVNC), title: "Input Capture VNC"),
            makeKeyCommand("m", modifiers: .command, action: #selector(toggleMaximizeFocusedWindow), title: "Toggle Fullscreen Focused Window"),
            makeKeyCommand("v", modifiers: .command, action: #selector(pasteClipboardToTerminal), title: "Paste Clipboard to Terminal")
        ]

        if !routesHardwareKeyboardToTerminal && !routesHardwareKeyboardToVNC {
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
               let terminalInput = routedKeyboardInput(for: key) {
                Task {
                    await AppEnvironment.phaseZero.sendInputToFocusedTerminal(terminalInput)
                }
                return
            }

            if routesHardwareKeyboardToVNC,
               let vncInput = routedKeyboardInput(for: key) {
                Task {
                    await AppEnvironment.phaseZero.sendInputToFocusedVNC(vncInput)
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
        syncDisplayFieldsIfNeeded(snapshot: snapshot)
        syncInputCaptureControlsIfNeeded(snapshot: snapshot)
        syncSoftKeyboardPresetIfNeeded(snapshot: snapshot)
        syncWorkModeControlIfNeeded(snapshot: snapshot)
        applyVisibleCards(for: snapshot.activeWorkMode)
        statusLabel.text = """
        Revision: \(snapshot.revision)
        External display: \(snapshot.isExternalDisplayConnected ? "connected" : "disconnected")
        Resolution: \(Int(snapshot.displayProfile.width)) x \(Int(snapshot.displayProfile.height)) @ \(String(format: "%.1f", snapshot.displayProfile.scale))x
        """
        displayStatusLabel.text = """
        Current profile:
        \(Int(snapshot.displayProfile.width)) x \(Int(snapshot.displayProfile.height)) points
        Effective pixels: \(Int(snapshot.displayProfile.width * snapshot.displayProfile.scale)) x \(Int(snapshot.displayProfile.height * snapshot.displayProfile.scale))
        """

        if let focusedID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedID }) {
            focusedLabel.text = "Focused window: \(focusedWindow.title)"
        } else {
            focusedLabel.text = "Focused window: none"
        }

        inputCaptureStatusLabel.text = inputCaptureStatusText(snapshot: snapshot)
        cursorLabel.text = "Cursor: x \(String(format: "%.2f", snapshot.cursor.x)), y \(String(format: "%.2f", snapshot.cursor.y))"
        inputLabel.text = "Last input: \(snapshot.lastInputDescription)"
        terminalStatusLabel.text = terminalStatusText(snapshot: snapshot)
        terminalPreviewView.text = terminalPreview(snapshot: snapshot)
        browserStatusLabel.text = browserStatusText(snapshot: snapshot)
        browserPreviewView.text = browserPreview(snapshot: snapshot)
        filesStatusLabel.text = filesStatusText(snapshot: snapshot)
        filesPreviewView.text = filesPreview(snapshot: snapshot)
        vncStatusLabel.text = vncStatusText(snapshot: snapshot)
        vncPreviewView.text = vncPreview(snapshot: snapshot)
        refreshFilesEntries(snapshot: snapshot)
        updateVNCDragButton(snapshot: snapshot)

        applyTrackpadCursor(snapshot: snapshot)
        updateSoftModifierUI()
    }

    private func syncDisplayFieldsIfNeeded(snapshot: PhaseZeroSnapshot) {
        if !(displayWidthField.isEditing || displayHeightField.isEditing || displayScaleField.isEditing) {
            displayWidthField.text = String(Int(snapshot.displayProfile.width))
            displayHeightField.text = String(Int(snapshot.displayProfile.height))
            displayScaleField.text = String(format: "%.2f", snapshot.displayProfile.scale)
        }
    }

    private func syncInputCaptureControlsIfNeeded(snapshot: PhaseZeroSnapshot) {
        let expectedIndex: Int
        switch snapshot.inputCaptureMode {
        case .automatic:
            expectedIndex = 0
        case .terminal:
            expectedIndex = 1
        case .vnc:
            expectedIndex = 2
        }

        if inputCaptureControl.selectedSegmentIndex != expectedIndex {
            inputCaptureControl.selectedSegmentIndex = expectedIndex
        }
    }

    private func syncSoftKeyboardPresetIfNeeded(snapshot: PhaseZeroSnapshot) {
        let expectedIndex: Int?
        switch snapshot.inputCaptureMode {
        case .automatic:
            expectedIndex = nil
        case .terminal:
            expectedIndex = 0
        case .vnc:
            expectedIndex = 1
        }

        guard let expectedIndex,
              softKeyboardPresetControl.selectedSegmentIndex != expectedIndex,
              !softKeyboardPresetControl.isTracking else {
            return
        }

        softKeyboardPresetControl.selectedSegmentIndex = expectedIndex
        applySoftKeyboardPresetUI()
    }

    private func syncWorkModeControlIfNeeded(snapshot: PhaseZeroSnapshot) {
        let expectedIndex: Int
        switch snapshot.activeWorkMode {
        case .ssh:
            expectedIndex = 0
        case .vnc:
            expectedIndex = 1
        case .browser:
            expectedIndex = 2
        }

        if workModeControl.selectedSegmentIndex != expectedIndex {
            workModeControl.selectedSegmentIndex = expectedIndex
        }
    }

    private func applyVisibleCards(for mode: PhaseZeroWorkMode) {
        sshCardView?.isHidden = mode != .ssh
        vncCardView?.isHidden = mode != .vnc
        browserCardView?.isHidden = mode != .browser
        filesCardView?.isHidden = true
    }

    private func applyTrackpadCursor(snapshot: PhaseZeroSnapshot) {
        guard trackpadView.bounds.width > 0, trackpadView.bounds.height > 0 else {
            return
        }

        let x = snapshot.cursor.x * trackpadView.bounds.width
        let y = snapshot.cursor.y * trackpadView.bounds.height
        trackpadCursor.center = CGPoint(x: x, y: y)
    }

    private func setupTrackpadMiniDock() {
        miniDockContainer.translatesAutoresizingMaskIntoConstraints = false
        miniDockContainer.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        miniDockContainer.layer.cornerRadius = 12
        miniDockContainer.layer.borderWidth = 1
        miniDockContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        miniDockContainer.clipsToBounds = true

        miniDockToggleButton.translatesAutoresizingMaskIntoConstraints = false
        miniDockToggleButton.configuration = .plain()
        miniDockToggleButton.configuration?.title = "×"
        miniDockToggleButton.tintColor = .white
        miniDockToggleButton.addTarget(self, action: #selector(toggleMiniDockCollapsed), for: .touchUpInside)

        miniDockContentStack.translatesAutoresizingMaskIntoConstraints = false
        miniDockContentStack.axis = .vertical
        miniDockContentStack.spacing = 6

        let editingRow = UIStackView()
        editingRow.axis = .horizontal
        editingRow.spacing = 6
        editingRow.distribution = .fillEqually
        editingRow.addArrangedSubview(makeMiniDockKeyButton(title: "Esc", payload: "\u{001B}", description: "Dock Esc"))
        editingRow.addArrangedSubview(makeMiniDockKeyButton(title: "Tab", payload: "\t", description: "Dock Tab"))
        editingRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "⌫", payload: "\u{7F}", description: "Dock Backspace"))
        editingRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "↩", payload: "\n", description: "Dock Enter"))

        let arrowsRow = UIStackView()
        arrowsRow.axis = .horizontal
        arrowsRow.spacing = 6
        arrowsRow.distribution = .fillEqually
        arrowsRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "↑", payload: "\u{001B}[A", description: "Dock Arrow Up"))
        arrowsRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "↓", payload: "\u{001B}[B", description: "Dock Arrow Down"))
        arrowsRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "←", payload: "\u{001B}[D", description: "Dock Arrow Left"))
        arrowsRow.addArrangedSubview(makeMiniDockRepeatKeyButton(title: "→", payload: "\u{001B}[C", description: "Dock Arrow Right"))

        miniDockContentStack.addArrangedSubview(editingRow)
        miniDockContentStack.addArrangedSubview(arrowsRow)

        trackpadView.addSubview(miniDockContainer)
        miniDockContainer.addSubview(miniDockToggleButton)
        miniDockContainer.addSubview(miniDockContentStack)

        miniDockCollapsedWidthConstraint = miniDockContainer.widthAnchor.constraint(equalToConstant: 44)
        miniDockExpandedWidthConstraint = miniDockContainer.widthAnchor.constraint(equalToConstant: 212)
        miniDockExpandedWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            miniDockContainer.topAnchor.constraint(equalTo: trackpadView.topAnchor, constant: 10),
            miniDockContainer.trailingAnchor.constraint(equalTo: trackpadView.trailingAnchor, constant: -10),
            miniDockContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            miniDockToggleButton.topAnchor.constraint(equalTo: miniDockContainer.topAnchor, constant: 4),
            miniDockToggleButton.trailingAnchor.constraint(equalTo: miniDockContainer.trailingAnchor, constant: -4),
            miniDockToggleButton.widthAnchor.constraint(equalToConstant: 32),
            miniDockToggleButton.heightAnchor.constraint(equalToConstant: 32),

            miniDockContentStack.leadingAnchor.constraint(equalTo: miniDockContainer.leadingAnchor, constant: 8),
            miniDockContentStack.trailingAnchor.constraint(equalTo: miniDockContainer.trailingAnchor, constant: -8),
            miniDockContentStack.topAnchor.constraint(equalTo: miniDockToggleButton.bottomAnchor, constant: 2),
            miniDockContentStack.bottomAnchor.constraint(equalTo: miniDockContainer.bottomAnchor, constant: -8)
        ])

        applyMiniDockCollapsedState()
    }

    private func makeMiniDockKeyButton(title: String, payload: String, description: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.configuration?.baseForegroundColor = .white
        button.addAction(
            UIAction { [weak self] _ in
                self?.sendSoftKeyPayload(payload, description: description, registerEvent: false)
            },
            for: .touchUpInside
        )
        return button
    }

    private func makeMiniDockRepeatKeyButton(title: String, payload: String, description: String) -> UIButton {
        let button = SoftRepeatKeyButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.configuration?.baseForegroundColor = .white
        button.payload = payload
        button.payloadDescription = description
        button.addTarget(self, action: #selector(handleSoftRepeatTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchUpOutside)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchCancel)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchDragExit)
        return button
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

        let captureLabel = UILabel()
        captureLabel.font = .preferredFont(forTextStyle: .headline)
        captureLabel.text = "Input Capture"

        inputCaptureControl.selectedSegmentIndex = 0
        inputCaptureControl.addTarget(self, action: #selector(inputCaptureModeChanged), for: .valueChanged)
        inputCaptureStatusLabel.text = "Input capture: Automatic"
        inputCaptureStatusLabel.textColor = .secondaryLabel

        stack.addArrangedSubview(captureLabel)
        stack.addArrangedSubview(inputCaptureControl)
        stack.addArrangedSubview(inputCaptureStatusLabel)

        let buttons: [(String, Selector)] = [
            ("Open Terminal Window", #selector(openTerminal)),
            ("Open Files Window", #selector(openFiles)),
            ("Open Browser Window", #selector(openBrowserWindow)),
            ("Open VNC Window", #selector(openVNC)),
            ("Toggle Fullscreen Focused Window", #selector(toggleMaximizeFocusedWindow))
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

    private func makeSoftKeyboardControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "Soft Keyboard"

        softModifierStatusLabel.textColor = .secondaryLabel
        softModifierStatusLabel.text = "Modifiers: none"

        softKeyboardPresetControl.selectedSegmentIndex = 0
        softKeyboardPresetControl.addTarget(self, action: #selector(softKeyboardPresetChanged), for: .valueChanged)

        let modifiersRow = UIStackView()
        modifiersRow.axis = .horizontal
        modifiersRow.spacing = 8
        modifiersRow.distribution = .fillEqually

        softControlButton.configuration = .tinted()
        softControlButton.configuration?.title = "Ctrl"
        softControlButton.addTarget(self, action: #selector(toggleSoftControlModifier), for: .touchUpInside)

        softAlternateButton.configuration = .tinted()
        softAlternateButton.configuration?.title = "Alt"
        softAlternateButton.addTarget(self, action: #selector(toggleSoftAlternateModifier), for: .touchUpInside)

        modifiersRow.addArrangedSubview(softControlButton)
        modifiersRow.addArrangedSubview(softAlternateButton)

        terminalDockStack.axis = .vertical
        terminalDockStack.spacing = 8
        vncDockStack.axis = .vertical
        vncDockStack.spacing = 8

        let terminalEditingRow = makeSoftEditingRow()
        let terminalFnRow1 = makeFunctionRow(indices: [1, 2, 3, 4])
        let terminalFnRow2 = makeFunctionRow(indices: [5, 6, 7, 8])
        let terminalFnRow3 = makeFunctionRow(indices: [9, 10, 11, 12])
        let terminalComboRow = makeSoftCombosRow()
        [terminalEditingRow, terminalComboRow, terminalFnRow1, terminalFnRow2, terminalFnRow3].forEach(terminalDockStack.addArrangedSubview)

        let vncEditingRow = makeSoftEditingRow()
        let vncArrowsRow = makeArrowsRow()
        let vncFunctionRow = makeFunctionRow(indices: [1, 2, 11, 12])
        let vncDesktopRow = makeVNCDesktopRow()
        [vncEditingRow, vncArrowsRow, vncFunctionRow, vncDesktopRow].forEach(vncDockStack.addArrangedSubview)

        applySoftKeyboardPresetUI()

        [titleLabel, softKeyboardPresetControl, softModifierStatusLabel, modifiersRow, terminalDockStack, vncDockStack].forEach(stack.addArrangedSubview)
        return stack
    }

    private func makeSoftEditingRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.addArrangedSubview(makeSoftKeyButton(title: "Esc", payload: "\u{001B}", description: "Esc"))
        row.addArrangedSubview(makeSoftKeyButton(title: "Tab", payload: "\t", description: "Tab"))
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "⌫", payload: "\u{7F}", description: "Backspace"))
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "↩", payload: "\n", description: "Enter"))
        return row
    }

    private func makeArrowsRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "↑", payload: "\u{001B}[A", description: "Arrow Up"))
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "↓", payload: "\u{001B}[B", description: "Arrow Down"))
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "←", payload: "\u{001B}[D", description: "Arrow Left"))
        row.addArrangedSubview(makeSoftRepeatKeyButton(title: "→", payload: "\u{001B}[C", description: "Arrow Right"))
        return row
    }

    private func makeVNCDesktopRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        row.addArrangedSubview(makeSoftComboButton(title: "Alt+Tab", payload: "\u{001B}\t", description: "Alt+Tab"))
        row.addArrangedSubview(makeSoftKeyButton(title: "PgUp", payload: "\u{001B}[5~", description: "Page Up"))
        row.addArrangedSubview(makeSoftKeyButton(title: "PgDn", payload: "\u{001B}[6~", description: "Page Down"))
        row.addArrangedSubview(makeSoftComboButton(title: "Ctrl+C", payload: "\u{03}", description: "Ctrl+C"))
        return row
    }

    private func makeFunctionRow(indices: [Int]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for index in indices {
            row.addArrangedSubview(
                makeSoftKeyButton(
                    title: "F\(index)",
                    payload: functionKeySequence(index: index),
                    description: "F\(index)"
                )
            )
        }
        return row
    }

    private func makeSoftKeyButton(title: String, payload: String, description: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.addAction(
            UIAction { [weak self] _ in
                self?.sendSoftKeyPayload(payload, description: description)
            },
            for: .touchUpInside
        )
        return button
    }

    private func makeSoftCombosRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        row.addArrangedSubview(makeSoftComboButton(title: "Ctrl+C", payload: "\u{03}", description: "Ctrl+C"))
        row.addArrangedSubview(makeSoftComboButton(title: "Ctrl+L", payload: "\u{0C}", description: "Ctrl+L"))
        row.addArrangedSubview(makeSoftComboButton(title: "Ctrl+D", payload: "\u{04}", description: "Ctrl+D"))
        row.addArrangedSubview(makeSoftComboButton(title: "Alt+Tab", payload: "\u{001B}\t", description: "Alt+Tab"))
        return row
    }

    private func makeSoftComboButton(title: String, payload: String, description: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .plain()
        button.configuration?.title = title
        button.addAction(
            UIAction { [weak self] _ in
                self?.sendSoftKeyPayload(
                    payload,
                    description: description,
                    registerEvent: true,
                    applyLatchedModifiers: false
                )
            },
            for: .touchUpInside
        )
        return button
    }

    private func makeSoftRepeatKeyButton(title: String, payload: String, description: String) -> UIButton {
        let button = SoftRepeatKeyButton(type: .system)
        button.configuration = .tinted()
        button.configuration?.title = title
        button.payload = payload
        button.payloadDescription = description
        button.addTarget(self, action: #selector(handleSoftRepeatTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchUpOutside)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchCancel)
        button.addTarget(self, action: #selector(handleSoftRepeatTouchUp(_:)), for: .touchDragExit)
        return button
    }

    private func makeDisplayControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.text = "External Display Profile"

        configureField(displayWidthField, placeholder: "Width (points)", keyboardType: .decimalPad)
        configureField(displayHeightField, placeholder: "Height (points)", keyboardType: .decimalPad)
        configureField(displayScaleField, placeholder: "Scale (e.g. 2.0)", keyboardType: .decimalPad)

        let buttonsRow = UIStackView()
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 8
        buttonsRow.distribution = .fillEqually

        let applyButton = UIButton(type: .system)
        applyButton.configuration = .filled()
        applyButton.configuration?.title = "Apply Profile"
        applyButton.addTarget(self, action: #selector(applyDisplayProfileOverride), for: .touchUpInside)

        let presetButton = UIButton(type: .system)
        presetButton.configuration = .tinted()
        presetButton.configuration?.title = "Preset 1080p"
        presetButton.addTarget(self, action: #selector(apply1080pDisplayPreset), for: .touchUpInside)

        let fitButton = UIButton(type: .system)
        fitButton.configuration = .tinted()
        fitButton.configuration?.title = "Fit to External"
        fitButton.addTarget(self, action: #selector(fitDisplayToExternalScene), for: .touchUpInside)

        [applyButton, presetButton, fitButton].forEach(buttonsRow.addArrangedSubview)

        [
            titleLabel,
            displayStatusLabel,
            displayWidthField,
            displayHeightField,
            displayScaleField,
            buttonsRow
        ].forEach(stack.addArrangedSubview)

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

        let copyVisibleButton = UIButton(type: .system)
        copyVisibleButton.configuration = .plain()
        copyVisibleButton.configuration?.title = "Copy Visible Screen"
        copyVisibleButton.addTarget(self, action: #selector(copyVisibleTerminalScreen), for: .touchUpInside)

        let copyTranscriptButton = UIButton(type: .system)
        copyTranscriptButton.configuration = .plain()
        copyTranscriptButton.configuration?.title = "Copy Full Transcript"
        copyTranscriptButton.addTarget(self, action: #selector(copyTerminalTranscript), for: .touchUpInside)

        let copySelectionButton = UIButton(type: .system)
        copySelectionButton.configuration = .plain()
        copySelectionButton.configuration?.title = "Copy Active Selection"
        copySelectionButton.addTarget(self, action: #selector(copyTerminalSelection), for: .touchUpInside)

        let clearSelectionButton = UIButton(type: .system)
        clearSelectionButton.configuration = .plain()
        clearSelectionButton.configuration?.title = "Clear Selection"
        clearSelectionButton.addTarget(self, action: #selector(clearTerminalSelection), for: .touchUpInside)

        let pasteClipboardButton = UIButton(type: .system)
        pasteClipboardButton.configuration = .plain()
        pasteClipboardButton.configuration?.title = "Paste Clipboard to Terminal"
        pasteClipboardButton.addTarget(self, action: #selector(pasteClipboardToTerminal), for: .touchUpInside)

        [
            titleLabel,
            hostField,
            portField,
            usernameField,
            passwordField,
            connectButton,
            commandField,
            sendButton,
            pasteClipboardButton,
            copySelectionButton,
            clearSelectionButton,
            copyVisibleButton,
            copyTranscriptButton
        ].forEach(stack.addArrangedSubview)

        return stack
    }

    private func makeFilesControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.text = "Files Workspace"

        configureField(newFolderField, placeholder: "New folder name")
        configureField(renameEntryField, placeholder: "Rename selected entry to")

        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 8
        controls.distribution = .fillEqually

        let upButton = UIButton(type: .system)
        upButton.configuration = .filled()
        upButton.configuration?.title = "Up"
        upButton.addTarget(self, action: #selector(navigateUpInFiles), for: .touchUpInside)

        let openButton = UIButton(type: .system)
        openButton.configuration = .tinted()
        openButton.configuration?.title = "Open Selected"
        openButton.addTarget(self, action: #selector(openSelectedFilesEntry), for: .touchUpInside)

        let refreshButton = UIButton(type: .system)
        refreshButton.configuration = .plain()
        refreshButton.configuration?.title = "Refresh"
        refreshButton.addTarget(self, action: #selector(refreshFilesWindow), for: .touchUpInside)

        let importButton = UIButton(type: .system)
        importButton.configuration = .plain()
        importButton.configuration?.title = "Import"
        importButton.addTarget(self, action: #selector(importFilesIntoWorkspace), for: .touchUpInside)

        let exportButton = UIButton(type: .system)
        exportButton.configuration = .plain()
        exportButton.configuration?.title = "Export"
        exportButton.addTarget(self, action: #selector(exportSelectedFilesEntry), for: .touchUpInside)

        [upButton, openButton, refreshButton, importButton, exportButton].forEach(controls.addArrangedSubview)
        controls.distribution = .fillProportionally

        let editControls = UIStackView()
        editControls.axis = .horizontal
        editControls.spacing = 8
        editControls.distribution = .fillEqually

        let createButton = UIButton(type: .system)
        createButton.configuration = .filled()
        createButton.configuration?.title = "Create Folder"
        createButton.addTarget(self, action: #selector(createFolderInFiles), for: .touchUpInside)

        let renameButton = UIButton(type: .system)
        renameButton.configuration = .tinted()
        renameButton.configuration?.title = "Rename Selected"
        renameButton.addTarget(self, action: #selector(renameSelectedFilesEntry), for: .touchUpInside)

        let deleteButton = UIButton(type: .system)
        deleteButton.configuration = .plain()
        deleteButton.configuration?.title = "Delete Selected"
        deleteButton.configuration?.baseForegroundColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteSelectedFilesEntry), for: .touchUpInside)

        [createButton, renameButton, deleteButton].forEach(editControls.addArrangedSubview)

        [
            titleLabel,
            filesStatusLabel,
            controls,
            newFolderField,
            renameEntryField,
            editControls,
            filesEntriesStack,
            filesPreviewView
        ].forEach(stack.addArrangedSubview)

        return stack
    }

    private func makeBrowserControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.text = "Browser"

        configureField(browserURLField, placeholder: "URL or host (focused browser)")
        browserURLField.returnKeyType = .go

        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 8
        controls.distribution = .fillEqually

        let navigateButton = UIButton(type: .system)
        navigateButton.configuration = .filled()
        navigateButton.configuration?.title = "Navigate"
        navigateButton.addTarget(self, action: #selector(navigateFocusedBrowser), for: .touchUpInside)

        let reloadButton = UIButton(type: .system)
        reloadButton.configuration = .tinted()
        reloadButton.configuration?.title = "Reload"
        reloadButton.addTarget(self, action: #selector(reloadFocusedBrowser), for: .touchUpInside)

        let backButton = UIButton(type: .system)
        backButton.configuration = .plain()
        backButton.configuration?.title = "Back"
        backButton.addTarget(self, action: #selector(goBackInFocusedBrowser), for: .touchUpInside)

        let forwardButton = UIButton(type: .system)
        forwardButton.configuration = .plain()
        forwardButton.configuration?.title = "Forward"
        forwardButton.addTarget(self, action: #selector(goForwardInFocusedBrowser), for: .touchUpInside)

        [navigateButton, reloadButton, backButton, forwardButton].forEach(controls.addArrangedSubview)

        [
            titleLabel,
            browserStatusLabel,
            browserURLField,
            controls,
            browserPreviewView
        ].forEach(stack.addArrangedSubview)

        return stack
    }

    private func makeVNCControls() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.text = "VNC Spike"

        configureField(vncHostField, placeholder: "VNC host", textContentType: .URL)
        configureField(vncPortField, placeholder: "VNC port", keyboardType: .numberPad)
        vncPortField.text = "5900"
        configureField(vncPasswordField, placeholder: "VNC password (optional)")
        vncPasswordField.isSecureTextEntry = true
        configureField(vncInputField, placeholder: "Text to send to focused VNC window")
        vncInputField.returnKeyType = .send

        let qualityLabel = UILabel()
        qualityLabel.font = .preferredFont(forTextStyle: .footnote)
        qualityLabel.textColor = .secondaryLabel
        qualityLabel.text = "Quality preset"

        vncQualityControl.selectedSegmentIndex = 1

        let trackpadLabel = UILabel()
        trackpadLabel.font = .preferredFont(forTextStyle: .footnote)
        trackpadLabel.textColor = .secondaryLabel
        trackpadLabel.text = "Trackpad mode"

        let trackpadRow = UIStackView(arrangedSubviews: [trackpadLabel, vncTrackpadSwitch])
        trackpadRow.axis = .horizontal
        trackpadRow.alignment = .center
        trackpadRow.distribution = .equalSpacing
        vncTrackpadSwitch.isOn = true

        let connectButton = UIButton(type: .system)
        connectButton.configuration = .filled()
        connectButton.configuration?.title = "Connect Focused VNC"
        connectButton.addTarget(self, action: #selector(connectVNC), for: .touchUpInside)

        let sessionButtons = UIStackView()
        sessionButtons.axis = .horizontal
        sessionButtons.spacing = 8
        sessionButtons.distribution = .fillEqually

        let reconnectButton = UIButton(type: .system)
        reconnectButton.configuration = .tinted()
        reconnectButton.configuration?.title = "Reconnect"
        reconnectButton.addTarget(self, action: #selector(reconnectVNC), for: .touchUpInside)

        let disconnectButton = UIButton(type: .system)
        disconnectButton.configuration = .plain()
        disconnectButton.configuration?.title = "Disconnect"
        disconnectButton.configuration?.baseForegroundColor = .systemRed
        disconnectButton.addTarget(self, action: #selector(disconnectVNC), for: .touchUpInside)

        [reconnectButton, disconnectButton].forEach(sessionButtons.addArrangedSubview)

        let buttons = UIStackView()
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let sendButton = UIButton(type: .system)
        sendButton.configuration = .tinted()
        sendButton.configuration?.title = "Send Text"
        sendButton.addTarget(self, action: #selector(sendTextToVNC), for: .touchUpInside)

        let clickButton = UIButton(type: .system)
        clickButton.configuration = .plain()
        clickButton.configuration?.title = "Primary"
        clickButton.addTarget(self, action: #selector(clickFocusedVNC), for: .touchUpInside)

        let secondaryClickButton = UIButton(type: .system)
        secondaryClickButton.configuration = .plain()
        secondaryClickButton.configuration?.title = "Secondary"
        secondaryClickButton.addTarget(self, action: #selector(secondaryClickFocusedVNC), for: .touchUpInside)

        let middleClickButton = UIButton(type: .system)
        middleClickButton.configuration = .plain()
        middleClickButton.configuration?.title = "Middle"
        middleClickButton.addTarget(self, action: #selector(middleClickFocusedVNC), for: .touchUpInside)

        let qualityButton = UIButton(type: .system)
        qualityButton.configuration = .plain()
        qualityButton.configuration?.title = "Cycle Quality"
        qualityButton.addTarget(self, action: #selector(cycleVNCQuality), for: .touchUpInside)

        [sendButton, clickButton, secondaryClickButton, middleClickButton].forEach(buttons.addArrangedSubview)

        let pointerModeButtons = UIStackView()
        pointerModeButtons.axis = .horizontal
        pointerModeButtons.spacing = 8
        pointerModeButtons.distribution = .fillEqually

        vncDragButton.configuration = .plain()
        vncDragButton.configuration?.title = "Start Drag"
        vncDragButton.addTarget(self, action: #selector(toggleVNCPrimaryDrag), for: .touchUpInside)

        let wheelUpButton = UIButton(type: .system)
        wheelUpButton.configuration = .plain()
        wheelUpButton.configuration?.title = "Wheel Up"
        wheelUpButton.addTarget(self, action: #selector(scrollVNCWheelUp), for: .touchUpInside)

        let wheelDownButton = UIButton(type: .system)
        wheelDownButton.configuration = .plain()
        wheelDownButton.configuration?.title = "Wheel Down"
        wheelDownButton.addTarget(self, action: #selector(scrollVNCWheelDown), for: .touchUpInside)

        [vncDragButton, wheelUpButton, wheelDownButton, qualityButton].forEach(pointerModeButtons.addArrangedSubview)

        let clipboardButtons = UIStackView()
        clipboardButtons.axis = .horizontal
        clipboardButtons.spacing = 8
        clipboardButtons.distribution = .fillEqually

        let pasteClipboardButton = UIButton(type: .system)
        pasteClipboardButton.configuration = .plain()
        pasteClipboardButton.configuration?.title = "Paste Clipboard"
        pasteClipboardButton.addTarget(self, action: #selector(pasteClipboardToVNC), for: .touchUpInside)

        let copyRemoteClipboardButton = UIButton(type: .system)
        copyRemoteClipboardButton.configuration = .plain()
        copyRemoteClipboardButton.configuration?.title = "Copy Remote Clipboard"
        copyRemoteClipboardButton.addTarget(self, action: #selector(copyRemoteVNCClipboard), for: .touchUpInside)

        [pasteClipboardButton, copyRemoteClipboardButton].forEach(clipboardButtons.addArrangedSubview)

        [
            titleLabel,
            vncStatusLabel,
            vncHostField,
            vncPortField,
            vncPasswordField,
            qualityLabel,
            vncQualityControl,
            trackpadRow,
            connectButton,
            sessionButtons,
            vncInputField,
            buttons,
            pointerModeButtons,
            clipboardButtons,
            vncPreviewView
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

        gesture.setTranslation(.zero, in: trackpadView)

        Task {
            await AppEnvironment.phaseZero.handlePointerPan(
                translation: translation,
                surfaceSize: trackpadView.bounds.size,
                source: .touchTrackpad
            )

            if gesture.state == .ended || gesture.state == .cancelled {
                await AppEnvironment.phaseZero.registerControlInput("Trackpad pan")
            }
        }
    }

    @objc
    private func handleTrackpadTap() {
        Task {
            if self.routesPointerToVNC {
                if self.isVNCPrimaryDragActive(snapshot: self.latestSnapshot) {
                    await AppEnvironment.phaseZero.registerControlInput("Trackpad tap ignored while VNC drag is active")
                } else {
                    await AppEnvironment.phaseZero.clickFocusedVNC()
                }
            }
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
    private func copyVisibleTerminalScreen() {
        guard let terminalState = focusedTerminalWindow(snapshot: latestSnapshot)?.terminalState else {
            return
        }

        UIPasteboard.general.string = terminalState.buffer.viewportText(
            insertingCursor: terminalState.sessionState == .connected
        )

        Task {
            await AppEnvironment.phaseZero.registerControlInput("Copied visible terminal screen")
        }
    }

    @objc
    private func copyTerminalTranscript() {
        guard let terminalState = focusedTerminalWindow(snapshot: latestSnapshot)?.terminalState else {
            return
        }

        UIPasteboard.general.string = terminalState.transcript

        Task {
            await AppEnvironment.phaseZero.registerControlInput("Copied terminal transcript")
        }
    }

    @objc
    private func pasteClipboardToTerminal() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.isEmpty else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Clipboard paste skipped: clipboard is empty")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.sendInputToFocusedTerminal(clipboardText)
        }
    }

    @objc
    private func navigateUpInFiles() {
        Task {
            await AppEnvironment.phaseZero.navigateUpInFocusedFiles()
            await AppEnvironment.phaseZero.registerControlInput("Files navigate up")
        }
    }

    @objc
    private func openSelectedFilesEntry() {
        Task {
            await AppEnvironment.phaseZero.openSelectedFilesEntry()
            await AppEnvironment.phaseZero.registerControlInput("Files open selected entry")
        }
    }

    @objc
    private func refreshFilesWindow() {
        Task {
            await AppEnvironment.phaseZero.refreshFocusedFiles()
            await AppEnvironment.phaseZero.registerControlInput("Files refresh")
        }
    }

    @objc
    private func createFolderInFiles() {
        let name = newFolderField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return
        }

        newFolderField.text = nil

        Task {
            await AppEnvironment.phaseZero.createFolderInFocusedFiles(named: name)
            await AppEnvironment.phaseZero.registerControlInput("Files create folder")
        }
    }

    @objc
    private func renameSelectedFilesEntry() {
        let name = renameEntryField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return
        }

        renameEntryField.text = nil

        Task {
            await AppEnvironment.phaseZero.renameSelectedFilesEntry(to: name)
            await AppEnvironment.phaseZero.registerControlInput("Files rename selected entry")
        }
    }

    @objc
    private func deleteSelectedFilesEntry() {
        Task {
            await AppEnvironment.phaseZero.deleteSelectedFilesEntry()
            await AppEnvironment.phaseZero.registerControlInput("Files delete selected entry")
        }
    }

    @objc
    private func importFilesIntoWorkspace() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        isAwaitingFilesExport = false
        present(picker, animated: true)
    }

    @objc
    private func exportSelectedFilesEntry() {
        Task {
            guard let exportURL = await AppEnvironment.phaseZero.exportURLForSelectedFilesEntry() else {
                await AppEnvironment.phaseZero.registerControlInput("Files export skipped: no selected entry")
                return
            }

            await MainActor.run {
                let picker = UIDocumentPickerViewController(forExporting: [exportURL], asCopy: true)
                picker.delegate = self
                self.isAwaitingFilesExport = true
                self.present(picker, animated: true)
            }

            await AppEnvironment.phaseZero.registerControlInput("Files export started")
        }
    }

    @objc
    private func connectVNC() {
        view.endEditing(true)

        guard let request = makeVNCRequest() else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("VNC connect skipped: invalid form")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.connectFocusedVNC(using: request)
        }
    }

    @objc
    private func reconnectVNC() {
        Task {
            await AppEnvironment.phaseZero.reconnectFocusedVNC()
        }
    }

    @objc
    private func disconnectVNC() {
        Task {
            await AppEnvironment.phaseZero.disconnectFocusedVNC()
        }
    }

    @objc
    private func sendTextToVNC() {
        guard let text = vncInputField.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        vncInputField.text = nil

        Task {
            await AppEnvironment.phaseZero.sendInputToFocusedVNC(text)
        }
    }

    @objc
    private func clickFocusedVNC() {
        Task {
            await AppEnvironment.phaseZero.clickFocusedVNC()
            await AppEnvironment.phaseZero.registerControlInput("VNC primary click")
        }
    }

    @objc
    private func secondaryClickFocusedVNC() {
        Task {
            await AppEnvironment.phaseZero.clickFocusedVNC(button: .secondary)
            await AppEnvironment.phaseZero.registerControlInput("VNC secondary click")
        }
    }

    @objc
    private func middleClickFocusedVNC() {
        Task {
            await AppEnvironment.phaseZero.clickFocusedVNC(button: .middle)
            await AppEnvironment.phaseZero.registerControlInput("VNC middle click")
        }
    }

    @objc
    private func cycleVNCQuality() {
        Task {
            await AppEnvironment.phaseZero.cycleQualityPresetForFocusedVNC()
        }
    }

    @objc
    private func toggleVNCPrimaryDrag() {
        Task {
            await AppEnvironment.phaseZero.togglePrimaryDragInFocusedVNC()
            await AppEnvironment.phaseZero.registerControlInput("VNC drag toggled")
        }
    }

    @objc
    private func scrollVNCWheelUp() {
        Task {
            await AppEnvironment.phaseZero.scrollFocusedVNC(.up)
            await AppEnvironment.phaseZero.registerControlInput("VNC wheel up")
        }
    }

    @objc
    private func scrollVNCWheelDown() {
        Task {
            await AppEnvironment.phaseZero.scrollFocusedVNC(.down)
            await AppEnvironment.phaseZero.registerControlInput("VNC wheel down")
        }
    }

    @objc
    private func pasteClipboardToVNC() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.isEmpty else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("VNC clipboard paste skipped: clipboard is empty")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.sendClipboardToFocusedVNC(clipboardText)
        }
    }

    @objc
    private func copyRemoteVNCClipboard() {
        Task {
            guard let text = await AppEnvironment.phaseZero.remoteClipboardTextForFocusedVNC(),
                  !text.isEmpty else {
                await AppEnvironment.phaseZero.registerControlInput("VNC clipboard copy skipped: remote clipboard is empty")
                return
            }

            await MainActor.run {
                UIPasteboard.general.string = text
            }
            await AppEnvironment.phaseZero.registerControlInput("VNC clipboard <- remote")
        }
    }

    @objc
    private func copyTerminalSelection() {
        Task {
            guard let selectedText = await AppEnvironment.phaseZero.selectedTextForFocusedTerminal(),
                  !selectedText.isEmpty else {
                await AppEnvironment.phaseZero.registerControlInput("Copy selection skipped: no active terminal selection")
                return
            }

            await MainActor.run {
                UIPasteboard.general.string = selectedText
            }
            await AppEnvironment.phaseZero.registerControlInput("Copied active terminal selection")
        }
    }

    @objc
    private func clearTerminalSelection() {
        Task {
            await AppEnvironment.phaseZero.clearFocusedTerminalSelection()
            await AppEnvironment.phaseZero.registerControlInput("Cleared terminal selection")
        }
    }

    @objc
    private func openTerminal() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.terminal)
            await AppEnvironment.phaseZero.setActiveWorkMode(.ssh)
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
            await AppEnvironment.phaseZero.setActiveWorkMode(.browser)
            await AppEnvironment.phaseZero.registerControlInput("Open browser window")
        }
    }

    @objc
    private func navigateFocusedBrowser() {
        let address = browserURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !address.isEmpty else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Browser navigate skipped: URL is empty")
            }
            return
        }

        guard let normalizedURLString = normalizedBrowserAddress(address) else {
            setBrowserAddressValidationState(isValid: false)
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Browser navigate skipped: invalid address")
            }
            return
        }

        if !isAllowedBrowserAddress(normalizedURLString) {
            setBrowserAddressValidationState(isValid: false)
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Browser navigate blocked: only http/https are allowed")
            }
            browserURLField.text = normalizedURLString
            return
        }

        setBrowserAddressValidationState(isValid: true)
        browserURLField.text = normalizedURLString
        Task {
            await AppEnvironment.phaseZero.navigateFocusedBrowser(to: normalizedURLString)
        }
    }

    @objc
    private func reloadFocusedBrowser() {
        Task {
            await AppEnvironment.phaseZero.reloadFocusedBrowser()
        }
    }

    @objc
    private func goBackInFocusedBrowser() {
        Task {
            await AppEnvironment.phaseZero.goBackInFocusedBrowser()
        }
    }

    @objc
    private func goForwardInFocusedBrowser() {
        Task {
            await AppEnvironment.phaseZero.goForwardInFocusedBrowser()
        }
    }

    @objc
    private func openVNC() {
        Task {
            await AppEnvironment.phaseZero.openWindow(.vnc)
            await AppEnvironment.phaseZero.setActiveWorkMode(.vnc)
            await AppEnvironment.phaseZero.registerControlInput("Open VNC window")
        }
    }

    @objc
    private func toggleMaximizeFocusedWindow() {
        Task {
            await AppEnvironment.phaseZero.toggleMaximizeFocusedWindow()
        }
    }

    @objc
    private func inputCaptureModeChanged() {
        let mode: PhaseZeroInputCaptureMode
        switch inputCaptureControl.selectedSegmentIndex {
        case 1:
            mode = .terminal
        case 2:
            mode = .vnc
        default:
            mode = .automatic
        }

        Task {
            await AppEnvironment.phaseZero.setInputCaptureMode(mode)
        }
    }

    @objc
    private func setCaptureAutomatic() {
        inputCaptureControl.selectedSegmentIndex = 0
        inputCaptureModeChanged()
    }

    @objc
    private func setCaptureTerminal() {
        inputCaptureControl.selectedSegmentIndex = 1
        inputCaptureModeChanged()
    }

    @objc
    private func setCaptureVNC() {
        inputCaptureControl.selectedSegmentIndex = 2
        inputCaptureModeChanged()
    }

    @objc
    private func workModeChanged() {
        let mode: PhaseZeroWorkMode
        switch workModeControl.selectedSegmentIndex {
        case 1:
            mode = .vnc
        case 2:
            mode = .browser
        default:
            mode = .ssh
        }

        Task {
            await AppEnvironment.phaseZero.setActiveWorkMode(mode)
        }
    }

    @objc
    private func toggleSoftControlModifier() {
        softControlModifierLatched.toggle()
        updateSoftModifierUI()
    }

    @objc
    private func toggleSoftAlternateModifier() {
        softAlternateModifierLatched.toggle()
        updateSoftModifierUI()
    }

    @objc
    private func toggleMiniDockCollapsed() {
        isMiniDockCollapsed.toggle()
        applyMiniDockCollapsedState()
    }

    @objc
    private func softKeyboardPresetChanged() {
        applySoftKeyboardPresetUI()
        let presetTitle = softKeyboardPresetControl.selectedSegmentIndex == 1 ? "VNC" : "Terminal"
        Task {
            await AppEnvironment.phaseZero.registerControlInput("Soft keyboard preset: \(presetTitle)")
        }
    }

    @objc
    private func apply1080pDisplayPreset() {
        displayWidthField.text = "1920"
        displayHeightField.text = "1080"
        displayScaleField.text = "1.00"
        applyDisplayProfileOverride()
    }

    @objc
    private func applyDisplayProfileOverride() {
        let width = Double(displayWidthField.text ?? "") ?? 0
        let height = Double(displayHeightField.text ?? "") ?? 0
        let scale = Double(displayScaleField.text ?? "") ?? 0

        guard width > 0, height > 0, scale > 0 else {
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Display override skipped: width/height/scale must be > 0")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.overrideDisplayProfile(width: width, height: height, scale: scale)
        }
    }

    @objc
    private func fitDisplayToExternalScene() {
        Task {
            await AppEnvironment.phaseZero.fitDisplayProfileToExternalScene()
        }
    }

    private func updateSoftModifierUI() {
        let active: [String] = [
            softControlModifierLatched ? "Ctrl" : nil,
            softAlternateModifierLatched ? "Alt" : nil
        ].compactMap { $0 }

        softModifierStatusLabel.text = "Modifiers: " + (active.isEmpty ? "none" : active.joined(separator: " + "))
        softControlButton.configuration?.baseBackgroundColor = softControlModifierLatched ? .systemBlue : nil
        softControlButton.configuration?.baseForegroundColor = softControlModifierLatched ? .white : nil
        softAlternateButton.configuration?.baseBackgroundColor = softAlternateModifierLatched ? .systemBlue : nil
        softAlternateButton.configuration?.baseForegroundColor = softAlternateModifierLatched ? .white : nil
    }

    private func applySoftKeyboardPresetUI() {
        let isVNC = softKeyboardPresetControl.selectedSegmentIndex == 1
        terminalDockStack.isHidden = isVNC
        vncDockStack.isHidden = !isVNC
    }

    private func applyMiniDockCollapsedState() {
        miniDockContentStack.isHidden = isMiniDockCollapsed
        miniDockExpandedWidthConstraint?.isActive = !isMiniDockCollapsed
        miniDockCollapsedWidthConstraint?.isActive = isMiniDockCollapsed
        miniDockToggleButton.configuration?.title = isMiniDockCollapsed ? "⌨︎" : "×"
    }

    private func sendSoftKeyPayload(
        _ payload: String,
        description: String,
        registerEvent: Bool = true,
        applyLatchedModifiers: Bool = true
    ) {
        let routedPayload = applyLatchedModifiers ? applyLatchedSoftModifiers(to: payload) : payload
        let routing = keyboardRouting(for: latestSnapshot)

        Task {
            if routing.routeToTerminal {
                await AppEnvironment.phaseZero.sendInputToFocusedTerminal(routedPayload)
                if registerEvent {
                    await AppEnvironment.phaseZero.registerControlInput("Soft key: \(description) -> Terminal")
                }
                return
            }

            if routing.routeToVNC {
                await AppEnvironment.phaseZero.sendInputToFocusedVNC(routedPayload)
                if registerEvent {
                    await AppEnvironment.phaseZero.registerControlInput("Soft key: \(description) -> VNC")
                }
                return
            }

            if registerEvent {
                await AppEnvironment.phaseZero.registerControlInput("Soft key ignored: no Terminal/VNC capture target")
            }
        }
    }

    private func applyLatchedSoftModifiers(to payload: String) -> String {
        var result = payload

        if softControlModifierLatched,
           payload.count == 1,
           let scalar = payload.unicodeScalars.first {
            let value = scalar.value
            if value >= 0x61 && value <= 0x7A,
               let controlCode = UnicodeScalar(value - 0x60) {
                result = String(controlCode)
            } else if value >= 0x41 && value <= 0x5A,
                      let controlCode = UnicodeScalar(value - 0x40) {
                result = String(controlCode)
            }
        }

        if softAlternateModifierLatched {
            result = "\u{001B}" + result
        }

        return result
    }

    private func functionKeySequence(index: Int) -> String {
        switch index {
        case 1:
            return "\u{001B}OP"
        case 2:
            return "\u{001B}OQ"
        case 3:
            return "\u{001B}OR"
        case 4:
            return "\u{001B}OS"
        case 5:
            return "\u{001B}[15~"
        case 6:
            return "\u{001B}[17~"
        case 7:
            return "\u{001B}[18~"
        case 8:
            return "\u{001B}[19~"
        case 9:
            return "\u{001B}[20~"
        case 10:
            return "\u{001B}[21~"
        case 11:
            return "\u{001B}[23~"
        case 12:
            return "\u{001B}[24~"
        default:
            return ""
        }
    }

    @objc
    private func handleSoftRepeatTouchDown(_ sender: SoftRepeatKeyButton) {
        stopSoftRepeat()

        activeSoftRepeatButton = sender
        sendSoftKeyPayload(sender.payload, description: sender.payloadDescription)

        let delayWorkItem = DispatchWorkItem { [weak self, weak sender] in
            guard let self, let sender else {
                return
            }

            self.softRepeatTimer?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self, weak sender] _ in
                guard let self, let sender, self.activeSoftRepeatButton === sender else {
                    return
                }
                self.sendSoftKeyPayload(
                    sender.payload,
                    description: sender.payloadDescription,
                    registerEvent: false,
                    applyLatchedModifiers: true
                )
            }
            self.softRepeatTimer = timer
        }

        softRepeatDelayWorkItem = delayWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: delayWorkItem)
    }

    @objc
    private func handleSoftRepeatTouchUp(_ sender: SoftRepeatKeyButton) {
        stopSoftRepeat()
    }

    private func stopSoftRepeat() {
        softRepeatDelayWorkItem?.cancel()
        softRepeatDelayWorkItem = nil
        softRepeatTimer?.invalidate()
        softRepeatTimer = nil
        activeSoftRepeatButton = nil
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTouchInsideControlHierarchy(touch.view)
    }

    private func isTouchInsideControlHierarchy(_ view: UIView?) -> Bool {
        var current = view
        while let node = current {
            if node is UIControl {
                return true
            }
            current = node.superview
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case commandField:
            sendCommandToTerminal()
        case passwordField:
            connectSSH()
        case vncInputField:
            sendTextToVNC()
        case vncPasswordField:
            connectVNC()
        case browserURLField:
            navigateFocusedBrowser()
        case newFolderField:
            createFolderInFiles()
        case renameEntryField:
            renameSelectedFilesEntry()
        case displayWidthField, displayHeightField, displayScaleField:
            applyDisplayProfileOverride()
        default:
            textField.resignFirstResponder()
        }

        return true
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if isAwaitingFilesExport {
            isAwaitingFilesExport = false
            Task {
                await AppEnvironment.phaseZero.registerControlInput("Files export completed")
            }
            return
        }

        Task {
            await AppEnvironment.phaseZero.importIntoFocusedFiles(from: urls)
            await AppEnvironment.phaseZero.registerControlInput("Files import completed")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let wasExport = isAwaitingFilesExport
        isAwaitingFilesExport = false

        Task {
            await AppEnvironment.phaseZero.registerControlInput(
                wasExport ? "Files export cancelled" : "Files import cancelled"
            )
        }
    }

    private var routesHardwareKeyboardToTerminal: Bool {
        keyboardRouting(for: latestSnapshot).routeToTerminal
    }

    private var routesHardwareKeyboardToVNC: Bool {
        keyboardRouting(for: latestSnapshot).routeToVNC
    }

    private var routesPointerToVNC: Bool {
        guard let snapshot = latestSnapshot else {
            return false
        }

        switch snapshot.inputCaptureMode {
        case .automatic:
            guard let vncWindow = focusedVNCWindow(snapshot: snapshot),
                  let vncState = vncWindow.vncState else {
                return false
            }
            return vncState.sessionState == .connected
        case .terminal:
            return false
        case .vnc:
            guard let vncWindow = snapshot.windows.last(where: { $0.kind == .vnc }),
                  let vncState = vncWindow.vncState else {
                return false
            }
            return vncState.sessionState == .connected
        }
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

    private func makeVNCRequest() -> PhaseZeroVNCConnectionRequest? {
        let host = vncHostField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = vncPasswordField.text ?? ""
        let port = Int(vncPortField.text ?? "") ?? 5900

        guard !host.isEmpty else {
            return nil
        }

        let qualityPreset: PhaseZeroVNCQualityPreset
        switch vncQualityControl.selectedSegmentIndex {
        case 0:
            qualityPreset = .low
        case 2:
            qualityPreset = .high
        default:
            qualityPreset = .balanced
        }

        return PhaseZeroVNCConnectionRequest(
            host: host,
            port: port,
            password: password,
            qualityPreset: qualityPreset,
            isTrackpadModeEnabled: vncTrackpadSwitch.isOn
        )
    }

    private func normalizedBrowserAddress(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: candidate) == nil ? nil : candidate
    }

    private func isAllowedBrowserAddress(_ address: String) -> Bool {
        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private func setBrowserAddressValidationState(isValid: Bool) {
        browserURLField.textColor = isValid ? .label : .systemRed
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

    private func focusedWindow(snapshot: PhaseZeroSnapshot?) -> PhaseZeroWindow? {
        guard let snapshot else {
            return nil
        }

        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID }) {
            return focusedWindow
        }

        return snapshot.windows.last
    }

    private func keyboardRouting(for snapshot: PhaseZeroSnapshot?) -> RoutedKeyboardInput {
        guard let snapshot else {
            return RoutedKeyboardInput(routeToTerminal: false, routeToVNC: false)
        }

        let routingWindow: PhaseZeroWindow?
        switch snapshot.inputCaptureMode {
        case .automatic:
            routingWindow = focusedWindow(snapshot: snapshot)
        case .terminal:
            routingWindow = focusedTerminalWindow(snapshot: snapshot)
        case .vnc:
            routingWindow = focusedVNCWindow(snapshot: snapshot)
        }

        return InputRouter().routeKeyboardInput(
            focusedWindow: routingWindow,
            captureMode: snapshot.inputCaptureMode
        )
    }

    private func inputCaptureStatusText(snapshot: PhaseZeroSnapshot) -> String {
        let routing = keyboardRouting(for: snapshot)
        let mode = snapshot.inputCaptureMode.rawValue.capitalized
        let workMode = snapshot.activeWorkMode.rawValue.uppercased()

        let targetWindow: PhaseZeroWindow?
        switch snapshot.inputCaptureMode {
        case .automatic:
            targetWindow = focusedWindow(snapshot: snapshot)
        case .terminal:
            targetWindow = focusedTerminalWindow(snapshot: snapshot)
        case .vnc:
            targetWindow = focusedVNCWindow(snapshot: snapshot)
        }

        let target = targetWindow?.title ?? "None"
        let keyboardDestination: String
        if routing.routeToVNC {
            keyboardDestination = "VNC"
        } else if routing.routeToTerminal {
            keyboardDestination = "Terminal"
        } else {
            keyboardDestination = "Local only"
        }

        return "Mode: \(workMode) • Input capture: \(mode) • Target: \(target) • Keyboard: \(keyboardDestination)"
    }

    private func focusedFilesWindow(snapshot: PhaseZeroSnapshot?) -> PhaseZeroWindow? {
        guard let snapshot else {
            return nil
        }

        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID && $0.kind == .files }) {
            return focusedWindow
        }

        return snapshot.windows.last(where: { $0.kind == .files })
    }

    private func focusedBrowserWindow(snapshot: PhaseZeroSnapshot?) -> PhaseZeroWindow? {
        guard let snapshot else {
            return nil
        }

        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID && $0.kind == .browser }) {
            return focusedWindow
        }

        return snapshot.windows.last(where: { $0.kind == .browser })
    }

    private func focusedVNCWindow(snapshot: PhaseZeroSnapshot?) -> PhaseZeroWindow? {
        guard let snapshot else {
            return nil
        }

        if let focusedWindowID = snapshot.focusedWindowID,
           let focusedWindow = snapshot.windows.first(where: { $0.id == focusedWindowID && $0.kind == .vnc }) {
            return focusedWindow
        }

        return snapshot.windows.last(where: { $0.kind == .vnc })
    }

    private func terminalStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let terminalWindow = focusedTerminalWindow(snapshot: snapshot),
              let terminalState = terminalWindow.terminalState else {
            return "Terminal: no terminal window selected"
        }

        return """
        Terminal: \(terminalState.connectionTitle)
        Screen: \(terminalState.screenTitle ?? "none")
        State: \(terminalState.sessionState.rawValue.capitalized)
        Status: \(terminalState.statusMessage)
        Grid: \(terminalState.columns) x \(terminalState.rows)
        Selection: \(terminalSelectionSummary(terminalState.selection))
        """
    }

    private func terminalSelectionSummary(_ selection: PhaseZeroTerminalSelection?) -> String {
        guard let selection else {
            return "none"
        }

        let normalized = selection.normalized
        return "r\(normalized.start.row):c\(normalized.start.column) -> r\(normalized.end.row):c\(normalized.end.column)"
    }

    private func terminalPreview(snapshot: PhaseZeroSnapshot) -> String {
        guard let terminalState = focusedTerminalWindow(snapshot: snapshot)?.terminalState else {
            return "No terminal output yet."
        }

        let lines = terminalState.buffer.renderedViewportLines(insertingCursor: terminalState.sessionState == .connected)
        return lines.suffix(10).joined(separator: "\n")
    }

    private func filesStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let filesState = focusedFilesWindow(snapshot: snapshot)?.filesState else {
            return "Files: no files window selected"
        }

        let selectedName = filesState.selectedEntry?.name ?? "none"
        return """
        Workspace: \(filesState.workspaceName)
        Path: \(filesState.currentPath)
        Status: \(filesState.statusMessage)
        Selected: \(selectedName)
        """
    }

    private func filesPreview(snapshot: PhaseZeroSnapshot) -> String {
        focusedFilesWindow(snapshot: snapshot)?.filesState?.previewText ?? "No files window selected."
    }

    private func browserStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let browserState = focusedBrowserWindow(snapshot: snapshot)?.browserState else {
            return "Browser: no browser window selected"
        }

        let current = browserState.currentURLString ?? browserState.homeURLString
        return """
        URL: \(current)
        Title: \(browserState.pageTitle ?? "untitled")
        Status: \(browserState.statusMessage)
        Loading: \(browserState.isLoading ? "yes" : "no")
        Back/Forward: \(browserState.canGoBack ? "yes" : "no") / \(browserState.canGoForward ? "yes" : "no")
        """
    }

    private func browserPreview(snapshot: PhaseZeroSnapshot) -> String {
        guard let browserState = focusedBrowserWindow(snapshot: snapshot)?.browserState else {
            return "No browser window selected."
        }

        let events = browserState.recentEvents.suffix(10)
        if events.isEmpty {
            return "No browser events yet."
        }

        return events.map { "• \($0)" }.joined(separator: "\n")
    }

    private func vncStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let vncState = focusedVNCWindow(snapshot: snapshot)?.vncState else {
            return "VNC: no VNC window selected"
        }

        let activeButtons = vncState.activePointerButtons.isEmpty ? "none" : vncState.activePointerButtons.joined(separator: ", ")
        let lastEvent = vncState.recentEvents.last ?? "none"

        return """
        Remote: \(vncState.connectionTitle)
        State: \(vncState.sessionState.rawValue.capitalized)
        Status: \(vncState.statusMessage)
        Last Event: \(lastEvent)
        Quality: \(vncState.qualityPreset)
        Pointer: x \(String(format: "%.2f", vncState.remotePointer.x)), y \(String(format: "%.2f", vncState.remotePointer.y))
        Active Buttons: \(activeButtons)
        Bells: \(vncState.bellCount)
        Remote Clipboard: \((vncState.remoteClipboardText?.isEmpty == false) ? "available" : "empty")
        """
    }

    private func vncPreview(snapshot: PhaseZeroSnapshot) -> String {
        guard let vncState = focusedVNCWindow(snapshot: snapshot)?.vncState else {
            return "No VNC window selected."
        }

        return vncState.frame.renderedText
    }

    private func updateVNCDragButton(snapshot: PhaseZeroSnapshot) {
        let isDragging = isVNCPrimaryDragActive(snapshot: snapshot)
        vncDragButton.configuration?.title = isDragging ? "End Drag" : "Start Drag"
        vncDragButton.configuration?.baseForegroundColor = isDragging ? .systemRed : nil
    }

    private func isVNCPrimaryDragActive(snapshot: PhaseZeroSnapshot?) -> Bool {
        guard let vncState = focusedVNCWindow(snapshot: snapshot)?.vncState else {
            return false
        }

        return vncState.activePointerButtons.contains("primary")
    }

    private func refreshFilesEntries(snapshot: PhaseZeroSnapshot) {
        filesEntriesStack.arrangedSubviews.forEach {
            filesEntriesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let filesState = focusedFilesWindow(snapshot: snapshot)?.filesState else {
            return
        }

        let entries = Array(filesState.entries.prefix(8))
        for entry in entries {
            let button = UIButton(type: .system)
            button.configuration = .plain()
            let prefix = entry.kind == .directory ? "[DIR]" : "[FILE]"
            let marker = entry.id == filesState.selectedEntryID ? "•" : " "
            button.configuration?.title = "\(marker) \(prefix) \(entry.name)"
            button.contentHorizontalAlignment = .leading
            button.addAction(
                UIAction { [weak self] _ in
                    self?.selectFilesEntry(id: entry.id)
                },
                for: .touchUpInside
            )
            filesEntriesStack.addArrangedSubview(button)
        }

        if filesState.entries.count > entries.count {
            let moreLabel = UILabel()
            moreLabel.font = .preferredFont(forTextStyle: .caption1)
            moreLabel.textColor = .secondaryLabel
            moreLabel.numberOfLines = 0
            moreLabel.text = "Showing first \(entries.count) of \(filesState.entries.count) items."
            filesEntriesStack.addArrangedSubview(moreLabel)
        }
    }

    private func selectFilesEntry(id: String) {
        Task {
            await AppEnvironment.phaseZero.selectFocusedFilesEntry(id: id)
            await AppEnvironment.phaseZero.registerControlInput("Files select entry")
        }
    }

    private func routedKeyboardInput(for key: UIKey) -> String? {
        if key.modifierFlags.contains(.command) {
            return nil
        }

        let effectiveControl = key.modifierFlags.contains(.control) || softControlModifierLatched
        let effectiveAlternate = key.modifierFlags.contains(.alternate) || softAlternateModifierLatched

        if effectiveControl,
           let scalar = key.charactersIgnoringModifiers.lowercased().unicodeScalars.first {
            let value = scalar.value
            if value >= 0x61 && value <= 0x7A,
               let controlCode = UnicodeScalar(value - 0x60) {
                let payload = String(controlCode)
                return effectiveAlternate ? "\u{001B}" + payload : payload
            }
        }

        switch key.keyCode {
        case .keyboardEscape:
            return "\u{001B}"
        case .keyboardReturnOrEnter:
            return "\n"
        case .keyboardDeleteOrBackspace:
            return "\u{7F}"
        case .keyboardDeleteForward:
            return "\u{001B}[3~"
        case .keyboardTab:
            return "\t"
        case .keyboardHome:
            return "\u{001B}[H"
        case .keyboardEnd:
            return "\u{001B}[F"
        case .keyboardPageUp:
            return "\u{001B}[5~"
        case .keyboardPageDown:
            return "\u{001B}[6~"
        case .keyboardUpArrow:
            return "\u{001B}[A"
        case .keyboardDownArrow:
            return "\u{001B}[B"
        case .keyboardRightArrow:
            return "\u{001B}[C"
        case .keyboardLeftArrow:
            return "\u{001B}[D"
        case .keyboardF1:
            return "\u{001B}OP"
        case .keyboardF2:
            return "\u{001B}OQ"
        case .keyboardF3:
            return "\u{001B}OR"
        case .keyboardF4:
            return "\u{001B}OS"
        case .keyboardF5:
            return "\u{001B}[15~"
        case .keyboardF6:
            return "\u{001B}[17~"
        case .keyboardF7:
            return "\u{001B}[18~"
        case .keyboardF8:
            return "\u{001B}[19~"
        case .keyboardF9:
            return "\u{001B}[20~"
        case .keyboardF10:
            return "\u{001B}[21~"
        case .keyboardF11:
            return "\u{001B}[23~"
        case .keyboardF12:
            return "\u{001B}[24~"
        default:
            let raw = key.characters.isEmpty ? key.charactersIgnoringModifiers : key.characters
            guard !raw.isEmpty else {
                return nil
            }

            if effectiveAlternate {
                return "\u{001B}" + raw
            }

            return raw
        }
    }

    private func moveCursor(deltaX: Double, deltaY: Double, description: String) {
        let surfaceSize = CGSize(
            width: max(trackpadView.bounds.width, 1),
            height: max(trackpadView.bounds.height, 1)
        )
        let translation = CGPoint(
            x: deltaX * surfaceSize.width,
            y: deltaY * surfaceSize.height
        )

        Task {
            await AppEnvironment.phaseZero.handlePointerPan(
                translation: translation,
                surfaceSize: surfaceSize,
                source: .keyboard
            )
            await AppEnvironment.phaseZero.registerControlInput(description)
        }
    }
}

private final class SoftRepeatKeyButton: UIButton {
    var payload: String = ""
    var payloadDescription: String = ""
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
