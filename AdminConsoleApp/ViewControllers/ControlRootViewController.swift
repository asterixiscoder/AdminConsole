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
        configureAppearance()

        let vaults = UINavigationController(rootViewController: RebootVaultsViewController(model: model))
        vaults.tabBarItem = UITabBarItem(title: "Vaults", image: UIImage(systemName: "shippingbox.fill"), selectedImage: UIImage(systemName: "shippingbox.fill"))

        let connections = UINavigationController(rootViewController: RebootConnectionsViewController(model: model))
        connections.tabBarItem = UITabBarItem(title: "Connections", image: UIImage(systemName: "bolt.horizontal.circle"), selectedImage: UIImage(systemName: "bolt.horizontal.circle.fill"))

        let profile = UINavigationController(rootViewController: RebootProfileViewController(model: model))
        profile.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person.crop.circle"), selectedImage: UIImage(systemName: "person.crop.circle.fill"))

        setViewControllers([vaults, connections, profile], animated: false)
        selectedIndex = 0
    }

    private func configureAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.secondarySystemBackground
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 34, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }
}

@MainActor
final class RebootVaultsViewController: UITableViewController {
    private enum FilterScope: Int {
        case all
        case favorites
        case recents
    }

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
    private let searchController = UISearchController(searchResultsController: nil)
    private let scopeControl = UISegmentedControl(items: ["All", "Favorites", "Recents"])
    private var searchText: String = ""
    private var selectedScope: FilterScope = .all

    init(model: RebootAppModel) {
        self.model = model
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vaults"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .singleLine
        tableView.sectionHeaderTopPadding = 12
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addHost))
        configureSearchAndScope()
        reloadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBottomInsets()
        reloadSections()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomInsets()
    }

    private func reloadSections() {
        let hasScopedHosts = !filteredAllHosts().isEmpty
        sections = []
        switch selectedScope {
        case .favorites:
            if !filteredFavorites().isEmpty { sections.append(.favorites) }
        case .recents:
            if !filteredRecents().isEmpty { sections.append(.recents) }
        case .all:
            if !filteredFavorites().isEmpty { sections.append(.favorites) }
            if !filteredRecents().isEmpty { sections.append(.recents) }
            let vaults = model.hostStore.groupedVaultNames().filter { vault in
                !filteredHosts(inVault: vault).isEmpty
            }
            sections.append(contentsOf: vaults.map { .vault($0) })
        }

        if !hasScopedHosts {
            sections = []
        }
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
        cell.textLabel?.text = host.name
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: host.isFavorite ? "star.fill" : "server.rack")
        cell.imageView?.tintColor = host.isFavorite ? .systemYellow : .systemBlue
        let lastConnected = host.lastConnectedAt.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) } ?? "never"
        cell.detailTextLabel?.text = "\(host.username)@\(host.hostname):\(host.port) • last: \(lastConnected)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let host = hosts(for: sections[indexPath.section])[indexPath.row]
        let controller = RebootHostDetailsViewController(model: model, hostID: host.id)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    private func hosts(for section: Section) -> [RebootHost] {
        switch section {
        case .favorites: return filteredFavorites()
        case .recents: return filteredRecents()
        case .vault(let name): return filteredHosts(inVault: name)
        }
    }

    @objc
    private func addHost() {
        let controller = RebootHostEditorViewController(model: model, existingHostID: nil)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    private func configureSearchAndScope() {
        searchController.searchBar.placeholder = "Search hosts"
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 48))
        scopeControl.frame = CGRect(x: 16, y: 8, width: header.bounds.width - 32, height: 32)
        scopeControl.autoresizingMask = [.flexibleWidth]
        header.addSubview(scopeControl)
        tableView.tableHeaderView = header
    }

    @objc
    private func scopeChanged() {
        selectedScope = FilterScope(rawValue: scopeControl.selectedSegmentIndex) ?? .all
        reloadSections()
    }

    private func filteredAllHosts() -> [RebootHost] {
        let all = model.hostStore.hosts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return all }
        return all.filter(matchesSearch(_:))
    }

    private func filteredFavorites() -> [RebootHost] {
        model.hostStore.favorites().filter(matchesSearch(_:))
    }

    private func filteredRecents() -> [RebootHost] {
        model.hostStore.recentHosts().filter(matchesSearch(_:))
    }

    private func filteredHosts(inVault vault: String) -> [RebootHost] {
        model.hostStore.hosts(inVault: vault).filter(matchesSearch(_:))
    }

    private func matchesSearch(_ host: RebootHost) -> Bool {
        if searchText.isEmpty { return true }
        let needle = searchText.lowercased()
        return host.name.lowercased().contains(needle)
            || host.hostname.lowercased().contains(needle)
            || host.username.lowercased().contains(needle)
            || host.vault.lowercased().contains(needle)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func updateBottomInsets() {
        let bottomPadding = (tabBarController?.tabBar.bounds.height ?? 0) + 24
        tableView.contentInset.bottom = bottomPadding
        tableView.verticalScrollIndicatorInsets.bottom = bottomPadding
    }
}

