import UIKit
import PersistenceKit

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
    private var selectedSSHHostPreset: TermiusHostPreset?

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
            if didConnect {
                await self.persistRecentHostForSuccessfulSSHConnection(request: request)
            }
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
        selectedSSHHostPreset = preset

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

    private func persistRecentHostForSuccessfulSSHConnection(request: PhaseZeroSSHConnectionRequest) async {
        let preset = selectedSSHHostPreset

        let title: String
        let subtitle: String
        let vaultName: String

        if let preset,
           preset.host.caseInsensitiveCompare(request.host) == .orderedSame,
           preset.port == request.port,
           preset.username.caseInsensitiveCompare(request.username) == .orderedSame {
            title = preset.title
            subtitle = preset.subtitle
            vaultName = preset.vaultName
        } else {
            title = request.host
            subtitle = "Manual SSH host"
            vaultName = "Personal"
        }

        await AppEnvironment.hostCatalog.recordConnection(
            host: request.host,
            port: request.port,
            username: request.username,
            title: title,
            subtitle: subtitle,
            vaultName: vaultName
        )
    }
}

struct TermiusHostPreset: Sendable, Equatable {
    let id: HostRecordID
    let vaultName: String
    let title: String
    let subtitle: String
    let host: String
    let port: Int
    let username: String
    let isFavorite: Bool

