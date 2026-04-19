import UIKit

@MainActor
final class ControlRootViewController: UIViewController, UITextFieldDelegate {
    private enum Mode: Int {
        case ssh = 0
        case vnc = 1
        case browser = 2
    }

    private struct ParsedEndpoint {
        var host: String
        var port: Int?
        var username: String?
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let modeControl = UISegmentedControl(items: ["SSH", "VNC", "Browser"])
    private let mirrorStatusLabel = UILabel()

    private let sshCard = UIView()
    private let sshHostField = UITextField()
    private let sshPortField = UITextField()
    private let sshUserField = UITextField()
    private let sshPasswordField = UITextField()
    private let sshStatusLabel = UILabel()
    private let sshConnectButton = UIButton(type: .system)
    private let sshDisconnectButton = UIButton(type: .system)
    private let sshOpenTerminalButton = UIButton(type: .system)

    private let vncCard = UIView()
    private let vncHostField = UITextField()
    private let vncPortField = UITextField()
    private let vncPasswordField = UITextField()
    private let vncStatusLabel = UILabel()
    private let vncConnectButton = UIButton(type: .system)
    private let vncDisconnectButton = UIButton(type: .system)

    private let browserCard = UIView()
    private let browserURLField = UITextField()
    private let browserStatusLabel = UILabel()
    private let browserOpenButton = UIButton(type: .system)

    private var updatesTask: Task<Void, Never>?
    private var latestSnapshot: PhaseZeroSnapshot?
    private var sshConnectTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Connections"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = UIColor.systemBackground
        setupUI()
        startUpdates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sshConnectTask?.cancel()
        sshConnectTask = nil
    }

    deinit {
        updatesTask?.cancel()
        sshConnectTask?.cancel()
    }