extension RebootVaultsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        reloadSections()
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
        navigationItem.largeTitleDisplayMode = .never

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

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
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
            let terminal = RebootTerminalViewController(model: self.model)
            terminal.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(terminal, animated: true)
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
        let controller = RebootHostEditorViewController(model: model, existingHostID: hostID)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
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
        navigationItem.largeTitleDisplayMode = .never

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

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
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

    private let connectBar = UIView()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let userField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)

    private let quickHostsCard = UIView()
    private let quickHostsStack = UIStackView()
    private let sessionCard = UIView()
    private let sessionHostLabel = UILabel()
    private let sessionStateLabel = UILabel()
    private let sessionPreviewView = UITextView()
    private let statusLabel = UILabel()
    private var terminalObserverID: UUID?
    private var didAutoOpenTerminal = false

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
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)

        configureConnectBar()
        configureQuickHostsCard()
        configureSessionCard()
        configureStatusLabel()

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

        let disconnect = UIButton(type: .system)
        disconnect.configuration = .tinted()
        disconnect.configuration?.title = "Disconnect"
        disconnect.addTarget(self, action: #selector(disconnectSSH), for: .touchUpInside)

        let terminal = UIButton(type: .system)
        terminal.configuration = .plain()
        terminal.configuration?.title = "Open Terminal"
        terminal.addTarget(self, action: #selector(openTerminal), for: .touchUpInside)

        let credentialsRow = UIStackView(arrangedSubviews: [userField, portField])
        credentialsRow.axis = .horizontal
        credentialsRow.spacing = 10
        credentialsRow.distribution = .fillEqually

        let controls = UIStackView(arrangedSubviews: [disconnect, terminal])
        controls.axis = .horizontal
        controls.spacing = 8
        controls.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [connectBar, credentialsRow, passwordField, sessionCard, quickHostsCard, controls, statusLabel])
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
        didAutoOpenTerminal = false
        reloadQuickHosts()
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

        let targetHost: RebootHost
        if let selectedHost = model.hostStore.host(id: model.selectedHostID ?? UUID()),
           selectedHost.hostname == host,
           selectedHost.username == user,
           selectedHost.port == port {
            targetHost = selectedHost
        } else {
            let saved = model.hostStore.hosts.first { candidate in
                candidate.hostname == host && candidate.username == user && candidate.port == port
            }
            targetHost = saved ?? RebootHost(vault: "Manual", name: host, note: "Manual session", hostname: host, port: port, username: user)
        }
        model.connect(host: targetHost, password: password)
        openTerminalIfNeeded()
    }

    @objc
    private func disconnectSSH() {
        model.disconnect()
    }

    @objc
    private func openTerminal() {
        let controller = RebootTerminalViewController(model: model)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
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
            self.openTerminalIfNeeded()
        })
        present(alert, animated: true)
    }

    @objc
    private func handleConnectHostNotification(_ notification: Notification) {
        guard let hostID = notification.userInfo?["hostID"] as? UUID else { return }
        guard let host = model.hostStore.host(id: hostID) else { return }
        prefill(host)
    }

    private func configureConnectBar() {
        connectBar.backgroundColor = .white
        connectBar.layer.cornerRadius = 12
        connectBar.translatesAutoresizingMaskIntoConstraints = false

        hostField.placeholder = "Search or \"ssh user@hostname -p port\""
        hostField.borderStyle = .none

        connectButton.configuration = .plain()
        connectButton.configuration?.title = "CONNECT"
        connectButton.configuration?.baseForegroundColor = .systemBlue
        connectButton.addTarget(self, action: #selector(connectSSH), for: .touchUpInside)

        let line = UIView()
        line.backgroundColor = UIColor.systemGray4
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let bar = UIStackView(arrangedSubviews: [hostField, line, connectButton])
        bar.axis = .horizontal
        bar.spacing = 10
        bar.alignment = .center
        bar.translatesAutoresizingMaskIntoConstraints = false
        connectBar.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: connectBar.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: connectBar.trailingAnchor, constant: -8),
            bar.topAnchor.constraint(equalTo: connectBar.topAnchor, constant: 10),
            bar.bottomAnchor.constraint(equalTo: connectBar.bottomAnchor, constant: -10),
            connectBar.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func configureQuickHostsCard() {
        quickHostsCard.backgroundColor = .white
        quickHostsCard.layer.cornerRadius = 14
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
    }

    private func configureSessionCard() {
        sessionCard.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.19, alpha: 1)
        sessionCard.layer.cornerRadius = 14
        sessionCard.translatesAutoresizingMaskIntoConstraints = false

        sessionHostLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        sessionHostLabel.textColor = .white
        sessionHostLabel.text = "No Active Session"

        sessionStateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sessionStateLabel.textColor = UIColor(red: 0.45, green: 0.82, blue: 0.52, alpha: 1)
        sessionStateLabel.text = "Idle"

        sessionPreviewView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        sessionPreviewView.textColor = UIColor(red: 0.39, green: 0.85, blue: 0.96, alpha: 1)
        sessionPreviewView.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1)
        sessionPreviewView.layer.cornerRadius = 10
        sessionPreviewView.isEditable = false
        sessionPreviewView.text = "Terminal output will appear here."
        sessionPreviewView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)

        let labels = UIStackView(arrangedSubviews: [sessionHostLabel, sessionStateLabel])
        labels.axis = .vertical
        labels.spacing = 4

        let stack = UIStackView(arrangedSubviews: [labels, sessionPreviewView])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        sessionCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sessionCard.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sessionCard.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: sessionCard.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: sessionCard.bottomAnchor, constant: -12),
            sessionPreviewView.heightAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func configureStatusLabel() {
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready"
    }

    private func render(_ state: TerminalSurfaceState) {
        statusLabel.text = "\(state.connectionTitle) • \(state.sessionState.rawValue.capitalized) • \(state.statusMessage)"
        sessionHostLabel.text = state.connectionTitle.isEmpty ? "No Active Session" : state.connectionTitle
        sessionStateLabel.text = state.sessionState.rawValue.capitalized
        sessionPreviewView.text = String(state.transcript.suffix(1200))
    }

    private func openTerminalIfNeeded() {
        guard !didAutoOpenTerminal else { return }
        didAutoOpenTerminal = true
        openTerminal()
    }
}