    init(record: SavedHostRecord) {
        id = record.id
        vaultName = record.vaultName
        title = record.title
        subtitle = record.subtitle
        host = record.host
        port = record.port
        username = record.username
        isFavorite = record.isFavorite
    }
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
    private var sections: [HostCatalogSection] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vaults"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addHostTapped)
        )
        tableView.rowHeight = 66
        tableView.backgroundColor = UIColor.systemBackground
        reloadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSections()
    }

    private func reloadSections() {
        Task { [weak self] in
            guard let self else { return }
            let loadedSections = await AppEnvironment.hostCatalog.sections()
            await MainActor.run {
                self.sections = loadedSections
                self.tableView.reloadData()
            }
        }
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
        let record = sections[indexPath.section].hosts[indexPath.row]
        let preset = TermiusHostPreset(record: record)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HostCell")
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = preset.isFavorite ? "★ \(preset.title)" : preset.title
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.text = "\(preset.username)@\(preset.host):\(preset.port) • \(preset.subtitle)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let record = sections[indexPath.section].hosts[indexPath.row]
        let preset = TermiusHostPreset(record: record)
        openHostDetails(for: preset)
    }

    @objc
    private func addHostTapped() {
        let editor = HostEditorViewController(mode: .create)
        editor.onSaved = { [weak self] preset in
            guard let self else { return }
            self.reloadSections()
            self.openHostDetails(for: preset)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func openHostDetails(for preset: TermiusHostPreset) {
        let details = HostDetailsViewController(preset: preset)
        details.onOpenInConnections = { [weak self] selectedPreset, autoConnect in
            self?.onHostSelection?(selectedPreset, autoConnect)
        }
        details.onHostDeleted = { [weak self] in
            self?.reloadSections()
        }
        details.onHostUpdated = { [weak self] _ in
            self?.reloadSections()
        }
        navigationController?.pushViewController(details, animated: true)
    }
}

enum HostEditorMode {
    case create
    case edit(TermiusHostPreset)
}

@MainActor
final class HostEditorViewController: UIViewController, UITextFieldDelegate {
    var onSaved: ((TermiusHostPreset) -> Void)?

    private let mode: HostEditorMode
    private let vaultField = UITextField()
    private let titleField = UITextField()
    private let subtitleField = UITextField()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let usernameField = UITextField()
    private let favoriteSwitch = UISwitch()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    init(mode: HostEditorMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = editorTitle
        setupUI()
        seedFieldsIfNeeded()
    }

    private var editorTitle: String {
        switch mode {
        case .create:
            return "New Host"
        case .edit:
            return "Edit Host"
        }
    }

    private func setupUI() {
        [vaultField, titleField, subtitleField, hostField, portField, usernameField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.delegate = self
        }

        vaultField.placeholder = "Vault (e.g. Production)"
        titleField.placeholder = "Title"
        subtitleField.placeholder = "Subtitle (optional)"
        hostField.placeholder = "Host"
        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        usernameField.placeholder = "Username"

        let favoriteLabel = UILabel()
        favoriteLabel.text = "Favorite"
        favoriteLabel.font = .preferredFont(forTextStyle: .body)

        let favoriteRow = UIStackView(arrangedSubviews: [favoriteLabel, favoriteSwitch])
        favoriteRow.axis = .horizontal
        favoriteRow.distribution = .equalSpacing

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "Fill host details and save."

        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save Host"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            vaultField,
            titleField,
            subtitleField,
            hostField,
            portField,
            usernameField,
            favoriteRow,
            statusLabel,
            saveButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func seedFieldsIfNeeded() {
        guard case .edit(let preset) = mode else {
            portField.text = "22"
            return
        }

        vaultField.text = preset.vaultName
        titleField.text = preset.title
        subtitleField.text = preset.subtitle
        hostField.text = preset.host
        portField.text = String(preset.port)
        usernameField.text = preset.username
        favoriteSwitch.isOn = preset.isFavorite
    }

    @objc
    private func saveTapped() {
        view.endEditing(true)

        let vaultName = (vaultField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (subtitleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (hostField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let username = (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int((portField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        let isFavorite = favoriteSwitch.isOn

        guard !vaultName.isEmpty, !title.isEmpty, !host.isEmpty, !username.isEmpty else {
            statusLabel.text = "Vault, title, host and username are required."
            statusLabel.textColor = .systemRed
            return
        }

        saveButton.isEnabled = false
        statusLabel.text = "Saving host..."
        statusLabel.textColor = .secondaryLabel

        Task { [weak self] in
            guard let self else { return }

            let savedRecord: SavedHostRecord?
            switch self.mode {
            case .create:
                savedRecord = await AppEnvironment.hostCatalog.createHost(
                    vaultName: vaultName,
                    title: title,
                    subtitle: subtitle,
                    host: host,
                    port: port,
                    username: username,
                    isFavorite: isFavorite
                )
            case .edit(let preset):
                savedRecord = await AppEnvironment.hostCatalog.updateHost(
                    id: preset.id,
                    vaultName: vaultName,
                    title: title,
                    subtitle: subtitle,
                    host: host,
                    port: port,
                    username: username,
                    isFavorite: isFavorite
                )
            }

            await MainActor.run {
                self.saveButton.isEnabled = true

                guard let savedRecord else {
                    self.statusLabel.text = "Unable to save host. Verify all required fields."
                    self.statusLabel.textColor = .systemRed
                    return
                }

                self.onSaved?(TermiusHostPreset(record: savedRecord))
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
        return true
    }
}

@MainActor
final class HostDetailsViewController: UIViewController {
    var onOpenInConnections: ((TermiusHostPreset, Bool) -> Void)?
    var onHostDeleted: (() -> Void)?
    var onHostUpdated: ((TermiusHostPreset) -> Void)?

    private var preset: TermiusHostPreset
    private let summaryLabel = UILabel()
    private let vaultLabel = UILabel()
    private let statusLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)

    init(preset: TermiusHostPreset) {
        self.preset = preset
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Host Details"
        setupUI()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFromStore()
    }

    private func setupUI() {
        summaryLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        summaryLabel.numberOfLines = 0
        summaryLabel.textColor = .label

        vaultLabel.font = .preferredFont(forTextStyle: .subheadline)
        vaultLabel.numberOfLines = 0
        vaultLabel.textColor = .secondaryLabel

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel

        let openButton = UIButton(type: .system)
        openButton.configuration = .filled()
        openButton.configuration?.title = "Open In Connections"
        openButton.addTarget(self, action: #selector(openInConnectionsTapped), for: .touchUpInside)

        let connectNowButton = UIButton(type: .system)
        connectNowButton.configuration = .tinted()
        connectNowButton.configuration?.title = "Connect Now"
        connectNowButton.addTarget(self, action: #selector(connectNowTapped), for: .touchUpInside)

        favoriteButton.configuration = .gray()
        favoriteButton.addTarget(self, action: #selector(toggleFavoriteTapped), for: .touchUpInside)

        let editButton = UIButton(type: .system)
        editButton.configuration = .plain()
        editButton.configuration?.title = "Edit Host"
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        let deleteButton = UIButton(type: .system)
        deleteButton.configuration = .plain()
        deleteButton.configuration?.title = "Delete Host"
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            summaryLabel,
            vaultLabel,
            statusLabel,
            openButton,
            connectNowButton,
            favoriteButton,
            editButton,
            deleteButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func render() {
        summaryLabel.text = """
        \(preset.title)
        \(preset.username)@\(preset.host):\(preset.port)
        """
        vaultLabel.text = "Vault: \(preset.vaultName) • \(preset.subtitle)"
        favoriteButton.configuration?.title = preset.isFavorite ? "Remove From Favorites" : "Add To Favorites"
        statusLabel.text = "Host id: \(preset.id.rawValue.uuidString)"
    }

    private func refreshFromStore() {
        Task { [weak self] in
            guard let self else { return }
            guard let refreshed = await AppEnvironment.hostCatalog.host(id: self.preset.id) else {
                await MainActor.run {
                    self.statusLabel.text = "Host was removed."
                    self.statusLabel.textColor = .systemRed
                }
                return
            }

            await MainActor.run {
                self.preset = TermiusHostPreset(record: refreshed)
                self.render()
            }
        }
    }

    @objc
    private func openInConnectionsTapped() {
        onOpenInConnections?(preset, false)
    }

    @objc
    private func connectNowTapped() {
        onOpenInConnections?(preset, true)
    }

    @objc
    private func toggleFavoriteTapped() {
        Task { [weak self] in
            guard let self else { return }
            guard let updated = await AppEnvironment.hostCatalog.toggleFavorite(hostID: self.preset.id) else {
                return
            }
            await MainActor.run {
                self.preset = TermiusHostPreset(record: updated)
                self.render()
                self.onHostUpdated?(self.preset)
            }
        }
    }

    @objc
    private func editTapped() {
        let editor = HostEditorViewController(mode: .edit(preset))
        editor.onSaved = { [weak self] updatedPreset in
            guard let self else { return }
            self.preset = updatedPreset
            self.render()
            self.onHostUpdated?(updatedPreset)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc
    private func deleteTapped() {
        let alert = UIAlertController(
            title: "Delete Host?",
            message: "This host will be removed from vaults, favorites, and recents.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                let deleted = await AppEnvironment.hostCatalog.deleteHost(id: self.preset.id)
                await MainActor.run {
                    if deleted {
                        self.onHostDeleted?()
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            }
        })
        present(alert, animated: true)
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
