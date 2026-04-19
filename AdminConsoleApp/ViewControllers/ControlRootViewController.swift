import ConnectionKit
import DesktopDomain
import SSHKit
import UIKit

private extension Notification.Name {
    static let rebootConnectHostRequested = Notification.Name("rebootConnectHostRequested")
}

struct RebootHost: Codable, Equatable, Identifiable {
    let id: UUID
    var vault: String
    var name: String
    var note: String
    var hostname: String
    var port: Int
    var username: String
    var isFavorite: Bool
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        vault: String,
        name: String,
        note: String,
        hostname: String,
        port: Int = 22,
        username: String,
        isFavorite: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.vault = vault
        self.name = name
        self.note = note
        self.hostname = hostname
        self.port = max(1, port)
        self.username = username
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
    }
}

private struct RebootHostStoreSnapshot: Codable {
    var hosts: [RebootHost]
    var recents: [UUID]
}

final class RebootHostStore {
    private let storageKey = "TermiusReboot.HostStore.v1"
    private(set) var hosts: [RebootHost] = []
    private(set) var recents: [UUID] = []

    init() {
        load()
        if hosts.isEmpty {
            seed()
            save()
        }
    }

    func groupedVaultNames() -> [String] {
        Array(Set(hosts.map(\.vault))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func favorites() -> [RebootHost] {
        hosts.filter(\.isFavorite).sorted(by: hostSort)
    }

    func recentHosts() -> [RebootHost] {
        let map = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0) })
        return recents.compactMap { map[$0] }
    }

    func hosts(inVault vault: String) -> [RebootHost] {
        hosts.filter { $0.vault == vault }.sorted(by: hostSort)
    }

    func host(id: UUID) -> RebootHost? {
        hosts.first(where: { $0.id == id })
    }

    @discardableResult
    func create(_ host: RebootHost) -> RebootHost {
        hosts.append(host)
        save()
        return host
    }

    @discardableResult
    func update(_ host: RebootHost) -> RebootHost {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        save()
        return host
    }

    func delete(id: UUID) {
        hosts.removeAll(where: { $0.id == id })
        recents.removeAll(where: { $0 == id })
        save()
    }

    func toggleFavorite(id: UUID) {
        guard let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[index].isFavorite.toggle()
        save()
    }

    func markConnected(id: UUID) {
        guard let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[index].lastConnectedAt = Date()
        recents.removeAll(where: { $0 == id })
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(12))
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let snapshot = try? JSONDecoder().decode(RebootHostStoreSnapshot.self, from: data) else { return }
        hosts = snapshot.hosts
        recents = snapshot.recents
    }

    private func save() {
        let snapshot = RebootHostStoreSnapshot(hosts: hosts, recents: recents)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func seed() {
        hosts = [
            RebootHost(vault: "Production", name: "web-eu-01", note: "Nginx + API", hostname: "web-eu-01.internal", username: "ops"),
            RebootHost(vault: "Production", name: "db-eu-01", note: "PostgreSQL", hostname: "db-eu-01.internal", username: "dba"),
            RebootHost(vault: "Staging", name: "stage-bastion", note: "Jump Host", hostname: "stage-bastion.internal", username: "qa")
        ]
        recents = []
    }

    private func hostSort(_ lhs: RebootHost, _ rhs: RebootHost) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

@MainActor
final class RebootAppModel {
    let hostStore = RebootHostStore()
    var selectedHostID: UUID?

    private(set) var terminalState: TerminalSurfaceState = .idle()
    private lazy var runtime: SSHTerminalRuntime = {
        SSHTerminalRuntime(windowID: WindowID(), initialState: .idle()) { [weak self] state in
            await self?.applyTerminalState(state)
        }
    }()
    private var terminalObservers: [UUID: (TerminalSurfaceState) -> Void] = [:]

    init() {}

    func connect(host: RebootHost, password: String) {
        selectedHostID = host.id
        let config = SSHConnectionConfiguration(
            connection: ConnectionDescriptor(
                kind: .ssh,
                host: host.hostname,
                port: host.port,
                displayName: host.name
            ),
            username: host.username,
            password: password,
            terminalType: "xterm-256color",
            terminalSize: TerminalSize(columns: 120, rows: 34, pixelWidth: 1440, pixelHeight: 900)
        )

        Task {
            _ = await runtime.connect(using: config)
            await MainActor.run {
                self.hostStore.markConnected(id: host.id)
            }
        }
    }

    func disconnect() {
        Task {
            await runtime.disconnect()
        }
    }

    func send(_ text: String) {
        Task {
            try? await runtime.send(text: text)
        }
    }

    @discardableResult
    func addTerminalObserver(_ observer: @escaping (TerminalSurfaceState) -> Void) -> UUID {
        let id = UUID()
        terminalObservers[id] = observer
        observer(terminalState)
        return id
    }

    func removeTerminalObserver(id: UUID) {
        terminalObservers.removeValue(forKey: id)
    }

    private func applyTerminalState(_ state: TerminalSurfaceState) {
        terminalState = state
        for observer in terminalObservers.values {
            observer(state)
        }
    }
}

@MainActor
final class RebootRootTabBarController: UITabBarController {
    private let model = RebootAppModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let vaults = UINavigationController(rootViewController: RebootVaultsViewController(model: model))
        vaults.tabBarItem = UITabBarItem(title: "Vaults", image: UIImage(systemName: "shippingbox.fill"), selectedImage: UIImage(systemName: "shippingbox.fill"))

        let connections = UINavigationController(rootViewController: RebootConnectionsViewController(model: model))
        connections.tabBarItem = UITabBarItem(title: "Connections", image: UIImage(systemName: "bolt.horizontal.circle"), selectedImage: UIImage(systemName: "bolt.horizontal.circle.fill"))

        let profile = UINavigationController(rootViewController: RebootProfileViewController(model: model))
        profile.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person.crop.circle"), selectedImage: UIImage(systemName: "person.crop.circle.fill"))

        setViewControllers([vaults, connections, profile], animated: false)
        selectedIndex = 0
    }
}