    private func setupUI() {
        modeControl.selectedSegmentIndex = Mode.ssh.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        mirrorStatusLabel.font = .preferredFont(forTextStyle: .subheadline)
        mirrorStatusLabel.textColor = .secondaryLabel
        mirrorStatusLabel.numberOfLines = 0

        configureField(sshHostField, placeholder: "Host or ssh://user@host:port")
        configureField(sshPortField, placeholder: "22", keyboardType: .numberPad)
        configureField(sshUserField, placeholder: "Username")
        configureField(sshPasswordField, placeholder: "Password")
        sshPasswordField.isSecureTextEntry = true
        sshStatusLabel.font = .preferredFont(forTextStyle: .footnote)
        sshStatusLabel.numberOfLines = 0
        sshStatusLabel.textColor = .secondaryLabel

        sshConnectButton.configuration = .filled()
        sshConnectButton.configuration?.title = "Connect"
        sshConnectButton.addTarget(self, action: #selector(connectSSH), for: .touchUpInside)
        sshDisconnectButton.configuration = .tinted()
        sshDisconnectButton.configuration?.title = "Disconnect"
        sshDisconnectButton.addTarget(self, action: #selector(disconnectSSH), for: .touchUpInside)
        sshOpenTerminalButton.configuration = .plain()
        sshOpenTerminalButton.configuration?.title = "Open Terminal"
        sshOpenTerminalButton.addTarget(self, action: #selector(openTerminalSession), for: .touchUpInside)

        let sshContent = makeVertical([
            makeSectionTitle("SSH Session"),
            sshStatusLabel,
            makeRow([sshHostField]),
            makeRow([sshPortField, sshUserField]),
            makeRow([sshPasswordField]),
            makeRow([sshConnectButton, sshDisconnectButton]),
            sshOpenTerminalButton
        ])
        embed(sshContent, in: sshCard)

        configureField(vncHostField, placeholder: "Host or vnc://host:port")
        configureField(vncPortField, placeholder: "5900", keyboardType: .numberPad)
        configureField(vncPasswordField, placeholder: "Password")
        vncPasswordField.isSecureTextEntry = true
        vncStatusLabel.font = .preferredFont(forTextStyle: .footnote)
        vncStatusLabel.numberOfLines = 0
        vncStatusLabel.textColor = .secondaryLabel
        vncConnectButton.configuration = .filled()
        vncConnectButton.configuration?.title = "Connect"
        vncConnectButton.addTarget(self, action: #selector(connectVNC), for: .touchUpInside)
        vncDisconnectButton.configuration = .tinted()
        vncDisconnectButton.configuration?.title = "Disconnect"
        vncDisconnectButton.addTarget(self, action: #selector(disconnectVNC), for: .touchUpInside)
        let vncContent = makeVertical([
            makeSectionTitle("VNC Session"),
            vncStatusLabel,
            makeRow([vncHostField]),
            makeRow([vncPortField, vncPasswordField]),
            makeRow([vncConnectButton, vncDisconnectButton])
        ])
        embed(vncContent, in: vncCard)

        configureField(browserURLField, placeholder: "https://example.com", keyboardType: .URL, returnKeyType: .go)
        browserStatusLabel.font = .preferredFont(forTextStyle: .footnote)
        browserStatusLabel.numberOfLines = 0
        browserStatusLabel.textColor = .secondaryLabel
        browserOpenButton.configuration = .filled()
        browserOpenButton.configuration?.title = "Open URL"
        browserOpenButton.addTarget(self, action: #selector(openBrowser), for: .touchUpInside)
        let browserContent = makeVertical([
            makeSectionTitle("Browser Session"),
            browserStatusLabel,
            makeRow([browserURLField]),
            browserOpenButton
        ])
        embed(browserContent, in: browserCard)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12

        stackView.addArrangedSubview(modeControl)
        stackView.addArrangedSubview(mirrorStatusLabel)
        stackView.addArrangedSubview(sshCard)
        stackView.addArrangedSubview(vncCard)
        stackView.addArrangedSubview(browserCard)

        scrollView.addSubview(stackView)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24)
        ])

        applyModeUI()
    }

    private func startUpdates() {
        updatesTask = Task { [weak self] in
            guard let self else { return }
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
        let selectedMode = selectedModeFromSnapshot(snapshot)
        if modeControl.selectedSegmentIndex != selectedMode.rawValue {
            modeControl.selectedSegmentIndex = selectedMode.rawValue
            applyModeUI()
        }

        mirrorStatusLabel.text = """
        Active mode: \(snapshot.activeWorkMode.rawValue.uppercased())
        Mirror mode: \(mirrorModeText(snapshot.mirrorMode))
        External display: \(snapshot.isExternalDisplayConnected ? "connected" : "not connected")
        Mirror target: \(mirroredTargetText(snapshot: snapshot))
        """

        if let terminal = focusedTerminalState(snapshot) {
            sshStatusLabel.text = "State: \(terminal.sessionState.rawValue.capitalized) • \(terminal.statusMessage)"
            sshConnectButton.isEnabled = terminal.sessionState != .connecting
            sshDisconnectButton.isEnabled = terminal.sessionState == .connecting || terminal.sessionState == .connected
        } else {
            sshStatusLabel.text = "State: Idle • Ready for SSH session"
            sshDisconnectButton.isEnabled = false
        }

        if let vnc = focusedVNCState(snapshot) {
            vncStatusLabel.text = "State: \(vnc.sessionState.rawValue.capitalized) • \(vnc.statusMessage)"
            vncDisconnectButton.isEnabled = vnc.sessionState == .connected || vnc.sessionState == .connecting
        } else {
            vncStatusLabel.text = "State: Idle • Ready for VNC session"
            vncDisconnectButton.isEnabled = false
        }

        if let browser = focusedBrowserState(snapshot) {
            browserStatusLabel.text = "\(browser.statusMessage)\n\(browser.currentURLString ?? browser.homeURLString)"
        } else {
            browserStatusLabel.text = "No active browser session."
        }
    }

    @objc
    private func modeChanged() {
        applyModeUI()
        let mode = currentMode()
        Task {
            switch mode {
            case .ssh:
                await AppEnvironment.phaseZero.setActiveWorkMode(.ssh)
            case .vnc:
                await AppEnvironment.phaseZero.setActiveWorkMode(.vnc)
            case .browser:
                await AppEnvironment.phaseZero.setActiveWorkMode(.browser)
            }
        }
    }

    private func applyModeUI() {
        let mode = currentMode()
        sshCard.isHidden = mode != .ssh
        vncCard.isHidden = mode != .vnc
        browserCard.isHidden = mode != .browser
    }

    private func currentMode() -> Mode {
        Mode(rawValue: modeControl.selectedSegmentIndex) ?? .ssh
    }

    @objc
    private func connectSSH() {
        view.endEditing(true)
        guard sshConnectTask == nil else { return }

        let requestResult = makeSSHRequest()
        guard let request = requestResult.request else {
            presentAlert(title: "SSH Form Error", message: requestResult.errorMessage ?? "Invalid SSH form.")
            return
        }

        sshConnectTask = Task { [weak self] in
            guard let self else { return }
            let didConnect = await AppEnvironment.phaseZero.connectFocusedTerminal(using: request)
            await MainActor.run {
                self.sshConnectTask = nil
                if didConnect {
                    self.openTerminalSession()
                } else {
                    let message = self.focusedTerminalState(self.latestSnapshot)?.statusMessage
                        ?? "Connection failed. Check host, port, credentials and network."
                    self.presentAlert(title: "SSH Connection Failed", message: message)
                }
            }
        }
    }

    @objc
    private func disconnectSSH() {
        sshConnectTask?.cancel()
        sshConnectTask = nil
        Task {
            await AppEnvironment.phaseZero.disconnectFocusedTerminal()
        }
    }

    @objc
    private func openTerminalSession() {
        navigationController?.pushViewController(SSHTerminalSessionViewController(), animated: true)
    }

    @objc
    private func connectVNC() {
        view.endEditing(true)
        let requestResult = makeVNCRequest()
        guard let request = requestResult.request else {
            presentAlert(title: "VNC Form Error", message: requestResult.errorMessage ?? "Invalid VNC form.")
            return
        }

        Task {
            let didConnect = await AppEnvironment.phaseZero.connectFocusedVNC(using: request)
            await MainActor.run {
                if !didConnect {
                    let message = self.focusedVNCState(self.latestSnapshot)?.statusMessage
                        ?? "Connection failed. Check host, port, password and network."
                    self.presentAlert(title: "VNC Connection Failed", message: message)
                }
            }
        }
    }

    @objc
    private func disconnectVNC() {
        Task {
            await AppEnvironment.phaseZero.disconnectFocusedVNC()
        }
    }

    @objc
    private func openBrowser() {
        let raw = (browserURLField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            presentAlert(title: "Browser Error", message: "Enter URL.")
            return
        }
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        guard URL(string: normalized) != nil else {
            presentAlert(title: "Browser Error", message: "Invalid URL.")
            return
        }

        Task {
            await AppEnvironment.phaseZero.setActiveWorkMode(.browser)
            await AppEnvironment.phaseZero.navigateFocusedBrowser(to: normalized)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case sshHostField, sshPortField, sshUserField, sshPasswordField:
            connectSSH()
        case vncHostField, vncPortField, vncPasswordField:
            connectVNC()
        case browserURLField:
            openBrowser()
        default:
            textField.resignFirstResponder()
        }
        return true
    }

    private func makeSSHRequest() -> (request: PhaseZeroSSHConnectionRequest?, errorMessage: String?) {
        let endpoint = parseEndpoint(rawHost: sshHostField.text ?? "", rawPort: sshPortField.text, defaultPort: 22)
        let user = (sshUserField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let username = user.isEmpty ? (endpoint.username ?? "") : user
        let password = sshPasswordField.text ?? ""

        guard !endpoint.host.isEmpty else {
            return (nil, "Host is required. Use host, host:port, or ssh://user@host:port")
        }
        guard !username.isEmpty else {
            return (nil, "Username is required.")
        }

        let profile = latestSnapshot?.displayProfile
        let width = Int((profile?.width ?? 1280) * (profile?.scale ?? 1.0))
        let height = Int((profile?.height ?? 720) * (profile?.scale ?? 1.0))
        let columns = max(80, Int((profile?.width ?? 1280) / 10))
        let rows = max(24, Int((profile?.height ?? 720) / 22))

        return (PhaseZeroSSHConnectionRequest(
            host: endpoint.host,
            port: endpoint.port ?? 22,
            username: username,
            password: password,
            columns: columns,
            rows: rows,
            pixelWidth: width,
            pixelHeight: height
        ), nil)
    }

    private func makeVNCRequest() -> (request: PhaseZeroVNCConnectionRequest?, errorMessage: String?) {
        let endpoint = parseEndpoint(rawHost: vncHostField.text ?? "", rawPort: vncPortField.text, defaultPort: 5900)
        guard !endpoint.host.isEmpty else {
            return (nil, "Host is required. Use host, host:port, or vnc://host:port")
        }
        return (PhaseZeroVNCConnectionRequest(
            host: endpoint.host,
            port: endpoint.port ?? 5900,
            password: vncPasswordField.text ?? "",
            qualityPreset: .balanced,
            isTrackpadModeEnabled: true
        ), nil)
    }

    private func parseEndpoint(rawHost: String, rawPort: String?, defaultPort: Int) -> ParsedEndpoint {
        var hostInput = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var extractedUsername: String?
        var extractedPort: Int?

        if let typedPort = Int((rawPort ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
            extractedPort = typedPort
        }

        if hostInput.contains("://"), let components = URLComponents(string: hostInput) {
            if let user = components.user, !user.isEmpty {
                extractedUsername = user
            }
            if let host = components.host, !host.isEmpty {
                hostInput = host
            }
            if extractedPort == nil, let p = components.port {
                extractedPort = p
            }
        } else {
            if let at = hostInput.lastIndex(of: "@") {
                let userPart = String(hostInput[..<at]).trimmingCharacters(in: .whitespacesAndNewlines)
                let hostPart = String(hostInput[hostInput.index(after: at)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !userPart.isEmpty { extractedUsername = userPart }
                if !hostPart.isEmpty { hostInput = hostPart }
            }
            let components = hostInput.split(separator: ":", omittingEmptySubsequences: false)
            if components.count == 2, extractedPort == nil, let p = Int(components[1]) {
                hostInput = String(components[0])
                extractedPort = p
            }
        }

        hostInput = hostInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        return ParsedEndpoint(host: hostInput, port: extractedPort ?? defaultPort, username: extractedUsername)
    }

    private func selectedModeFromSnapshot(_ snapshot: PhaseZeroSnapshot) -> Mode {
        switch snapshot.activeWorkMode {
        case .ssh: return .ssh
        case .vnc: return .vnc
        case .browser: return .browser
        }
    }

    private func mirroredTargetText(snapshot: PhaseZeroSnapshot) -> String {
        guard let window = mirroredWindow(in: snapshot) else {
            return "No window"
        }

        switch window.kind {
        case .terminal:
            let state = window.terminalState
            return "SSH \(state?.connectionTitle ?? "-") (\(state?.sessionState.rawValue ?? "idle"))"
        case .vnc:
            let state = window.vncState
            return "VNC \(state?.connectionTitle ?? "-") (\(state?.sessionState.rawValue ?? "idle"))"
        case .browser:
            let state = window.browserState
            return state?.currentURLString ?? state?.homeURLString ?? "Browser"
        case .files:
            return "Files \(window.title)"
        }
    }

    private func mirrorModeText(_ mode: PhaseZeroMirrorMode) -> String {
        switch mode {
        case .activeWorkMode:
            return "active"
        case .focusedWindow:
            return "focused"
        case .terminal:
            return "ssh"
        case .vnc:
            return "vnc"
        case .browser:
            return "browser"
        }
    }

    private func mirroredWindow(in snapshot: PhaseZeroSnapshot) -> PhaseZeroWindow? {
        switch snapshot.mirrorMode {
        case .activeWorkMode:
            return snapshot.windows.last(where: { $0.kind == snapshot.activeWorkMode.windowKind })
                ?? snapshot.windows.last
        case .focusedWindow:
            if let focusedID = snapshot.focusedWindowID,
               let focusedWindow = snapshot.windows.first(where: { $0.id == focusedID }) {
                return focusedWindow
            }
            return snapshot.windows.last
        case .terminal:
            return snapshot.windows.last(where: { $0.kind == .terminal }) ?? snapshot.windows.last
        case .vnc:
            return snapshot.windows.last(where: { $0.kind == .vnc }) ?? snapshot.windows.last
        case .browser:
            return snapshot.windows.last(where: { $0.kind == .browser }) ?? snapshot.windows.last
        }
    }

    func applyHostPreset(_ preset: TermiusHostPreset, autoConnect: Bool) {
        modeControl.selectedSegmentIndex = Mode.ssh.rawValue
        applyModeUI()

        sshHostField.text = preset.host
        sshPortField.text = String(preset.port)
        sshUserField.text = preset.username

        if autoConnect {
            connectSSH()
        }
    }

    private func focusedTerminalState(_ snapshot: PhaseZeroSnapshot?) -> PhaseZeroTerminalState? {
        guard let snapshot else { return nil }
        if let id = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.id == id && $0.kind == .terminal })?.terminalState {
            return focused
        }
        return snapshot.windows.last(where: { $0.kind == .terminal })?.terminalState
    }

    private func focusedVNCState(_ snapshot: PhaseZeroSnapshot?) -> PhaseZeroVNCState? {
        guard let snapshot else { return nil }
        if let id = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.id == id && $0.kind == .vnc })?.vncState {
            return focused
        }
        return snapshot.windows.last(where: { $0.kind == .vnc })?.vncState
    }

    private func focusedBrowserState(_ snapshot: PhaseZeroSnapshot?) -> PhaseZeroBrowserState? {
        guard let snapshot else { return nil }
        if let id = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.id == id && $0.kind == .browser })?.browserState {
            return focused
        }
        return snapshot.windows.last(where: { $0.kind == .browser })?.browserState
    }

    private func configureField(
        _ textField: UITextField,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .done
    ) {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.returnKeyType = returnKeyType
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.delegate = self
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = text
        return label
    }

    private func makeRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    private func makeVertical(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    private func embed(_ content: UIView, in card: UIView) {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.secondarySystemBackground
        card.layer.cornerRadius = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

struct TermiusHostPreset: Sendable, Equatable {
    let vaultName: String
    let title: String
    let subtitle: String
    let host: String
    let port: Int
    let username: String
}

private struct TermiusVaultSection {
    let title: String
    let hosts: [TermiusHostPreset]
}

private enum TermiusVaultCatalog {
    static let sections: [TermiusVaultSection] = [
        TermiusVaultSection(
            title: "Production",
            hosts: [
                TermiusHostPreset(
                    vaultName: "Production",
                    title: "web-eu-01",
                    subtitle: "Nginx + API",
                    host: "web-eu-01.internal",
                    port: 22,
                    username: "ops"
                ),
                TermiusHostPreset(
                    vaultName: "Production",
                    title: "db-eu-01",
                    subtitle: "PostgreSQL Primary",
                    host: "db-eu-01.internal",
                    port: 22,
                    username: "dba"
                )
            ]
        ),
        TermiusVaultSection(
            title: "Staging",
            hosts: [
                TermiusHostPreset(
                    vaultName: "Staging",
                    title: "stage-web-01",
                    subtitle: "Integration Tests",
                    host: "stage-web-01.internal",
                    port: 22,
                    username: "qa"
                ),
                TermiusHostPreset(
                    vaultName: "Staging",
                    title: "stage-bastion",
                    subtitle: "Jump Host",
                    host: "stage-bastion.internal",
                    port: 22,
                    username: "qa"
                )
            ]
        ),
        TermiusVaultSection(
            title: "Lab",
            hosts: [
                TermiusHostPreset(
                    vaultName: "Lab",
                    title: "raspi-k3s",
                    subtitle: "Edge Cluster Node",
                    host: "raspi-k3s.local",
                    port: 22,
                    username: "pi"
                ),
                TermiusHostPreset(
                    vaultName: "Lab",
                    title: "nas-storage",
                    subtitle: "Backups",
                    host: "nas-storage.local",
                    port: 22,
                    username: "backup"
                )
            ]
        )
    ]
}

@MainActor
final class TermiusRootTabBarController: UITabBarController {
    private let connectionsNavigationController = UINavigationController()
    private let connectionsController = ControlRootViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabs()
    }

    private func configureTabs() {
        let vaultsController = VaultsHomeViewController()
        vaultsController.onHostSelection = { [weak self] preset, autoConnect in
            self?.openConnection(for: preset, autoConnect: autoConnect)
        }

        let vaultsNavigationController = UINavigationController(rootViewController: vaultsController)
        vaultsNavigationController.tabBarItem = UITabBarItem(
            title: "Vaults",
            image: UIImage(systemName: "shippingbox.fill"),
            selectedImage: UIImage(systemName: "shippingbox.fill")
        )

        connectionsNavigationController.viewControllers = [connectionsController]
        connectionsNavigationController.tabBarItem = UITabBarItem(
            title: "Connections",
            image: UIImage(systemName: "bolt.horizontal.circle"),
            selectedImage: UIImage(systemName: "bolt.horizontal.circle.fill")
        )

        let profileController = ProfileHomeViewController()
        let profileNavigationController = UINavigationController(rootViewController: profileController)
        profileNavigationController.tabBarItem = UITabBarItem(
            title: "Profile",
            image: UIImage(systemName: "person.crop.circle"),
            selectedImage: UIImage(systemName: "person.crop.circle.fill")
        )

        setViewControllers(
            [vaultsNavigationController, connectionsNavigationController, profileNavigationController],
            animated: false
        )
        selectedIndex = 1
    }

    private func openConnection(for preset: TermiusHostPreset, autoConnect: Bool) {
        selectedIndex = 1
        connectionsNavigationController.popToRootViewController(animated: false)
        connectionsController.applyHostPreset(preset, autoConnect: autoConnect)
    }
}

@MainActor
final class VaultsHomeViewController: UITableViewController {
    var onHostSelection: ((TermiusHostPreset, Bool) -> Void)?

    private let sections = TermiusVaultCatalog.sections

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vaults"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HostCell")
        tableView.rowHeight = 66
        tableView.backgroundColor = UIColor.systemBackground
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].hosts.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let preset = sections[indexPath.section].hosts[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HostCell")
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = preset.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.text = "\(preset.username)@\(preset.host):\(preset.port) • \(preset.subtitle)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let preset = sections[indexPath.section].hosts[indexPath.row]
        let sheet = UIAlertController(
            title: preset.title,
            message: "\(preset.username)@\(preset.host):\(preset.port)",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(title: "Open In Connections", style: .default) { [weak self] _ in
            self?.onHostSelection?(preset, false)
        })
        sheet.addAction(UIAlertAction(title: "Connect Now", style: .default) { [weak self] _ in
            self?.onHostSelection?(preset, true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController,
           let cell = tableView.cellForRow(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }

        present(sheet, animated: true)
    }
}

@MainActor
final class ProfileHomeViewController: UIViewController {
    private let statusLabel = UILabel()
    private let mirrorModeControl = UISegmentedControl(items: ["Active", "Focused", "SSH", "VNC", "Web"])
    private let mirrorHintLabel = UILabel()
    private var updatesTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Profile"
        view.backgroundColor = .systemBackground

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel

        mirrorModeControl.selectedSegmentIndex = 0
        mirrorModeControl.addTarget(self, action: #selector(mirrorModeChanged), for: .valueChanged)

        mirrorHintLabel.font = .preferredFont(forTextStyle: .footnote)
        mirrorHintLabel.textColor = .secondaryLabel
        mirrorHintLabel.numberOfLines = 0
        mirrorHintLabel.text = "Mirror mode defines what is shown on the external monitor."

        let stack = UIStackView(arrangedSubviews: [statusLabel, mirrorModeControl, mirrorHintLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        startUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    private func startUpdates() {
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await AppEnvironment.phaseZero.startIfNeeded()
            let stream = await AppEnvironment.phaseZero.snapshots()
            for await snapshot in stream {
                await MainActor.run {
                    self.apply(snapshot: snapshot)
                }
            }
        }
    }

    private func apply(snapshot: PhaseZeroSnapshot) {
        statusLabel.text = """
        External display: \(snapshot.isExternalDisplayConnected ? "connected" : "not connected")
        Display profile: \(Int(snapshot.displayProfile.width))x\(Int(snapshot.displayProfile.height)) @ \(String(format: "%.2f", snapshot.displayProfile.scale))x
        Active mode: \(snapshot.activeWorkMode.rawValue.uppercased())
        """

        let expectedIndex = segmentIndex(for: snapshot.mirrorMode)
        if mirrorModeControl.selectedSegmentIndex != expectedIndex {
            mirrorModeControl.selectedSegmentIndex = expectedIndex
        }
    }

    @objc
    private func mirrorModeChanged() {
        let mode = mirrorMode(for: mirrorModeControl.selectedSegmentIndex)
        Task {
            await AppEnvironment.phaseZero.setMirrorMode(mode)
        }
    }

    private func mirrorMode(for selectedIndex: Int) -> PhaseZeroMirrorMode {
        switch selectedIndex {
        case 1:
            return .focusedWindow
        case 2:
            return .terminal
        case 3:
            return .vnc
        case 4:
            return .browser
        default:
            return .activeWorkMode
        }
    }

    private func segmentIndex(for mode: PhaseZeroMirrorMode) -> Int {
        switch mode {
        case .activeWorkMode:
            return 0
        case .focusedWindow:
            return 1
        case .terminal:
            return 2
        case .vnc:
            return 3
        case .browser:
            return 4
        }
    }
}
