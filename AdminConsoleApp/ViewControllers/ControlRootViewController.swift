import AppPlatform
import UniformTypeIdentifiers
import UIKit
import WebKit

final class ControlRootViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let summaryLabel = UILabel()
    private let statusLabel = UILabel()
    private let focusedLabel = UILabel()
    private let cursorLabel = UILabel()
    private let inputLabel = UILabel()
    private let terminalStatusLabel = UILabel()
    private let terminalPreviewView = UITextView()
    private let filesStatusLabel = UILabel()
    private let filesPreviewView = UITextView()
    private let vncStatusLabel = UILabel()
    private let vncPreviewView = UITextView()
    private let filesEntriesStack = UIStackView()
    private let newFolderField = UITextField()
    private let renameEntryField = UITextField()
    private let trackpadView = UIView()
    private let trackpadCursor = UIView()
    private let keyboardHintLabel = UILabel()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let commandField = UITextField()
    private let vncHostField = UITextField()
    private let vncPortField = UITextField()
    private let vncPasswordField = UITextField()
    private let vncInputField = UITextField()
    private let vncQualityControl = UISegmentedControl(items: ["Low", "Balanced", "High"])
    private let vncTrackpadSwitch = UISwitch()
    private let vncDragButton = UIButton(type: .system)
    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?
    private var isAwaitingFilesExport = false

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

        [statusLabel, focusedLabel, cursorLabel, inputLabel, terminalStatusLabel, filesStatusLabel, vncStatusLabel].forEach { label in
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
        Cmd+V Paste clipboard to terminal
        Arrow keys move cursor unless terminal or VNC focus is active
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

        let infoCard = makeCard(
            arrangedSubviews: [
                summaryLabel,
                statusLabel,
                focusedLabel,
                cursorLabel,
                inputLabel,
                terminalStatusLabel,
                terminalPreviewView
            ]
        )
        let trackpadCard = makeCard(arrangedSubviews: [trackpadView, keyboardHintLabel])
        let actionsCard = makeCard(arrangedSubviews: [makeButtonsRow()])
        let sshCard = makeCard(arrangedSubviews: [makeSSHControls()])
        let filesCard = makeCard(arrangedSubviews: [makeFilesControls()])
        let vncCard = makeCard(arrangedSubviews: [makeVNCControls()])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18

        [infoCard, trackpadCard, actionsCard, sshCard, filesCard, vncCard].forEach(stackView.addArrangedSubview)
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
            makeKeyCommand("4", modifiers: .command, action: #selector(openVNC), title: "Open VNC"),
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
               let terminalInput = terminalInput(for: key) {
                Task {
                    await AppEnvironment.phaseZero.sendInputToFocusedTerminal(terminalInput)
                }
                return
            }

            if routesHardwareKeyboardToVNC,
               let vncInput = terminalInput(for: key) {
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
        terminalPreviewView.text = terminalPreview(snapshot: snapshot)
        filesStatusLabel.text = filesStatusText(snapshot: snapshot)
        filesPreviewView.text = filesPreview(snapshot: snapshot)
        vncStatusLabel.text = vncStatusText(snapshot: snapshot)
        vncPreviewView.text = vncPreview(snapshot: snapshot)
        refreshFilesEntries(snapshot: snapshot)
        updateVNCDragButton(snapshot: snapshot)

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
        let deltaX = Double(translation.x / max(trackpadView.bounds.width, 1)) * 0.6
        let deltaY = Double(translation.y / max(trackpadView.bounds.height, 1)) * 0.6

        gesture.setTranslation(.zero, in: trackpadView)

        Task {
            await AppEnvironment.phaseZero.moveCursor(deltaX: deltaX, deltaY: deltaY)
            if self.routesPointerToVNC {
                await AppEnvironment.phaseZero.movePointerInFocusedVNC(deltaX: deltaX, deltaY: deltaY)
            }
            await AppEnvironment.phaseZero.registerControlInput("Trackpad pan")
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
        case vncInputField:
            sendTextToVNC()
        case vncPasswordField:
            connectVNC()
        case newFolderField:
            createFolderInFiles()
        case renameEntryField:
            renameSelectedFilesEntry()
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
        guard let terminalWindow = focusedTerminalWindow(snapshot: latestSnapshot),
              let terminalState = terminalWindow.terminalState else {
            return false
        }

        return terminalState.sessionState == .connected
    }

    private var routesHardwareKeyboardToVNC: Bool {
        guard let vncWindow = focusedVNCWindow(snapshot: latestSnapshot),
              let vncState = vncWindow.vncState else {
            return false
        }

        return vncState.sessionState == .connected
    }

    private var routesPointerToVNC: Bool {
        guard let vncWindow = focusedVNCWindow(snapshot: latestSnapshot),
              let vncState = vncWindow.vncState else {
            return false
        }

        return vncState.sessionState == .connected
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

    private func vncStatusText(snapshot: PhaseZeroSnapshot) -> String {
        guard let vncState = focusedVNCWindow(snapshot: snapshot)?.vncState else {
            return "VNC: no VNC window selected"
        }

        let activeButtons = vncState.activePointerButtons.isEmpty ? "none" : vncState.activePointerButtons.joined(separator: ", ")

        return """
        Remote: \(vncState.connectionTitle)
        State: \(vncState.sessionState.rawValue.capitalized)
        Status: \(vncState.statusMessage)
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
