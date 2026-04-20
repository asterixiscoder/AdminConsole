import ConnectionKit
import DesktopDomain
import SecurityKit
import SSHKit
import UIKit

private extension Notification.Name {
    static let rebootConnectHostRequested = Notification.Name("rebootConnectHostRequested")
}

final class RebootTerminalInputProxyView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    // Keep deletion key active for terminal semantics (delete should always emit DEL).
    var hasText: Bool {
        true
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        onInsertText?(text)
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically: Bool = false
    var textContentType: UITextContentType?

    @available(iOS 17.0, *)
    var inlinePredictionType: UITextInlinePredictionType = .no
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
struct RebootTerminalSessionSummary {
    let id: UUID
    let title: String
    let sessionState: TerminalConnectionState
    let isActive: Bool
}

@MainActor
final class RebootAppModel {
    let hostStore = RebootHostStore()
    var selectedHostID: UUID?
    private let credentialStore = SSHCredentialStore()

    private final class TerminalSessionSlot {
        let id: UUID
        var hostID: UUID?
        let runtime: SSHTerminalRuntime
        var state: TerminalSurfaceState
        var backgroundReconnectHostID: UUID?

        init(id: UUID, runtime: SSHTerminalRuntime, state: TerminalSurfaceState) {
            self.id = id
            self.runtime = runtime
            self.state = state
            self.backgroundReconnectHostID = nil
        }
    }

    private(set) var terminalState: TerminalSurfaceState = .idle()
    private(set) var activeTerminalSessionID: UUID?
    private var terminalSessions: [UUID: TerminalSessionSlot] = [:]
    private var terminalSessionOrder: [UUID] = []
    private var terminalObservers: [UUID: (TerminalSurfaceState) -> Void] = [:]

    init() {
        _ = createTerminalSession(makeActive: true)
    }

    @discardableResult
    func createTerminalSession(makeActive: Bool = true) -> UUID {
        let sessionID = UUID()
        let runtime = SSHTerminalRuntime(windowID: WindowID(), initialState: .idle()) { [weak self] state in
            await self?.applyTerminalState(state, for: sessionID)
        }
        let slot = TerminalSessionSlot(id: sessionID, runtime: runtime, state: .idle())
        terminalSessions[sessionID] = slot
        terminalSessionOrder.append(sessionID)

        if makeActive {
            activateSession(sessionID)
        }

        return sessionID
    }

    func switchToTerminalSession(_ id: UUID) {
        activateSession(id)
    }

    func closeActiveTerminalSession() {
        guard let activeSessionID = activeTerminalSessionID else {
            return
        }
        guard terminalSessionOrder.count > 1 else {
            return
        }
        guard let slot = terminalSessions.removeValue(forKey: activeSessionID) else {
            return
        }

        terminalSessionOrder.removeAll(where: { $0 == activeSessionID })
        Task {
            await slot.runtime.disconnect()
        }

        let fallback = terminalSessionOrder.last ?? createTerminalSession(makeActive: false)
        activateSession(fallback)
    }

    func terminalSessionSummaries() -> [RebootTerminalSessionSummary] {
        terminalSessionOrder.enumerated().compactMap { index, sessionID in
            guard let slot = terminalSessions[sessionID] else {
                return nil
            }
            let hostTitle = slot.hostID.flatMap { hostStore.host(id: $0)?.name }
            let stateTitle = slot.state.connectionTitle.isEmpty ? nil : slot.state.connectionTitle
            let title = hostTitle ?? stateTitle ?? "session-\(index + 1)"

            return RebootTerminalSessionSummary(
                id: sessionID,
                title: title,
                sessionState: slot.state.sessionState,
                isActive: sessionID == activeTerminalSessionID
            )
        }
    }

    func connect(host: RebootHost, password: String) {
        guard let sessionID = activeTerminalSessionID else {
            return
        }
        connect(host: host, password: password, sessionID: sessionID)
    }

    private func connect(host: RebootHost, password: String, sessionID: UUID) {
        selectedHostID = host.id
        guard let slot = terminalSessions[sessionID] else {
            return
        }
        slot.hostID = host.id
        let runtime = slot.runtime

        Task {
            let typedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = SSHCredentialIdentity(
                host: host.hostname,
                port: host.port,
                username: host.username
            )

            let resolvedPassword: String
            if typedPassword.isEmpty {
                do {
                    if let stored = try await credentialStore.password(for: identity),
                       !stored.isEmpty {
                        resolvedPassword = stored
                    } else {
                        await runtime.presentLocalFailure(
                            connectionTitle: "\(host.username)@\(host.hostname):\(host.port)",
                            message: "No saved password found. Enter password to connect."
                        )
                        return
                    }
                } catch {
                    await runtime.presentLocalFailure(
                        connectionTitle: "\(host.username)@\(host.hostname):\(host.port)",
                        message: "Unable to read saved password: \(error.localizedDescription)"
                    )
                    return
                }
            } else {
                resolvedPassword = typedPassword
            }

            let config = SSHConnectionConfiguration(
                connection: ConnectionDescriptor(
                    kind: .ssh,
                    host: host.hostname,
                    port: host.port,
                    displayName: host.name
                ),
                username: host.username,
                password: resolvedPassword,
                terminalType: "xterm-256color",
                terminalSize: TerminalSize(columns: 40, rows: 30, pixelWidth: 640, pixelHeight: 1200)
            )

            let didConnect = await runtime.connect(using: config)
            await MainActor.run {
                if didConnect {
                    self.hostStore.markConnected(id: host.id)
                }
            }

            guard didConnect, !typedPassword.isEmpty else {
                return
            }

            do {
                try await credentialStore.savePassword(typedPassword, for: identity)
            } catch {
                // Connection is already active; keep session state and skip failing UI.
                NSLog("AdminConsole: failed to save SSH password for %@: %@", identity.account, error.localizedDescription)
            }
        }
    }

    func hasSavedPassword(for host: RebootHost) async -> Bool {
        let identity = SSHCredentialIdentity(
            host: host.hostname,
            port: host.port,
            username: host.username
        )

        do {
            let saved = try await credentialStore.password(for: identity)
            return !(saved?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    func disconnect() {
        guard let activeSessionID = activeTerminalSessionID,
              let slot = terminalSessions[activeSessionID] else {
            return
        }
        Task {
            slot.backgroundReconnectHostID = nil
            await slot.runtime.disconnect()
        }
    }

    func sceneDidEnterBackground() {
        let sessions = terminalSessionOrder.compactMap { terminalSessions[$0] }
        for slot in sessions {
            slot.backgroundReconnectHostID = slot.state.sessionState == .connected ? slot.hostID : nil
        }

        Task {
            for slot in sessions {
                await slot.runtime.suspendForBackground()
            }
        }
    }

    func sceneWillEnterForeground() {
        let sessions = terminalSessionOrder.compactMap { terminalSessions[$0] }

        Task {
            for slot in sessions {
                await slot.runtime.resumeAfterForeground()

                guard let reconnectHostID = slot.backgroundReconnectHostID else {
                    continue
                }
                slot.backgroundReconnectHostID = nil

                let state = await slot.runtime.snapshot()
                guard state.sessionState != .connected,
                      let host = hostStore.host(id: reconnectHostID) else {
                    continue
                }

                await MainActor.run {
                    self.connect(host: host, password: "", sessionID: slot.id)
                }
            }
        }
    }

    func send(_ text: String) {
        guard let activeSessionID = activeTerminalSessionID,
              let slot = terminalSessions[activeSessionID] else {
            return
        }
        Task {
            try? await slot.runtime.send(text: text)
        }
    }

    func resizeTerminal(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        let normalizedColumns = max(40, min(220, columns))
        let normalizedRows = max(18, rows)
        guard let activeSessionID = activeTerminalSessionID,
              let slot = terminalSessions[activeSessionID] else {
            return
        }
        Task {
            await slot.runtime.resize(
                to: TerminalSize(
                    columns: normalizedColumns,
                    rows: normalizedRows,
                    pixelWidth: max(320, pixelWidth),
                    pixelHeight: max(320, pixelHeight)
                )
            )
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

    private func applyTerminalState(_ state: TerminalSurfaceState, for sessionID: UUID) {
        guard let slot = terminalSessions[sessionID] else {
            return
        }
        slot.state = state
        if sessionID != activeTerminalSessionID {
            return
        }

        terminalState = state
        for observer in terminalObservers.values {
            observer(state)
        }
    }

    private func activateSession(_ sessionID: UUID) {
        guard let slot = terminalSessions[sessionID] else {
            return
        }
        activeTerminalSessionID = sessionID
        terminalState = slot.state
        for observer in terminalObservers.values {
            observer(terminalState)
        }
    }
}

@MainActor
protocol RebootPhoneRouting: AnyObject {
    func showHostDetails(hostID: UUID)
    func showHostEditor(existingHostID: UUID?)
    func showTerminal()
    func switchToConnections(hostID: UUID?)
}

@MainActor
final class RebootRootViewController: UIViewController, RebootPhoneRouting {
    private enum Tab: CaseIterable {
        case vaults
        case connections
        case profile

        var title: String {
            switch self {
            case .vaults: return "Vaults"
            case .connections: return "Connections"
            case .profile: return "Profile"
            }
        }

        var iconName: String {
            switch self {
            case .vaults: return "shippingbox.fill"
            case .connections: return "bolt.horizontal.circle.fill"
            case .profile: return "person.crop.circle.fill"
            }
        }
    }

    private let model = RebootAppModel()
    var appModel: RebootAppModel { model }
    private let contentContainer = UIView()
    private let tabBarContainer = UIView()
    private let tabStack = UIStackView()
    private var tabButtons: [Tab: UIButton] = [:]
    private var selectedTab: Tab = .vaults
    private var currentChild: UIViewController?

    private lazy var vaultsViewController = RebootVaultsViewController(model: model, router: self)
    private lazy var connectionsViewController = RebootConnectionsViewController(model: model, router: self)
    private lazy var profileViewController = RebootProfileViewController(model: model)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLayout()
        switchToTab(.vaults, animated: false)
    }

    func sceneDidEnterBackground() {
        model.sceneDidEnterBackground()
    }

    func sceneWillEnterForeground() {
        model.sceneWillEnterForeground()
    }

    private func configureLayout() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.backgroundColor = UIColor.secondarySystemBackground
        tabBarContainer.layer.cornerRadius = 28
        tabBarContainer.layer.shadowColor = UIColor.black.cgColor
        tabBarContainer.layer.shadowOpacity = 0.08
        tabBarContainer.layer.shadowRadius = 20
        tabBarContainer.layer.shadowOffset = CGSize(width: 0, height: 10)

        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.axis = .horizontal
        tabStack.spacing = 10
        tabStack.distribution = .fillEqually

        view.addSubview(contentContainer)
        view.addSubview(tabBarContainer)
        tabBarContainer.addSubview(tabStack)

        for tab in Tab.allCases {
            let button = makeTabButton(for: tab)
            tabButtons[tab] = button
            tabStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: tabBarContainer.topAnchor, constant: -12),

            tabBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            tabBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            tabBarContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            tabBarContainer.heightAnchor.constraint(equalToConstant: 78),

            tabStack.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor, constant: -12),
            tabStack.topAnchor.constraint(equalTo: tabBarContainer.topAnchor, constant: 10),
            tabStack.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: -10)
        ])
    }

    private func makeTabButton(for tab: Tab) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = Tab.allCases.firstIndex(of: tab) ?? 0
        button.configuration = .plain()
        button.configuration?.image = UIImage(systemName: tab.iconName)
        button.configuration?.title = tab.title
        button.configuration?.imagePlacement = .top
        button.configuration?.imagePadding = 6
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 10, weight: .semibold)
            return outgoing
        }
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.layer.cornerRadius = 22
        button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc
    private func tabTapped(_ sender: UIButton) {
        guard Tab.allCases.indices.contains(sender.tag) else { return }
        switchToTab(Tab.allCases[sender.tag], animated: false)
    }

    private func switchToTab(_ tab: Tab, animated: Bool) {
        selectedTab = tab
        updateTabSelection()

        let nextController: UIViewController
        switch tab {
        case .vaults:
            nextController = vaultsViewController
        case .connections:
            nextController = connectionsViewController
        case .profile:
            nextController = profileViewController
        }

        guard currentChild !== nextController else { return }

        let previousChild = currentChild
        previousChild?.willMove(toParent: nil)
        previousChild?.view.removeFromSuperview()
        previousChild?.removeFromParent()

        addChild(nextController)
        nextController.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(nextController.view)
        NSLayoutConstraint.activate([
            nextController.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            nextController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            nextController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            nextController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        nextController.didMove(toParent: self)
        currentChild = nextController

        if animated {
            nextController.view.alpha = 0
            UIView.animate(withDuration: 0.2) {
                nextController.view.alpha = 1
            }
        }
    }

    private func updateTabSelection() {
        for (tab, button) in tabButtons {
            let isSelected = tab == selectedTab
            button.configuration?.baseForegroundColor = isSelected ? .systemBlue : .label
            button.backgroundColor = isSelected ? UIColor.systemBlue.withAlphaComponent(0.14) : .clear
        }
    }

    private func topPresenter() -> UIViewController {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    private func presentFullscreen(_ controller: UIViewController) {
        controller.modalPresentationStyle = .fullScreen
        topPresenter().present(controller, animated: true)
    }

    func showHostDetails(hostID: UUID) {
        presentFullscreen(RebootHostDetailsViewController(model: model, hostID: hostID, router: self))
    }

    func showHostEditor(existingHostID: UUID?) {
        presentFullscreen(RebootHostEditorViewController(model: model, existingHostID: existingHostID))
    }

    func showTerminal() {
        presentFullscreen(RebootTerminalViewController(model: model))
    }

    func switchToConnections(hostID: UUID?) {
        let switchAction = {
            if let hostID {
                NotificationCenter.default.post(
                    name: .rebootConnectHostRequested,
                    object: nil,
                    userInfo: ["hostID": hostID]
                )
            }
            self.switchToTab(.connections, animated: false)
        }

        if presentedViewController != nil {
            dismiss(animated: true) {
                switchAction()
            }
        } else {
            switchAction()
        }
    }
}

@MainActor
final class RebootVaultsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
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
    private weak var router: (any RebootPhoneRouting)?
    private var sections: [Section] = []
    private let titleLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let searchField = UITextField()
    private let scopeControl = UISegmentedControl(items: ["All", "Favorites", "Recents"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var searchText: String = ""
    private var selectedScope: FilterScope = .all

    init(model: RebootAppModel, router: any RebootPhoneRouting) {
        self.model = model
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHeader()
        configureTableView()
        reloadSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSections()
    }

    private func configureHeader() {
        titleLabel.text = "Vaults"
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)

        addButton.configuration = .filled()
        addButton.configuration?.image = UIImage(systemName: "plus")
        addButton.configuration?.baseForegroundColor = .label
        addButton.configuration?.baseBackgroundColor = UIColor.secondarySystemBackground
        addButton.configuration?.cornerStyle = .capsule
        addButton.addTarget(self, action: #selector(addHost), for: .touchUpInside)

        searchField.placeholder = "Search hosts"
        searchField.borderStyle = .roundedRect
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .done
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), addButton])
        titleRow.axis = .horizontal
        titleRow.alignment = .center

        let headerStack = UIStackView(arrangedSubviews: [titleRow, searchField, scopeControl])
        headerStack.axis = .vertical
        headerStack.spacing = 16
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56),
            headerStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .singleLine
        tableView.sectionHeaderTopPadding = 12
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 120, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 20),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        hosts(for: sections[section]).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let host = hosts(for: sections[indexPath.section])[indexPath.row]
        router?.showHostDetails(hostID: host.id)
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
        router?.showHostEditor(existingHostID: nil)
    }

    @objc
    private func searchTextChanged() {
        searchText = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        reloadSections()
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

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

@MainActor
final class RebootHostDetailsViewController: UIViewController {
    private let model: RebootAppModel
    private let hostID: UUID
    private weak var router: (any RebootPhoneRouting)?
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()

    init(model: RebootAppModel, hostID: UUID, router: any RebootPhoneRouting) {
        self.model = model
        self.hostID = hostID
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHeader()
        summaryLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        summaryLabel.numberOfLines = 0

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
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
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

    private func configureHeader() {
        let closeButton = UIButton(type: .system)
        closeButton.configuration = .plain()
        closeButton.configuration?.image = UIImage(systemName: "chevron.left")
        closeButton.configuration?.baseForegroundColor = .label
        closeButton.addTarget(self, action: #selector(closeScreen), for: .touchUpInside)

        titleLabel.text = "Host"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
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
        router?.switchToConnections(hostID: hostID)
    }

    @objc
    private func connectNow() {
        guard let host = model.hostStore.host(id: hostID) else { return }
        Task { [weak self] in
            guard let self else { return }
            if await self.model.hasSavedPassword(for: host) {
                self.model.connect(host: host, password: "")
                self.router?.showTerminal()
            } else {
                self.presentPasswordPrompt(for: host)
            }
        }
    }

    @objc
    private func toggleFavorite() {
        model.hostStore.toggleFavorite(id: hostID)
        refresh()
    }

    @objc
    private func editHost() {
        router?.showHostEditor(existingHostID: hostID)
    }

    @objc
    private func deleteHost() {
        model.hostStore.delete(id: hostID)
        dismiss(animated: true)
    }

    @objc
    private func closeScreen() {
        dismiss(animated: true)
    }

    private func presentPasswordPrompt(for host: RebootHost) {
        view.endEditing(true)

        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentedViewController == nil else { return }
            let prompt = RebootPasswordPromptViewController(hostName: host.name) { [weak self] password in
                guard let self else { return }
                self.model.connect(host: host, password: password)
                self.router?.showTerminal()
            }
            prompt.modalPresentationStyle = .overFullScreen
            prompt.modalTransitionStyle = .crossDissolve
            self.present(prompt, animated: true)
        }
    }
}

@MainActor
final class RebootHostEditorViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel
    private let existingHostID: UUID?

    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
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
        configureChrome()
        configureFields()
        configureKeyboardHandling()
        configureContent()
        loadHostValues()
    }

    private func configureChrome() {
        let closeButton = UIButton(type: .system)
        closeButton.configuration = .plain()
        closeButton.configuration?.image = UIImage(systemName: "chevron.left")
        closeButton.configuration?.baseForegroundColor = .label
        closeButton.addTarget(self, action: #selector(closeScreen), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = existingHostID == nil ? "New Host" : "Edit Host"
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    private func configureFields() {
        [vaultField, nameField, noteField, hostField, portField, userField].forEach {
            $0.borderStyle = .roundedRect
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.delegate = self
            $0.clearButtonMode = .whileEditing
        }

        vaultField.placeholder = "Vault"
        vaultField.returnKeyType = .next
        nameField.placeholder = "Name"
        nameField.returnKeyType = .next
        noteField.placeholder = "Note"
        noteField.returnKeyType = .next
        hostField.placeholder = "Host"
        hostField.returnKeyType = .next
        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        userField.placeholder = "Username"
        userField.returnKeyType = .done
    }

    private func configureKeyboardHandling() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(title: "Previous", style: .plain, target: self, action: #selector(focusPreviousField)),
            UIBarButtonItem(title: "Next", style: .plain, target: self, action: #selector(focusNextField)),
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        ]

        [vaultField, nameField, noteField, hostField, portField, userField].forEach {
            $0.inputAccessoryView = toolbar
        }
    }

    private func configureContent() {
        let saveButton = UIButton(type: .system)
        saveButton.configuration = .filled()
        saveButton.configuration?.title = "Save Host"
        saveButton.addTarget(self, action: #selector(saveHost), for: .touchUpInside)

        let favoriteLabel = UILabel()
        favoriteLabel.text = "Favorite"
        favoriteLabel.font = .preferredFont(forTextStyle: .body)

        let favoriteRow = UIStackView(arrangedSubviews: [favoriteLabel, favoriteSwitch])
        favoriteRow.axis = .horizontal
        favoriteRow.distribution = .equalSpacing

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [vaultField, nameField, noteField, hostField, portField, userField, favoriteRow, saveButton].forEach {
            contentStack.addArrangedSubview($0)
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func loadHostValues() {
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

        dismiss(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case vaultField:
            nameField.becomeFirstResponder()
        case nameField:
            noteField.becomeFirstResponder()
        case noteField:
            hostField.becomeFirstResponder()
        case hostField:
            portField.becomeFirstResponder()
        case portField:
            userField.becomeFirstResponder()
        case userField:
            saveHost()
        default:
            textField.resignFirstResponder()
        }
        return true
    }

    @objc
    private func focusPreviousField() {
        focusField(offset: -1)
    }

    @objc
    private func focusNextField() {
        focusField(offset: 1)
    }

    private func focusField(offset: Int) {
        let fields = [vaultField, nameField, noteField, hostField, portField, userField]
        guard let currentIndex = fields.firstIndex(where: { $0.isFirstResponder }) else {
            fields.first?.becomeFirstResponder()
            return
        }

        let nextIndex = currentIndex + offset
        guard fields.indices.contains(nextIndex) else {
            dismissKeyboard()
            return
        }
        fields[nextIndex].becomeFirstResponder()
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc
    private func closeScreen() {
        dismiss(animated: true)
    }
}

@MainActor
final class RebootConnectionsViewController: UIViewController, UITextFieldDelegate {
    private let model: RebootAppModel
    private weak var router: (any RebootPhoneRouting)?

    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
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
    private var lastFailureSignature: String?

    init(model: RebootAppModel, router: any RebootPhoneRouting) {
        self.model = model
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        configureFormChrome()
        configureHeader()

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
        hostField.returnKeyType = .next
        portField.placeholder = "Port"
        portField.keyboardType = .numberPad
        portField.text = "22"
        userField.returnKeyType = .next
        userField.placeholder = "Username"
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .go
        configureKeyboardAccessory()

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

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [connectBar, credentialsRow, passwordField, sessionCard, quickHostsCard, controls, statusLabel].forEach { contentStack.addArrangedSubview($0) }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
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
        router?.showTerminal()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case hostField:
            userField.becomeFirstResponder()
        case userField:
            passwordField.becomeFirstResponder()
        case passwordField:
            connectSSH()
        default:
            textField.resignFirstResponder()
        }
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

    private func configureHeader() {
        titleLabel.text = "Connections"
        titleLabel.font = .systemFont(ofSize: 36, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    private func prefill(_ host: RebootHost) {
        model.selectedHostID = host.id
        hostField.text = host.hostname
        portField.text = String(host.port)
        userField.text = host.username
    }

    private func promptPasswordAndConnect(host: RebootHost) {
        Task { [weak self] in
            guard let self else { return }
            if await self.model.hasSavedPassword(for: host) {
                self.passwordField.text = ""
                self.model.connect(host: host, password: "")
                self.openTerminalIfNeeded()
            } else {
                self.view.endEditing(true)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.presentedViewController == nil else { return }
                    let prompt = RebootPasswordPromptViewController(hostName: host.name) { [weak self] password in
                        guard let self else { return }
                        self.passwordField.text = ""
                        self.model.connect(host: host, password: password)
                        self.openTerminalIfNeeded()
                    }
                    prompt.modalPresentationStyle = .overFullScreen
                    prompt.modalTransitionStyle = .crossDissolve
                    self.present(prompt, animated: true)
                }
            }
        }
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

        switch state.sessionState {
        case .failed:
            let signature = "\(state.connectionTitle)|\(state.statusMessage)"
            if lastFailureSignature != signature {
                lastFailureSignature = signature
                presentConnectionFailureAlert(message: state.statusMessage)
            }
        case .connected, .idle:
            lastFailureSignature = nil
        case .connecting:
            break
        }
    }

    private func presentConnectionFailureAlert(message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Connection Failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func openTerminalIfNeeded() {
        guard !didAutoOpenTerminal else { return }
        didAutoOpenTerminal = true
        openTerminal()
    }

    private func configureFormChrome() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func configureKeyboardAccessory() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(title: "Previous", style: .plain, target: self, action: #selector(focusPreviousField)),
            UIBarButtonItem(title: "Next", style: .plain, target: self, action: #selector(focusNextField)),
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        ]
        [hostField, userField, portField, passwordField].forEach { $0.inputAccessoryView = toolbar }
    }

    @objc
    private func focusPreviousField() {
        focusField(offset: -1)
    }

    @objc
    private func focusNextField() {
        focusField(offset: 1)
    }

    private func focusField(offset: Int) {
        let fields = [hostField, userField, portField, passwordField]
        guard let currentIndex = fields.firstIndex(where: { $0.isFirstResponder }) else {
            fields.first?.becomeFirstResponder()
            return
        }
        let nextIndex = currentIndex + offset
        guard fields.indices.contains(nextIndex) else {
            dismissKeyboard()
            return
        }
        fields[nextIndex].becomeFirstResponder()
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }
}

@MainActor
final class RebootPasswordPromptViewController: UIViewController, UITextFieldDelegate {
    private let hostName: String
    private let onConnect: (String) -> Void

    private let dimView = UIView()
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let passwordField = UITextField()
    private let cancelButton = UIButton(type: .system)
    private let connectButton = UIButton(type: .system)

    init(hostName: String, onConnect: @escaping (String) -> Void) {
        self.hostName = hostName
        self.onConnect = onConnect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureLayout()
        configureKeyboardDismissTap()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        passwordField.becomeFirstResponder()
    }

    private func configureLayout() {
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 18
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        titleLabel.text = "Connect \(hostName)"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label

        subtitleLabel.text = "Enter SSH password"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        passwordField.borderStyle = .roundedRect
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.autocorrectionType = .no
        passwordField.spellCheckingType = .no
        passwordField.smartDashesType = .no
        passwordField.smartQuotesType = .no
        passwordField.smartInsertDeleteType = .no
        passwordField.keyboardType = .asciiCapable
        passwordField.returnKeyType = .go
        passwordField.enablesReturnKeyAutomatically = true
        passwordField.delegate = self

        cancelButton.configuration = .tinted()
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        connectButton.configuration = .filled()
        connectButton.configuration?.title = "Connect"
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [cancelButton, connectButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, passwordField, buttons])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),

            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            passwordField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureKeyboardDismissTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
    }

    @objc
    private func dimTapped() {
        dismiss(animated: true)
    }

    @objc
    private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc
    private func connectTapped() {
        let password = passwordField.text ?? ""
        dismiss(animated: true) { [onConnect] in
            onConnect(password)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        connectTapped()
        return true
    }
}

@MainActor
final class RebootTerminalViewController: UIViewController, UITextViewDelegate {
    private let model: RebootAppModel
    private let titleLabel = UILabel()
    private let outputView = UITextView()
    private let sessionRow = UIStackView()
    private let previousCommandButton = UIButton(type: .system)
    private let activeSessionButton = UIButton(type: .system)
    private let sessionActionsButton = UIButton(type: .system)
    private let shortcutsScrollView = UIScrollView()
    private let shortcutsRow = UIStackView()
    private let keyboardInputField = RebootTerminalInputProxyView()
    private var terminalObserverID: UUID?
    private var lastAppliedTerminalSize: TerminalSize?
    private var isFollowingTail = true
    private var isInteractingWithTerminalScroll = false
    private var currentInputBuffer = ""
    private var commandHistory: [String] = []
    private var historyCursor: Int?

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
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)
        configureHeader()

        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        outputView.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1)
        outputView.textColor = UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1)
        outputView.layer.cornerRadius = 6
        outputView.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 2)
        outputView.textContainer.lineFragmentPadding = 0
        outputView.textContainer.lineBreakMode = .byWordWrapping
        outputView.translatesAutoresizingMaskIntoConstraints = false
        outputView.isScrollEnabled = true
        outputView.alwaysBounceVertical = true
        outputView.keyboardDismissMode = .interactive
        outputView.isSelectable = true
        outputView.delegate = self
        outputView.panGestureRecognizer.addTarget(self, action: #selector(handleTerminalPan(_:)))

        shortcutsScrollView.showsHorizontalScrollIndicator = false
        shortcutsScrollView.alwaysBounceHorizontal = true
        shortcutsScrollView.alwaysBounceVertical = false
        shortcutsScrollView.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)
        shortcutsScrollView.layer.cornerRadius = 12

        shortcutsRow.axis = .horizontal
        shortcutsRow.spacing = 8
        shortcutsRow.distribution = .fillProportionally
        shortcutsRow.alignment = .fill
        let shortcutKeys: [(String, String)] = [
            ("esc", "\u{1B}"),
            ("tab", "\t"),
            ("ctrl", "\u{3}"),
            ("alt", ""),
            ("/", "/"),
            ("|", "|"),
            ("~", "~"),
            ("-", "-"),
            ("copy", ""),
            ("paste", ""),
            ("^C", "\u{3}"),
            ("^\\", "\u{1C}")
        ]
        for item in shortcutKeys {
            let button = makeSoftKeyButton(item.0)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if item.0 == "copy" {
                    self.copyTerminalText()
                } else if item.0 == "paste" {
                    self.pasteTerminalText()
                } else if !item.1.isEmpty {
                    self.model.send(item.1)
                }
            }, for: .touchUpInside)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            shortcutsRow.addArrangedSubview(button)
        }
        shortcutsRow.translatesAutoresizingMaskIntoConstraints = false
        shortcutsScrollView.addSubview(shortcutsRow)
        NSLayoutConstraint.activate([
            shortcutsRow.leadingAnchor.constraint(equalTo: shortcutsScrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            shortcutsRow.trailingAnchor.constraint(equalTo: shortcutsScrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            shortcutsRow.topAnchor.constraint(equalTo: shortcutsScrollView.contentLayoutGuide.topAnchor, constant: 6),
            shortcutsRow.bottomAnchor.constraint(equalTo: shortcutsScrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            shortcutsRow.heightAnchor.constraint(equalTo: shortcutsScrollView.frameLayoutGuide.heightAnchor, constant: -12)
        ])

        configureSessionRow()

        let bottomStack = UIStackView(arrangedSubviews: [sessionRow, shortcutsScrollView])
        bottomStack.axis = .vertical
        bottomStack.spacing = 8
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        keyboardInputField.tintColor = .clear
        keyboardInputField.backgroundColor = .clear
        keyboardInputField.translatesAutoresizingMaskIntoConstraints = false
        keyboardInputField.onInsertText = { [weak self] text in
            self?.handleTerminalInsertedText(text)
        }
        keyboardInputField.onDeleteBackward = { [weak self] in
            self?.handleTerminalBackspace()
        }

        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusKeyboard))
        focusTap.cancelsTouchesInView = false
        outputView.addGestureRecognizer(focusTap)

        view.addSubview(outputView)
        view.addSubview(bottomStack)
        view.addSubview(keyboardInputField)
        NSLayoutConstraint.activate([
            outputView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
            outputView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            outputView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            outputView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -16),

            bottomStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomStack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),

            sessionRow.heightAnchor.constraint(equalToConstant: 44),
            shortcutsScrollView.heightAnchor.constraint(equalToConstant: 44),

            keyboardInputField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardInputField.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardInputField.widthAnchor.constraint(equalToConstant: 1),
            keyboardInputField.heightAnchor.constraint(equalToConstant: 1)
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusKeyboard()
        applyTerminalGeometryIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyTerminalGeometryIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboardInputField.resignFirstResponder()
        if let terminalObserverID {
            model.removeTerminalObserver(id: terminalObserverID)
            self.terminalObserverID = nil
        }
    }

    private func render(state: TerminalSurfaceState) {
        titleLabel.text = state.connectionTitle.isEmpty ? "Terminal" : state.connectionTitle
        applySessionStatus(state.sessionState)
        let shouldScrollToBottom = isFollowingTail && !isInteractingWithTerminalScroll
        let currentOffset = outputView.contentOffset
        let transcript = state.transcript
        let cursorSuffix = state.sessionState == .connected ? "█" : ""
        let renderedText = transcript.isEmpty
            ? state.statusMessage
            : transcript + cursorSuffix
        outputView.text = renderedText
        if shouldScrollToBottom {
            scrollOutputToBottom()
            isFollowingTail = true
        } else if outputView.contentSize.height > 0 {
            let maxOffsetY = max(
                -outputView.adjustedContentInset.top,
                outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
            )
            let restoredOffset = CGPoint(
                x: 0,
                y: min(max(currentOffset.y, -outputView.adjustedContentInset.top), maxOffsetY)
            )
            outputView.setContentOffset(restoredOffset, animated: false)
        }
    }

    @objc
    private func focusKeyboard() {
        isFollowingTail = true
        keyboardInputField.becomeFirstResponder()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        isInteractingWithTerminalScroll = true
        isFollowingTail = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        if !isInteractingWithTerminalScroll {
            isFollowingTail = isNearBottom(scrollView)
        } else if !isNearBottom(scrollView) {
            isFollowingTail = false
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === outputView, !decelerate else { return }
        isInteractingWithTerminalScroll = false
        isFollowingTail = isNearBottom(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === outputView else { return }
        isInteractingWithTerminalScroll = false
        isFollowingTail = isNearBottom(scrollView)
    }

    @objc
    private func handleTerminalPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            isInteractingWithTerminalScroll = true
            isFollowingTail = false
        case .ended, .cancelled, .failed:
            isInteractingWithTerminalScroll = false
            isFollowingTail = isNearBottom(outputView)
        default:
            break
        }
    }

    private func scrollOutputToBottom() {
        let maxOffsetY = max(
            -outputView.adjustedContentInset.top,
            outputView.contentSize.height - outputView.bounds.height + outputView.adjustedContentInset.bottom
        )
        outputView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
    }

    private func isNearBottom(_ scrollView: UIScrollView, threshold: CGFloat = 16) -> Bool {
        let maxOffsetY = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        return scrollView.contentOffset.y >= (maxOffsetY - threshold)
    }

    private func handleTerminalInsertedText(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else {
            return
        }
        captureInputForLocalHistory(normalized)
        model.send(normalized)
    }

    private func handleTerminalBackspace() {
        if !currentInputBuffer.isEmpty {
            currentInputBuffer.removeLast()
        }
        historyCursor = nil
        model.send("\u{7F}")
    }

    private func captureInputForLocalHistory(_ text: String) {
        for character in text {
            if character == "\n" {
                commitCurrentInputToHistory()
                continue
            }

            currentInputBuffer.append(character)
            historyCursor = nil
        }
    }

    private func commitCurrentInputToHistory() {
        let command = currentInputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        currentInputBuffer = ""
        historyCursor = nil

        guard !command.isEmpty else {
            return
        }

        if commandHistory.last != command {
            commandHistory.append(command)
            if commandHistory.count > 100 {
                commandHistory.removeFirst(commandHistory.count - 100)
            }
        }
    }

    private func recallPreviousCommandFromHistory() {
        guard !commandHistory.isEmpty else {
            return
        }

        let nextIndex: Int
        if let historyCursor {
            nextIndex = max(0, historyCursor - 1)
        } else {
            nextIndex = commandHistory.count - 1
        }

        historyCursor = nextIndex
        replaceCurrentInput(with: commandHistory[nextIndex])
    }

    private func replaceCurrentInput(with command: String) {
        if !currentInputBuffer.isEmpty {
            for _ in currentInputBuffer {
                model.send("\u{7F}")
            }
        }
        model.send(command)
        currentInputBuffer = command
    }

    private func configureSessionRow() {
        sessionRow.axis = .horizontal
        sessionRow.spacing = 8
        sessionRow.distribution = .fill
        sessionRow.alignment = .fill
        sessionRow.translatesAutoresizingMaskIntoConstraints = false

        styleSessionButton(previousCommandButton, title: "<")
        previousCommandButton.addAction(UIAction { [weak self] _ in
            self?.recallPreviousCommandFromHistory()
            self?.focusKeyboard()
        }, for: .touchUpInside)

        styleSessionButton(activeSessionButton, title: "idle")
        activeSessionButton.addAction(UIAction { [weak self] _ in
            self?.presentSessionSwitcher()
        }, for: .touchUpInside)

        styleSessionButton(sessionActionsButton, title: "+")
        sessionActionsButton.addAction(UIAction { [weak self] _ in
            self?.presentSessionActions()
        }, for: .touchUpInside)

        sessionRow.addArrangedSubview(previousCommandButton)
        sessionRow.addArrangedSubview(activeSessionButton)
        sessionRow.addArrangedSubview(sessionActionsButton)

        previousCommandButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        sessionActionsButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
    }

    private func styleSessionButton(_ button: UIButton, title: String) {
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.baseForegroundColor = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        button.configuration?.baseBackgroundColor = UIColor(red: 0.22, green: 0.25, blue: 0.39, alpha: 1)
        button.configuration?.cornerStyle = .large
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    }

    private func applySessionStatus(_ sessionState: TerminalConnectionState) {
        let stateTitle: String
        switch sessionState {
        case .idle:
            stateTitle = "idle"
        case .connecting:
            stateTitle = "connecting"
        case .connected:
            stateTitle = "active"
        case .failed:
            stateTitle = "failed"
        }

        let summaries = model.terminalSessionSummaries()
        let activeSummary = summaries.first(where: \.isActive)
        if let activeSummary {
            let compact = compactSessionTitle(activeSummary.title)
            activeSessionButton.configuration?.title = compact
            activeSessionButton.configuration?.subtitle = stateTitle
        } else {
            activeSessionButton.configuration?.title = stateTitle
            activeSessionButton.configuration?.subtitle = nil
        }
        sessionActionsButton.configuration?.title = summaries.count > 1 ? "+\(summaries.count)" : "+"
    }

    private func compactSessionTitle(_ rawTitle: String) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return "session"
        }
        let maxLength = 16
        if title.count <= maxLength {
            return title
        }
        let head = title.prefix(12)
        return "\(head)…"
    }

    private func presentSessionActions() {
        let sheet = UIAlertController(title: "Session", message: nil, preferredStyle: .actionSheet)
        let summaries = model.terminalSessionSummaries()

        sheet.addAction(UIAlertAction(title: "New Session", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            _ = self.model.createTerminalSession(makeActive: true)
            self.currentInputBuffer = ""
            self.historyCursor = nil
            self.isFollowingTail = true
            self.scrollOutputToBottom()
            self.focusKeyboard()
        }))

        if summaries.count > 1 {
            sheet.addAction(UIAlertAction(title: "Switch Session", style: .default, handler: { [weak self] _ in
                self?.presentSessionSwitcher()
            }))
            sheet.addAction(UIAlertAction(title: "Close Active Session", style: .destructive, handler: { [weak self] _ in
                guard let self else { return }
                self.model.closeActiveTerminalSession()
                self.currentInputBuffer = ""
                self.historyCursor = nil
                self.isFollowingTail = true
                self.scrollOutputToBottom()
                self.focusKeyboard()
            }))
        }

        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
            sheet.addAction(UIAlertAction(title: "Paste Clipboard", style: .default, handler: { [weak self] _ in
                self?.model.send(clipboard)
                self?.focusKeyboard()
            }))
        }

        sheet.addAction(UIAlertAction(title: "Send Ctrl+C", style: .default, handler: { [weak self] _ in
            self?.model.send("\u{3}")
            self?.focusKeyboard()
        }))

        sheet.addAction(UIAlertAction(title: "Clear Screen", style: .default, handler: { [weak self] _ in
            self?.model.send("\u{C}")
            self?.focusKeyboard()
        }))

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sessionActionsButton
            popover.sourceRect = sessionActionsButton.bounds
        }
        present(sheet, animated: true)
    }

    private func presentSessionSwitcher() {
        let summaries = model.terminalSessionSummaries()
        guard !summaries.isEmpty else {
            return
        }

        let sheet = UIAlertController(title: "Sessions", message: nil, preferredStyle: .actionSheet)
        for summary in summaries {
            let stateLabel = summary.sessionState.rawValue
            let marker = summary.isActive ? "• " : ""
            let title = "\(marker)\(summary.title) (\(stateLabel))"
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                guard let self else { return }
                self.model.switchToTerminalSession(summary.id)
                self.currentInputBuffer = ""
                self.historyCursor = nil
                self.isFollowingTail = true
                self.scrollOutputToBottom()
                self.focusKeyboard()
            }))
        }

        if summaries.count > 1 {
            sheet.addAction(UIAlertAction(title: "Close Active Session", style: .destructive, handler: { [weak self] _ in
                guard let self else { return }
                self.model.closeActiveTerminalSession()
                self.currentInputBuffer = ""
                self.historyCursor = nil
                self.isFollowingTail = true
                self.scrollOutputToBottom()
                self.focusKeyboard()
            }))
        }

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = activeSessionButton
            popover.sourceRect = activeSessionButton.bounds
        }
        present(sheet, animated: true)
    }

    private func applyTerminalGeometryIfNeeded() {
        guard outputView.bounds.width > 80, outputView.bounds.height > 120 else {
            return
        }

        let font = outputView.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let insets = outputView.textContainerInset
        let linePadding = outputView.textContainer.lineFragmentPadding * 2
        let usableWidth = max(0, outputView.bounds.width - insets.left - insets.right - linePadding)
        let usableHeight = max(0, outputView.bounds.height - insets.top - insets.bottom)
        let glyphWidth = max(6.0, "W".size(withAttributes: [.font: font]).width)
        let rowHeight = max(10.0, font.lineHeight)

        let columns = Int(floor(usableWidth / glyphWidth))
        let rows = Int(floor(usableHeight / rowHeight))
        let screenScale = view.window?.screen.scale ?? UIScreen.main.scale
        let terminalSize = TerminalSize(
            columns: max(40, min(160, columns)),
            rows: max(18, rows),
            pixelWidth: Int(outputView.bounds.width * screenScale),
            pixelHeight: Int(outputView.bounds.height * screenScale)
        )

        guard terminalSize != lastAppliedTerminalSize else {
            return
        }
        lastAppliedTerminalSize = terminalSize
        model.resizeTerminal(
            columns: terminalSize.columns,
            rows: terminalSize.rows,
            pixelWidth: terminalSize.pixelWidth,
            pixelHeight: terminalSize.pixelHeight
        )
    }

    private func makeSoftKeyButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = title
        button.configuration?.baseForegroundColor = UIColor(red: 0.69, green: 0.78, blue: 0.94, alpha: 1)
        button.configuration?.baseBackgroundColor = UIColor(red: 0.13, green: 0.22, blue: 0.43, alpha: 1)
        button.configuration?.cornerStyle = .capsule
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        return button
    }

    private func copyTerminalText() {
        let text = outputView.text ?? ""
        let payload: String
        if outputView.selectedRange.length > 0,
           let range = Range(outputView.selectedRange, in: text) {
            payload = String(text[range])
        } else {
            payload = text
        }
        guard !payload.isEmpty else {
            return
        }
        UIPasteboard.general.string = payload
    }

    private func pasteTerminalText() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            return
        }
        model.send(text)
    }

    private func configureHeader() {
        let closeButton = UIButton(type: .system)
        closeButton.configuration = .plain()
        closeButton.configuration?.image = UIImage(systemName: "chevron.left")
        closeButton.configuration?.baseForegroundColor = .white
        closeButton.addTarget(self, action: #selector(closeScreen), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Terminal"
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    @objc
    private func closeScreen() {
        dismiss(animated: true)
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
        External monitor mirroring is planned for Phase 3 after phone flow stabilization.
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