@MainActor
final class RebootVaultsViewController: UITableViewController {
    private enum Section {
        case favorites
        case recents
        case vault(String)

        var title: String {
            switch self {
            case .favorites: return "Favorites"
            case .recents: return "Recents"
            case .vault(let name): return name
            }
        }
    }

    private let model: RebootAppModel
    private var sections: [Section] = []

    init(model: RebootAppModel) {
        self.model = model
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vaults"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addHost))
        reloadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSections()
    }

    private func reloadSections() {
        sections = []
        if !model.hostStore.favorites().isEmpty { sections.append(.favorites) }
        if !model.hostStore.recentHosts().isEmpty { sections.append(.recents) }
        sections.append(contentsOf: model.hostStore.groupedVaultNames().map { .vault($0) })
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        hosts(for: sections[section]).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let host = hosts(for: sections[indexPath.section])[indexPath.row]
        cell.textLabel?.text = host.isFavorite ? "★ \(host.name)" : host.name
        cell.detailTextLabel?.text = "\(host.username)@\(host.hostname):\(host.port) • \(host.note)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let host = hosts(for: sections[indexPath.section])[indexPath.row]
        navigationController?.pushViewController(RebootHostDetailsViewController(model: model, hostID: host.id), animated: true)
    }

    private func hosts(for section: Section) -> [RebootHost] {
        switch section {
        case .favorites: return model.hostStore.favorites()
        case .recents: return model.hostStore.recentHosts()
        case .vault(let name): return model.hostStore.hosts(inVault: name)
        }
    }

    @objc
    private func addHost() {
        navigationController?.pushViewController(RebootHostEditorViewController(model: model, existingHostID: nil), animated: true)
    }
}

@MainActor
final class RebootHostDetailsViewController: UIViewController {
    private let model: RebootAppModel
    private let hostID: UUID

    private let summaryLabel = UILabel()