@MainActor
final class RebootTerminalViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel
    private let outputView = UITextView()
    private let tabsRow = UIStackView()
    private let shortcutsRow = UIStackView()
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
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)

        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 1)
        outputView.textColor = UIColor(red: 0.42, green: 0.86, blue: 0.97, alpha: 1)
        outputView.layer.cornerRadius = 12
        outputView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)

        inputField.borderStyle = .roundedRect
        inputField.placeholder = "Command"
        inputField.autocapitalizationType = .none
        inputField.autocorrectionType = .no
        inputField.delegate = self

        tabsRow.axis = .horizontal
        tabsRow.spacing = 8
        tabsRow.distribution = .fillProportionally
        let prev = makeChipButton("‹")
        prev.configuration?.baseBackgroundColor = UIColor(red: 0.18, green: 0.20, blue: 0.30, alpha: 1)
        let activeTab = makeChipButton("active")
        activeTab.configuration?.baseBackgroundColor = UIColor(red: 0.21, green: 0.24, blue: 0.35, alpha: 1)
        let addTab = makeChipButton("+")
        addTab.configuration?.baseBackgroundColor = UIColor(red: 0.18, green: 0.20, blue: 0.30, alpha: 1)
        tabsRow.addArrangedSubview(prev)
        tabsRow.addArrangedSubview(activeTab)
        tabsRow.addArrangedSubview(addTab)

        shortcutsRow.axis = .horizontal
        shortcutsRow.spacing = 6
        shortcutsRow.distribution = .fillEqually
        let shortcutKeys: [(String, String)] = [("esc", "\u{1B}"), ("tab", "\t"), ("ctrl", "\u{3}"), ("alt", ""), ("/", "/"), ("|", "|"), ("~", "~"), ("-", "-"), ("^C", "\u{3}")]
        for item in shortcutKeys {
            let button = UIButton(type: .system)
            button.configuration = .tinted()
            button.configuration?.title = item.0
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if !item.1.isEmpty {
                    self.model.send(item.1)
                }
            }, for: .touchUpInside)
            shortcutsRow.addArrangedSubview(button)
        }

        let sendButton = UIButton(type: .system)
        sendButton.configuration = .filled()
        sendButton.configuration?.title = "Send"
        sendButton.addTarget(self, action: #selector(sendCommand), for: .touchUpInside)

        let inputRow = UIStackView(arrangedSubviews: [inputField, sendButton])
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        sendButton.widthAnchor.constraint(equalToConstant: 84).isActive = true

        let stack = UIStackView(arrangedSubviews: [outputView, tabsRow, shortcutsRow, inputRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            outputView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            tabsRow.heightAnchor.constraint(equalToConstant: 36),
            shortcutsRow.heightAnchor.constraint(equalToConstant: 34)
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

    private func makeChipButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.baseForegroundColor = .white
        button.configuration?.cornerStyle = .medium
        return button
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