    init(model: RebootAppModel, hostID: UUID) {
        self.model = model
        self.hostID = hostID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Host"

        summaryLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        summaryLabel.numberOfLines = 0
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let openButton = UIButton(type: .system)
        openButton.configuration = .filled()
        openButton.configuration?.title = "Use In Connections"
        openButton.addTarget(self, action: #selector(openInConnections), for: .touchUpInside)

        let connectButton = UIButton(type: .system)
        connectButton.configuration = .filled()
        connectButton.configuration?.title = "Connect Now"
        connectButton.addTarget(self, action: #selector(connectNow), for: .touchUpInside)

        let favoriteButton = UIButton(type: .system)
        favoriteButton.configuration = .tinted()
        favoriteButton.configuration?.title = "Toggle Favorite"
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)

        let editButton = UIButton(type: .system)
        editButton.configuration = .plain()
        editButton.configuration?.title = "Edit Host"
        editButton.addTarget(self, action: #selector(editHost), for: .touchUpInside)

        let deleteButton = UIButton(type: .system)
        deleteButton.configuration = .plain()
        deleteButton.configuration?.title = "Delete Host"
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteHost), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [summaryLabel, connectButton, openButton, favoriteButton, editButton, deleteButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func refresh() {
        guard let host = model.hostStore.host(id: hostID) else {
            summaryLabel.text = "Host removed"
            return
        }

        summaryLabel.text = """
        \(host.name)
        \(host.username)@\(host.hostname):\(host.port)
        Vault: \(host.vault)
        Note: \(host.note)
        """
    }

    @objc
    private func openInConnections() {
        NotificationCenter.default.post(
            name: .rebootConnectHostRequested,
            object: nil,
            userInfo: ["hostID": hostID]
        )
        guard let tabBar = tabBarController else { return }
        tabBar.selectedIndex = 1
    }

    @objc
    private func connectNow() {
        guard let host = model.hostStore.host(id: hostID) else { return }

        let alert = UIAlertController(title: "Connect \(host.name)", message: "Enter SSH password", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Password"
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let password = alert?.textFields?.first?.text ?? ""
            self.model.connect(host: host, password: password)
            self.navigationController?.pushViewController(RebootTerminalViewController(model: self.model), animated: true)
        })
        present(alert, animated: true)
    }

    @objc
    private func toggleFavorite() {
        model.hostStore.toggleFavorite(id: hostID)
        refresh()
    }

    @objc
    private func editHost() {
        navigationController?.pushViewController(RebootHostEditorViewController(model: model, existingHostID: hostID), animated: true)
    }

    @objc
    private func deleteHost() {
        model.hostStore.delete(id: hostID)
        navigationController?.popViewController(animated: true)
    }
}

@MainActor
final class RebootHostEditorViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel
    private let existingHostID: UUID?

    private let vaultField = UITextField()
    private let nameField = UITextField()
    private let noteField = UITextField()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let userField = UITextField()
    private let favoriteSwitch = UISwitch()

    init(model: RebootAppModel, existingHostID: UUID?) {
        self.model = model
        self.existingHostID = existingHostID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = existingHostID == nil ? "New Host" : "Edit Host"

        [vaultField, nameField, noteField, hostField, portField, userField].forEach {
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.delegate = self
        }

        vaultField.placeholder = "Vault"
        nameField.placeholder = "Name"
        noteField.placeholder = "Note"
        hostField.placeholder = "Host"
        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        userField.placeholder = "Username"

        let saveButton = UIButton(type: .system)
        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save"
        saveButton.addTarget(self, action: #selector(saveHost), for: .touchUpInside)

        let favoriteRow = UIStackView(arrangedSubviews: [UILabel(), favoriteSwitch])
        (favoriteRow.arrangedSubviews.first as? UILabel)?.text = "Favorite"
        favoriteRow.axis = .horizontal
        favoriteRow.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [vaultField, nameField, noteField, hostField, portField, userField, favoriteRow, saveButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        if let existingHostID, let host = model.hostStore.host(id: existingHostID) {
            vaultField.text = host.vault
            nameField.text = host.name
            noteField.text = host.note
            hostField.text = host.hostname
            portField.text = String(host.port)
            userField.text = host.username
            favoriteSwitch.isOn = host.isFavorite
        } else {
            portField.text = "22"
        }
    }

    @objc
    private func saveHost() {
        let vault = (vaultField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (noteField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hostname = (hostField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let user = (userField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int((portField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22

        guard !vault.isEmpty, !name.isEmpty, !hostname.isEmpty, !user.isEmpty else { return }

        if let existingHostID,
           var existing = model.hostStore.host(id: existingHostID) {
            existing.vault = vault
            existing.name = name
            existing.note = note
            existing.hostname = hostname
            existing.port = max(1, port)
            existing.username = user
            existing.isFavorite = favoriteSwitch.isOn
            _ = model.hostStore.update(existing)
        } else {
            _ = model.hostStore.create(
                RebootHost(
                    vault: vault,
                    name: name,
                    note: note,
                    hostname: hostname,
                    port: port,
                    username: user,
                    isFavorite: favoriteSwitch.isOn
                )
            )
        }

        navigationController?.popViewController(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveHost()
        return true
    }
}

@MainActor
final class RebootConnectionsViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel

    private let quickHostsCard = UIView()
    private let quickHostsStack = UIStackView()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let userField = UITextField()
    private let passwordField = UITextField()
    private let statusLabel = UILabel()
    private var terminalObserverID: UUID?

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
        title = "Connections"
        view.backgroundColor = .systemBackground

        quickHostsCard.backgroundColor = .secondarySystemBackground
        quickHostsCard.layer.cornerRadius = 12
        quickHostsCard.translatesAutoresizingMaskIntoConstraints = false

        let quickTitle = UILabel()
        quickTitle.text = "Quick Connect"
        quickTitle.font = .preferredFont(forTextStyle: .headline)

        quickHostsStack.axis = .vertical
        quickHostsStack.spacing = 8

        let quickCardStack = UIStackView(arrangedSubviews: [quickTitle, quickHostsStack])
        quickCardStack.axis = .vertical
        quickCardStack.spacing = 10
        quickCardStack.translatesAutoresizingMaskIntoConstraints = false
        quickHostsCard.addSubview(quickCardStack)
        NSLayoutConstraint.activate([
            quickCardStack.leadingAnchor.constraint(equalTo: quickHostsCard.leadingAnchor, constant: 12),
            quickCardStack.trailingAnchor.constraint(equalTo: quickHostsCard.trailingAnchor, constant: -12),
            quickCardStack.topAnchor.constraint(equalTo: quickHostsCard.topAnchor, constant: 12),
            quickCardStack.bottomAnchor.constraint(equalTo: quickHostsCard.bottomAnchor, constant: -12)
        ])

        [hostField, portField, userField, passwordField].forEach {
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.delegate = self
        }

        hostField.placeholder = "Host"
        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        portField.text = "22"
        userField.placeholder = "Username"
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true

        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready"

        let connect = UIButton(type: .system)
        connect.configuration = .filled()
        connect.configuration?.title = "Connect SSH"
        connect.addTarget(self, action: #selector(connectSSH), for: .touchUpInside)

        let disconnect = UIButton(type: .system)
        disconnect.configuration = .tinted()
        disconnect.configuration?.title = "Disconnect"
        disconnect.addTarget(self, action: #selector(disconnectSSH), for: .touchUpInside)

        let terminal = UIButton(type: .system)
        terminal.configuration = .plain()
        terminal.configuration?.title = "Open Terminal"
        terminal.addTarget(self, action: #selector(openTerminal), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [quickHostsCard, hostField, portField, userField, passwordField, connect, disconnect, terminal, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectHostNotification(_:)),
            name: .rebootConnectHostRequested,
            object: nil
        )

        reloadQuickHosts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadQuickHosts()
        if terminalObserverID == nil {
            terminalObserverID = model.addTerminalObserver { [weak self] state in
                self?.statusLabel.text = "\(state.connectionTitle) • \(state.sessionState.rawValue.capitalized) • \(state.statusMessage)"
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func connectSSH() {
        let host = (hostField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let user = (userField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""
        let port = Int((portField.text ?? "22").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        guard !host.isEmpty, !user.isEmpty else { return }

        if let selectedHost = model.hostStore.host(id: model.selectedHostID ?? UUID()),
           selectedHost.hostname == host,
           selectedHost.username == user,
           selectedHost.port == port {
            model.connect(host: selectedHost, password: password)
            return
        }

        let saved = model.hostStore.hosts.first { candidate in
            candidate.hostname == host && candidate.username == user && candidate.port == port
        }

        if let saved {
            model.connect(host: saved, password: password)
        } else {
            let transient = RebootHost(vault: "Manual", name: host, note: "Manual session", hostname: host, port: port, username: user)
            model.connect(host: transient, password: password)
        }
    }

    @objc
    private func disconnectSSH() {
        model.disconnect()
    }

    @objc
    private func openTerminal() {
        navigationController?.pushViewController(RebootTerminalViewController(model: model), animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        connectSSH()
        return true
    }

    private func reloadQuickHosts() {
        quickHostsStack.arrangedSubviews.forEach { view in
            quickHostsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let quickHosts = Array((model.hostStore.recentHosts() + model.hostStore.favorites()).reduce(into: [RebootHost]()) { partialResult, host in
            if !partialResult.contains(where: { $0.id == host.id }) {
                partialResult.append(host)
            }
        }.prefix(6))

        if quickHosts.isEmpty {
            let label = UILabel()
            label.text = "No recent connections yet."
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.textColor = .secondaryLabel
            quickHostsStack.addArrangedSubview(label)
            return
        }

        for host in quickHosts {
            let button = UIButton(type: .system)
            button.configuration = .tinted()
            button.configuration?.title = "\(host.name)  \(host.username)@\(host.hostname):\(host.port)"
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in
                self?.prefill(host)
                self?.promptPasswordAndConnect(host: host)
            }, for: .touchUpInside)
            quickHostsStack.addArrangedSubview(button)
        }
    }

    private func prefill(_ host: RebootHost) {
        model.selectedHostID = host.id
        hostField.text = host.hostname
        portField.text = String(host.port)
        userField.text = host.username
    }

    private func promptPasswordAndConnect(host: RebootHost) {
        let alert = UIAlertController(title: "Connect \(host.name)", message: "Enter SSH password", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Password"
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let password = alert?.textFields?.first?.text ?? ""
            self.passwordField.text = ""
            self.model.connect(host: host, password: password)
        })
        present(alert, animated: true)
    }

    @objc
    private func handleConnectHostNotification(_ notification: Notification) {
        guard let hostID = notification.userInfo?["hostID"] as? UUID else { return }
        guard let host = model.hostStore.host(id: hostID) else { return }
        prefill(host)
    }
}

@MainActor
final class RebootTerminalViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel
    private let outputView = UITextView()
    private let inputField = UITextField()
    private var terminalObserverID: UUID?

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
        title = "Terminal"
        view.backgroundColor = .systemBackground

        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        outputView.backgroundColor = UIColor.secondarySystemBackground
        outputView.layer.cornerRadius = 12

        inputField.borderStyle = .roundedRect
        inputField.placeholder = "Command"
        inputField.autocapitalizationType = .none
        inputField.autocorrectionType = .no
        inputField.delegate = self

        let sendButton = UIButton(type: .system)
        sendButton.configuration = .filled()
        sendButton.configuration?.title = "Send"
        sendButton.addTarget(self, action: #selector(sendCommand), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [outputView, inputField, sendButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            outputView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if terminalObserverID == nil {
            terminalObserverID = model.addTerminalObserver { [weak self] state in
                self?.render(state: state)
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

    private func render(state: TerminalSurfaceState) {
        outputView.text = state.transcript
        let length = outputView.text.utf16.count
        if length > 0 {
            outputView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
        }
    }

    @objc
    private func sendCommand() {
        guard let text = inputField.text, !text.isEmpty else { return }
        model.send(text + "\n")
        inputField.text = ""
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendCommand()
        return true
    }
}

@MainActor
final class RebootProfileViewController: UIViewController {
    private let model: RebootAppModel

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
        title = "Profile"
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.text = """
        Termius Reboot
        Mobile-first mode.
        External monitor mirroring will be added as Phase 2 after phone flow is stable.
        Hosts in storage: \(model.hostStore.hosts.count)
        """

        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }
}
