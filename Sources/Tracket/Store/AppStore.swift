import AppKit
import Foundation

enum SidebarSelection: Hashable {
    case dashboard
    case project(UUID)
    case settings
}

@MainActor
final class AppStore: ObservableObject {
    @Published var projects: [TracketProject]
    @Published var selection: SidebarSelection = .dashboard
    @Published var isAddingProject = false
    @Published var isWorking = false
    @Published var workingProjectID: UUID?
    @Published var alertMessage: String?
    @Published var hasAPIKey: Bool
    @Published var notificationsEnabled = false
    @Published var activities: [ProjectActivityEvent]
    @Published var monitoringEnabled: Bool
    @Published var remoteSyncEnabled: Bool
    @Published var monitorIntervalMinutes: Int
    @Published var lastMonitorAt: Date?
    @Published var isBackgroundScanning = false
    @Published var connections: [DeveloperConnection]
    @Published var isConnectingProvider: ConnectionProvider?
    @Published var aiSettings: AISettings
    @Published var configuredAIProviders: Set<CloudAIProvider>
    @Published var localModelStates: [LocalAIModel: LocalModelState] = [:]
    @Published var projectAIWorkspaces: [UUID: ProjectAIWorkspace]
    @Published var aiChattingProjectIDs: Set<UUID> = []

    private var persistence: PersistenceStore
    private var projectAIWorkspaceStore: ProjectAIWorkspaceStore
    private let keychain = KeychainService()
    private let ai = AIService()
    private let notifications = NotificationService()
    private let folderAccess = FolderAccessService()
    private let hookInbox = HookInboxService()
    private let codexHooks = CodexHookInstaller()
    private let codexDiscovery = CodexProjectDiscovery()
    private let localAppDiscovery = LocalAppProjectDiscovery()
    private let localDiscovery = LocalProjectDiscovery()
    private let cloudImport = CloudProjectImportService()
    private let cloudflareMCP = CloudflareMCPService()
    private let renderMCP = RenderMCPService()
    private let githubCLIAuth = GitHubCLIAuthService()
    private let providerUsage = ProviderUsageService()
    private let codexUsage = CodexUsageService()
    private let localToolUsage = LocalToolUsageService()
    private let oauth = OAuthService()
    private var monitoringTask: Task<Void, Never>?
    private var modelDownloadTasks: [LocalAIModel: Task<Void, Never>] = [:]

    init(
        persistence: PersistenceStore = PersistenceStore(),
        projectAIWorkspaceStore: ProjectAIWorkspaceStore = ProjectAIWorkspaceStore()
    ) {
        self.persistence = persistence
        self.projectAIWorkspaceStore = projectAIWorkspaceStore
        self.projects = persistence.loadProjects()
        self.activities = persistence.loadActivities()
        self.monitoringEnabled = persistence.monitoringEnabled
        self.remoteSyncEnabled = persistence.remoteSyncEnabled
        self.monitorIntervalMinutes = persistence.monitorIntervalMinutes
        self.lastMonitorAt = persistence.lastMonitorAt
        self.connections = persistence.loadConnections()
        self.aiSettings = persistence.loadAISettings()
        self.projectAIWorkspaces = projectAIWorkspaceStore.loadAll()
        var configuredAIProviders = persistence.configuredAIProviders
        if persistence.hasOpenAIKeyConfigured { configuredAIProviders.insert(.openAI) }
        self.configuredAIProviders = configuredAIProviders
        // Do not read Keychain during launch. Ad-hoc development builds can have
        // a changing code requirement, which would otherwise display a password
        // prompt every time Tracket starts.
        self.hasAPIKey = persistence.hasOpenAIKeyConfigured
        self.persistence.configuredAIProviders = configuredAIProviders
        folderAccess.restoreAccess(for: projects.filter(\.isLocalProject).map(\.path))

        if ProcessInfo.processInfo.arguments.contains("--demo"), projects.isEmpty {
            projects = DemoData.projects
            if activities.isEmpty { activities = DemoData.activities(for: projects) }
        }

        Task { @MainActor [weak self] in
            self?.startMonitoring()
            await self?.refreshLocalModelStates()
        }
    }

    var selectedProject: TracketProject? {
        guard case .project(let id) = selection else { return nil }
        return projects.first(where: { $0.id == id })
    }

    var activeProjects: [TracketProject] {
        projects.filter { $0.stage != .live }
    }

    var atRiskProjects: [TracketProject] {
        activeProjects.filter(\.isAtRisk)
    }

    var averageMomentum: Int {
        guard !activeProjects.isEmpty else { return 0 }
        return activeProjects.map(\.momentumScore).reduce(0, +) / activeProjects.count
    }

    var recentActivities: [ProjectActivityEvent] {
        Array(activities.sorted { $0.occurredAt > $1.occurredAt }.prefix(20))
    }

    var recentDevelopmentProjects: [TracketProject] {
        projects
            .filter { $0.isLocalProject && $0.latestDevelopmentTool != nil }
            .sorted { $0.latestDevelopmentActivityAt > $1.latestDevelopmentActivityAt }
    }

    func recentActivities(for projectID: UUID, limit: Int = 8) -> [ProjectActivityEvent] {
        Array(activities
            .filter { $0.projectID == projectID }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(limit))
    }

    func projectName(for activity: ProjectActivityEvent) -> String {
        projects.first(where: { $0.id == activity.projectID })?.name ?? "Unknown project"
    }

    func addProject(from url: URL, goal: String, deadline: Date) {
        guard !projects.contains(where: { $0.path == url.path }) else {
            alertMessage = "That project is already tracked."
            return
        }

        folderAccess.remember(url)
        isWorking = true
        Task {
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try ProjectScanner().scan(url: url)
                }.value
                let project = TracketProject(
                    name: snapshot.name,
                    path: snapshot.path,
                    goal: goal.nilIfBlank ?? "Ship a small, useful version to real users.",
                    stage: snapshot.stage,
                    lastActivityAt: snapshot.lastActivityAt,
                    deadline: deadline,
                    branch: snapshot.branch,
                    remoteURL: snapshot.remoteURL,
                    deploymentURL: nil,
                    uncommittedChanges: snapshot.uncommittedChanges,
                    commitCountLast7Days: snapshot.commitCountLast7Days,
                    detectedTools: snapshot.detectedTools,
                    languages: snapshot.languages,
                    roadmap: Self.defaultRoadmap(stage: snapshot.stage, deadline: deadline),
                    aiSummary: nil,
                    nextSuggestion: "Finish the smallest end-to-end path, then put it in front of one real user.",
                    headCommit: snapshot.headCommit,
                    headCommitMessage: snapshot.headCommitMessage,
                    upstreamBranch: snapshot.upstreamBranch,
                    aheadCount: snapshot.aheadCount,
                    behindCount: snapshot.behindCount,
                    toolActivity: snapshot.toolActivity,
                    lastMonitorAt: Date()
                )
                projects.append(project)
                addActivities([
                    ProjectActivityEvent(
                        projectID: project.id,
                        source: .system,
                        kind: .monitoring,
                        title: "Background tracking started",
                        detail: "Tracket will keep watching this project from the menu bar.",
                        fingerprint: "tracking-started-\(project.id.uuidString)"
                    )
                ])
                projects.sort { $0.lastActivityAt > $1.lastActivityAt }
                selection = .project(project.id)
                isAddingProject = false
                save()
                if notificationsEnabled { try? await notifications.scheduleNudge(for: project) }
            } catch {
                alertMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    func rescan(_ project: TracketProject) {
        workingProjectID = project.id
        Task {
            do {
                let url = URL(fileURLWithPath: project.path)
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try ProjectScanner().scan(url: url, fetchRemote: false)
                }.value
                applySnapshot(snapshot, to: project.id, recordActivity: true)
            } catch {
                alertMessage = error.localizedDescription
            }
            workingProjectID = nil
        }
    }

    func generateAIPlan(for project: TracketProject) {
        workingProjectID = project.id
        Task {
            do {
                let key = cloudAPIKey(for: aiSettings.cloudProvider)
                let plan = try await ai.createPlan(for: project, settings: aiSettings, cloudAPIKey: key)
                apply(plan, to: project.id)
            } catch {
                if case AIProviderError.missingAPIKey = error { selection = .settings }
                if case AIProviderError.localModelRequired = error { selection = .settings }
                alertMessage = error.localizedDescription
            }
            workingProjectID = nil
        }
    }

    func projectAIWorkspace(for projectID: UUID) -> ProjectAIWorkspace {
        projectAIWorkspaces[projectID] ?? ProjectAIWorkspace(projectID: projectID)
    }

    var activeAIProviderTitle: String {
        switch aiSettings.mode {
        case .local:
            "Local · \(aiSettings.localModel.title)"
        case .cloud:
            "\(aiSettings.cloudProvider.title) · \(aiSettings.effectiveModel)"
        case .smartHybrid:
            "Smart hybrid · \(aiSettings.localModel.title) first"
        }
    }

    var activeAIChatContextTitle: String {
        aiSettings.mode == .local
            ? "Relevant project files · private on this Mac"
            : aiSettings.contextSharing.title
    }

    func sendProjectAIMessage(_ message: String, projectID: UUID) {
        let question = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty,
              !aiChattingProjectIDs.contains(projectID),
              let project = projects.first(where: { $0.id == projectID }) else { return }

        var workspace = projectAIWorkspace(for: projectID)
        let sessionID = workspace.currentSessionID
        workspace.append(ProjectChatMessage(role: .user, content: question), to: sessionID)
        persistProjectAIWorkspace(workspace)
        aiChattingProjectIDs.insert(projectID)

        Task {
            defer { aiChattingProjectIDs.remove(projectID) }
            do {
                let key = cloudAPIKey(for: aiSettings.cloudProvider)
                let response = try await ai.chat(
                    for: project,
                    workspace: workspace,
                    question: question,
                    settings: aiSettings,
                    cloudAPIKey: key
                )
                var updated = projectAIWorkspace(for: projectID)
                updated.append(ProjectChatMessage(role: .assistant, content: response.answer), to: sessionID)
                updated.memory = ProjectAIMemory(
                    summary: response.memorySummary,
                    skills: response.skills,
                    updatedAt: Date()
                )
                persistProjectAIWorkspace(updated)
            } catch {
                if case AIProviderError.missingAPIKey = error { selection = .settings }
                if case AIProviderError.localModelRequired = error { selection = .settings }
                alertMessage = error.localizedDescription
            }
        }
    }

    func startNewProjectAISession(projectID: UUID) {
        guard !aiChattingProjectIDs.contains(projectID) else { return }
        var workspace = projectAIWorkspace(for: projectID)
        if workspace.currentSession.messages.isEmpty { return }
        workspace.startNewSession()
        persistProjectAIWorkspace(workspace)
    }

    func selectProjectAISession(projectID: UUID, sessionID: UUID) {
        guard !aiChattingProjectIDs.contains(projectID) else { return }
        var workspace = projectAIWorkspace(for: projectID)
        guard workspace.sessions.contains(where: { $0.id == sessionID }) else { return }
        workspace.currentSessionID = sessionID
        persistProjectAIWorkspace(workspace)
    }

    func isConnected(_ provider: ConnectionProvider) -> Bool {
        connections.contains { $0.provider == provider && $0.lastError == nil }
    }

    func connection(for provider: ConnectionProvider) -> DeveloperConnection? {
        connections.first { $0.provider == provider }
    }

    func connectLocalAdapter(_ provider: ConnectionProvider) {
        guard provider.mode == .localAdapter else { return }
        if provider == .codex {
            connectCodexApp()
            return
        }
        connectAutomaticLocalApp(provider)
    }

    func oauthClientID(for provider: ConnectionProvider) -> String? {
        if provider == .render { return "codex" }
        let key: String = switch provider {
        case .github: "TracketGitHubOAuthClientID"
        case .cloudflare: "TracketCloudflareOAuthClientID"
        case .vercel: "TracketVercelOAuthClientID"
        default: ""
        }
        guard !key.isEmpty else { return nil }
        // Distribution builds own the OAuth registration. The persisted value is
        // retained only as a backwards-compatible development override.
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.nilIfBlank
            ?? persistence.oauthClientID(for: provider)
    }

    func connectCloudOAuth(_ provider: ConnectionProvider) {
        let clientID = oauthClientID(for: provider)
        isConnectingProvider = provider
        Task {
            do {
                let credential: OAuthCredential
                if provider == .github, clientID == nil {
                    credential = try await githubCLIAuth.authenticate()
                } else {
                    credential = try await oauth.authorize(
                        provider: provider,
                        clientID: clientID,
                        devicePrompt: { [weak self] code in
                            self?.alertMessage = "GitHub authorization code \(code) was copied. Paste it in the browser to continue."
                        }
                    )
                }
                try saveOAuthCredential(credential, provider: provider)
                let result = try await fetchCloudProjects(provider: provider, accessToken: credential.accessToken)
                let importedIDs = importCloudProjects(result.projects)
                upsertConnection(
                    provider: provider,
                    accountName: result.accountName,
                    roots: [],
                    importedCount: result.projects.count,
                    error: nil
                )
                await refreshProviderUsage(provider, accessToken: credential.accessToken)
                await assessImportedProjects(importedIDs)
                alertMessage = "\(provider.title) connected. Imported or refreshed \(result.projects.count) projects."
            } catch {
                alertMessage = error.localizedDescription
                upsertConnection(provider: provider, accountName: nil, roots: [], importedCount: 0, error: error.localizedDescription)
            }
            isConnectingProvider = nil
        }
    }

    func syncConnection(_ provider: ConnectionProvider) {
        guard connection(for: provider) != nil else { return }
        if provider == .codex {
            connectCodexApp()
            return
        }
        if provider.mode == .localAdapter {
            connectAutomaticLocalApp(provider)
        } else {
            isConnectingProvider = provider
            Task {
                defer { isConnectingProvider = nil }
                do {
                    guard let accessToken = try await validAccessToken(for: provider) else {
                        throw OAuthServiceError.provider("Reconnect \(provider.title) to restore OAuth access.")
                    }
                    let result = try await fetchCloudProjects(provider: provider, accessToken: accessToken)
                    let importedIDs = importCloudProjects(result.projects)
                    upsertConnection(
                        provider: provider,
                        accountName: result.accountName,
                        roots: [],
                        importedCount: result.projects.count,
                        error: nil
                    )
                    await refreshProviderUsage(provider, accessToken: accessToken)
                    await assessImportedProjects(importedIDs)
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    func disconnect(_ provider: ConnectionProvider) {
        try? keychain.deleteSecret(account: credentialAccount(provider))
        connections.removeAll { $0.provider == provider }
        persistence.saveConnections(connections)
        alertMessage = "\(provider.title) disconnected. Already imported projects remain in Tracket."
    }

    func toggleRoadmapItem(projectID: UUID, itemID: UUID) {
        let roadmapItem = projects
            .first(where: { $0.id == projectID })?
            .roadmap.first(where: { $0.id == itemID })
        update(projectID) { project in
            guard let index = project.roadmap.firstIndex(where: { $0.id == itemID }) else { return }
            let wasDone = project.roadmap[index].status == .done
            project.roadmap[index].status = wasDone ? .todo : .done

            if !wasDone,
               !project.roadmap.contains(where: { $0.status == .active }),
               let next = project.roadmap.firstIndex(where: { $0.status == .todo }) {
                project.roadmap[next].status = .active
            }
            if project.roadmap.allSatisfy({ $0.status == .done }) {
                project.stage = project.deploymentURL == nil ? .launchReady : .live
            }
            project.aiCompletionPercent = nil
            project.aiCompletionRationale = nil
            project.aiAssessedAt = nil
        }
        if let roadmapItem {
            let completed = roadmapItem.status != .done
            addActivities([
                ProjectActivityEvent(
                    projectID: projectID,
                    source: .system,
                    kind: .monitoring,
                    title: completed ? "Milestone completed" : "Milestone reopened",
                    detail: roadmapItem.title,
                    fingerprint: "roadmap-\(itemID)-\(completed)-\(Date().timeIntervalSinceReferenceDate)"
                )
            ])
        }
    }

    func updateProject(_ project: TracketProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        save()
    }

    func markLive(projectID: UUID, deploymentURL: String) {
        update(projectID) { project in
            project.deploymentURL = deploymentURL.nilIfBlank
            project.stage = project.deploymentURL == nil ? .launchReady : .live
        }
        if deploymentURL.nilIfBlank != nil {
            addActivities([
                ProjectActivityEvent(
                    projectID: projectID,
                    source: .system,
                    kind: .monitoring,
                    title: "Project marked live",
                    detail: deploymentURL,
                    fingerprint: "live-\(projectID)-\(deploymentURL)"
                )
            ])
        }
    }

    func delete(_ project: TracketProject) {
        notifications.removeNudge(for: project)
        if project.isLocalProject { folderAccess.forget(path: project.path) }
        projects.removeAll { $0.id == project.id }
        activities.removeAll { $0.projectID == project.id }
        projectAIWorkspaces.removeValue(forKey: project.id)
        try? projectAIWorkspaceStore.remove(projectID: project.id)
        selection = .dashboard
        save()
    }

    func saveAPIKey(_ key: String) {
        saveCloudAPIKey(key, for: .openAI)
    }

    func saveCloudAPIKey(_ key: String, for provider: CloudAIProvider) {
        do {
            try keychain.saveSecret(key, account: aiCredentialAccount(provider))
            configuredAIProviders.insert(provider)
            persistence.configuredAIProviders = configuredAIProviders
            if provider == .openAI {
                hasAPIKey = true
                persistence.hasOpenAIKeyConfigured = true
            }
            alertMessage = "\(provider.title) API key saved securely in Keychain."
            if aiSettings.mode != .local {
                let pending = projects
                    .filter { $0.stage != .live && $0.aiCompletionPercent == nil }
                    .map(\.id)
                Task { await assessImportedProjects(pending) }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        removeCloudAPIKey(for: .openAI)
    }

    func removeCloudAPIKey(for provider: CloudAIProvider) {
        do {
            try keychain.deleteSecret(account: aiCredentialAccount(provider))
            configuredAIProviders.remove(provider)
            persistence.configuredAIProviders = configuredAIProviders
            if provider == .openAI {
                hasAPIKey = false
                persistence.hasOpenAIKeyConfigured = false
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func updateAISettings(_ settings: AISettings) {
        aiSettings = settings
        persistence.saveAISettings(settings)
        Task { await refreshLocalModelStates() }
    }

    func downloadLocalModel(_ model: LocalAIModel) {
        guard modelDownloadTasks[model] == nil else { return }
        localModelStates[model] = .downloading(0)
        modelDownloadTasks[model] = Task {
            defer { modelDownloadTasks[model] = nil }
            do {
                try await ai.download(model) { [weak self] progress in
                    Task { @MainActor in self?.localModelStates[model] = .downloading(progress) }
                }
                await refreshLocalModelStates()
                alertMessage = "\(model.title) is ready for private, offline planning."
            } catch is CancellationError {
                await refreshLocalModelStates()
            } catch {
                if Task.isCancelled {
                    await refreshLocalModelStates()
                } else {
                    localModelStates[model] = .failed(error.localizedDescription)
                    alertMessage = "Model download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelLocalModelDownload(_ model: LocalAIModel) {
        modelDownloadTasks[model]?.cancel()
    }

    func removeLocalModel(_ model: LocalAIModel) {
        Task {
            do {
                try await ai.remove(model)
                await refreshLocalModelStates()
            } catch {
                alertMessage = "Could not remove \(model.title): \(error.localizedDescription)"
            }
        }
    }

    func refreshLocalModelStates() async {
        for model in LocalAIModel.allCases {
            localModelStates[model] = await ai.localState(for: model)
        }
    }

    var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    func resetApplication() {
        do {
            for task in modelDownloadTasks.values { task.cancel() }
            modelDownloadTasks = [:]
            for project in projects {
                notifications.removeNudge(for: project)
            }
            notifications.removeAllNudges()
            let removedKeychainItems = try keychain.deleteAllSecrets()
            folderAccess.reset()
            persistence.resetAll()
            try projectAIWorkspaceStore.reset()

            projects = []
            activities = []
            connections = []
            selection = .dashboard
            isAddingProject = false
            isWorking = false
            workingProjectID = nil
            isConnectingProvider = nil
            hasAPIKey = false
            aiSettings = AISettings()
            configuredAIProviders = []
            localModelStates = [:]
            projectAIWorkspaces = [:]
            aiChattingProjectIDs = []
            notificationsEnabled = false
            monitoringEnabled = true
            remoteSyncEnabled = true
            monitorIntervalMinutes = 2
            lastMonitorAt = nil
            alertMessage = removedKeychainItems
                ? "Tracket was reset. Projects, folder links, connected accounts, credentials, and preferences were removed."
                : "Tracket was reset and no longer references any credentials. macOS retained an older protected Keychain item; you can remove it in Keychain Access without reconnecting it to Tracket."
            Task {
                for model in LocalAIModel.allCases { try? await ai.remove(model) }
                await refreshLocalModelStates()
            }
        } catch {
            alertMessage = "Tracket could not finish resetting: \(error.localizedDescription)"
        }
    }

    func enableNotifications() {
        Task {
            do {
                notificationsEnabled = try await notifications.requestPermission()
                if notificationsEnabled {
                    for project in activeProjects {
                        try? await notifications.scheduleNudge(for: project)
                    }
                }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        monitoringEnabled = enabled
        persistence.monitoringEnabled = enabled
        if enabled {
            monitorNow(forceRemoteSync: false)
        }
    }

    func setRemoteSyncEnabled(_ enabled: Bool) {
        remoteSyncEnabled = enabled
        persistence.remoteSyncEnabled = enabled
    }

    func setMonitorInterval(_ minutes: Int) {
        monitorIntervalMinutes = max(1, minutes)
        persistence.monitorIntervalMinutes = monitorIntervalMinutes
    }

    func monitorNow(forceRemoteSync: Bool = true) {
        Task { await runMonitoringCycle(forceRemoteSync: forceRemoteSync) }
    }

    func isCodexConnected(to project: TracketProject) -> Bool {
        codexHooks.isConnected(to: project)
    }

    func connectCodex(to project: TracketProject) {
        do {
            try codexHooks.connect(to: project)
            alertMessage = "Codex events are connected. Open /hooks in Codex to review and trust the new project hooks."
            rescan(project)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.monitoringEnabled {
                    await self.runMonitoringCycle(forceRemoteSync: false)
                }

                let nanoseconds = UInt64(max(1, self.monitorIntervalMinutes)) * 60 * 1_000_000_000
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    private func runMonitoringCycle(forceRemoteSync: Bool) async {
        guard monitoringEnabled, !isBackgroundScanning else { return }
        isBackgroundScanning = true
        defer { isBackgroundScanning = false }

        ingestHookEvents()
        for provider in ConnectionProvider.allCases where provider.mode == .localAdapter && isConnected(provider) {
            if provider == .codex {
                await refreshCodexConnection(importExisting: false)
            } else {
                await refreshAutomaticLocalApp(provider, importExisting: false)
            }
        }
        let now = Date()
        let remoteFetchDue = persistence.lastRemoteFetchAt.map {
            now.timeIntervalSince($0) >= 15 * 60
        } ?? true
        let shouldFetch = remoteSyncEnabled && (forceRemoteSync || remoteFetchDue)
        let trackedProjects = projects.filter(\.isLocalProject).map { ($0.id, $0.path, $0.remoteURL != nil) }

        let results = await withTaskGroup(of: MonitorScanResult.self, returning: [MonitorScanResult].self) { group in
            for (id, path, hasRemote) in trackedProjects {
                group.addTask {
                    do {
                        let snapshot = try ProjectScanner().scan(
                            url: URL(fileURLWithPath: path),
                            fetchRemote: shouldFetch && hasRemote
                        )
                        return MonitorScanResult(projectID: id, snapshot: snapshot)
                    } catch {
                        return MonitorScanResult(projectID: id, snapshot: nil)
                    }
                }
            }

            var scans: [MonitorScanResult] = []
            for await result in group { scans.append(result) }
            return scans
        }

        for result in results {
            if let snapshot = result.snapshot {
                applySnapshot(snapshot, to: result.projectID, recordActivity: true)
            }
        }

        if shouldFetch {
            await refreshCloudConnections()
            persistence.lastRemoteFetchAt = now
        }
        lastMonitorAt = now
        persistence.lastMonitorAt = now
        ingestHookEvents()
        save()
    }

    private func refreshCloudConnections() async {
        let cloudConnections = connections.filter { $0.provider.mode != .localAdapter && $0.lastError == nil }
        for connection in cloudConnections {
            do {
                guard let accessToken = try await validAccessToken(for: connection.provider) else { continue }
                let result = try await fetchCloudProjects(provider: connection.provider, accessToken: accessToken)
                _ = importCloudProjects(result.projects)
                upsertConnection(
                    provider: connection.provider,
                    accountName: result.accountName,
                    roots: [],
                    importedCount: result.projects.count,
                    error: nil
                )
                await refreshProviderUsage(connection.provider, accessToken: accessToken)
            } catch {
                // A temporary provider outage must not interrupt local project monitoring.
            }
        }
    }

    private func applySnapshot(_ snapshot: ProjectSnapshot, to projectID: UUID, recordActivity: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let previous = projects[index]
        let newEvents = recordActivity ? deriveActivities(previous: previous, snapshot: snapshot) : []

        projects[index].name = snapshot.name
        projects[index].stage = previous.stage == .live ? .live : snapshot.stage
        projects[index].lastActivityAt = max(previous.lastActivityAt, snapshot.lastActivityAt)
        projects[index].lastScannedAt = Date()
        projects[index].branch = snapshot.branch
        projects[index].remoteURL = snapshot.remoteURL
        projects[index].uncommittedChanges = snapshot.uncommittedChanges
        projects[index].commitCountLast7Days = snapshot.commitCountLast7Days
        projects[index].detectedTools = snapshot.detectedTools
        projects[index].languages = snapshot.languages
        projects[index].headCommit = snapshot.headCommit
        projects[index].headCommitMessage = snapshot.headCommitMessage
        projects[index].upstreamBranch = snapshot.upstreamBranch
        projects[index].aheadCount = snapshot.aheadCount
        projects[index].behindCount = snapshot.behindCount
        var mergedToolActivity = previous.toolActivity ?? [:]
        for (tool, date) in snapshot.toolActivity {
            mergedToolActivity[tool] = max(mergedToolActivity[tool] ?? .distantPast, date)
        }
        if let sourceTool = previous.sourceProvider?.tool, sourceTool.isDevelopmentEnvironment,
           snapshot.lastActivityAt > previous.lastActivityAt {
            mergedToolActivity[sourceTool] = max(
                mergedToolActivity[sourceTool] ?? .distantPast,
                snapshot.lastActivityAt
            )
        }
        projects[index].toolActivity = mergedToolActivity
        projects[index].lastMonitorAt = Date()
        addActivities(newEvents)
        save()
    }

    private func deriveActivities(previous: TracketProject, snapshot: ProjectSnapshot) -> [ProjectActivityEvent] {
        guard previous.lastMonitorAt != nil else { return [] }
        var events: [ProjectActivityEvent] = []
        let projectID = previous.id
        let source: ActivitySource = previous.remoteURL?.contains("github.com") == true ? .github : .git

        if let oldBranch = previous.branch,
           let newBranch = snapshot.branch,
           oldBranch != newBranch {
            events.append(ProjectActivityEvent(
                projectID: projectID,
                source: .git,
                kind: .branchChanged,
                title: "Switched to \(newBranch)",
                detail: "The active branch changed from \(oldBranch).",
                fingerprint: "branch-\(projectID)-\(newBranch)-\(Date().timeIntervalSinceReferenceDate)"
            ))
        }

        if let oldHead = previous.headCommit,
           let newHead = snapshot.headCommit,
           oldHead != newHead {
            events.append(ProjectActivityEvent(
                projectID: projectID,
                occurredAt: snapshot.lastActivityAt,
                source: .git,
                kind: .commit,
                title: "New commit detected",
                detail: snapshot.headCommitMessage ?? "The project HEAD moved forward.",
                fingerprint: "commit-\(projectID)-\(newHead)"
            ))
        }

        if previous.uncommittedChanges != snapshot.uncommittedChanges {
            let title = snapshot.uncommittedChanges == 0
                ? "Working tree cleaned up"
                : "Workspace edits detected"
            let detail = snapshot.uncommittedChanges == 0
                ? "All local changes are now committed or reverted."
                : "\(snapshot.uncommittedChanges) uncommitted file changes are present."
            events.append(ProjectActivityEvent(
                projectID: projectID,
                source: .workspace,
                kind: .workingTreeChanged,
                title: title,
                detail: detail,
                fingerprint: "tree-\(projectID)-\(snapshot.uncommittedChanges)-\(snapshot.lastActivityAt.timeIntervalSinceReferenceDate)"
            ))
        } else if snapshot.lastActivityAt.timeIntervalSince(previous.lastActivityAt) > 1,
                  previous.headCommit == snapshot.headCommit {
            events.append(ProjectActivityEvent(
                projectID: projectID,
                occurredAt: snapshot.lastActivityAt,
                source: .workspace,
                kind: .workspaceChanged,
                title: "Project files changed",
                detail: "Tracket detected new local development activity.",
                fingerprint: "files-\(projectID)-\(snapshot.lastActivityAt.timeIntervalSinceReferenceDate)"
            ))
        }

        if let oldAhead = previous.aheadCount {
            if oldAhead > 0, snapshot.aheadCount == 0 {
                events.append(ProjectActivityEvent(
                    projectID: projectID,
                    source: source,
                    kind: .push,
                    title: source == .github ? "Push reached GitHub" : "Push reached the remote",
                    detail: "The local branch is no longer ahead of \(snapshot.upstreamBranch ?? "its upstream").",
                    fingerprint: "push-\(projectID)-\(snapshot.headCommit ?? "unknown")"
                ))
            }
        }

        if let oldBehind = previous.behindCount {
            if snapshot.behindCount > oldBehind {
                events.append(ProjectActivityEvent(
                    projectID: projectID,
                    source: source,
                    kind: .pullAvailable,
                    title: "New remote work available",
                    detail: "\(snapshot.behindCount) commit\(snapshot.behindCount == 1 ? " is" : "s are") waiting upstream.",
                    fingerprint: "behind-\(projectID)-\(snapshot.behindCount)-\(Date().timeIntervalSinceReferenceDate)"
                ))
            } else if oldBehind > 0, snapshot.behindCount == 0 {
                events.append(ProjectActivityEvent(
                    projectID: projectID,
                    source: source,
                    kind: .pullIntegrated,
                    title: "Remote changes integrated",
                    detail: "The local branch is caught up with \(snapshot.upstreamBranch ?? "its upstream").",
                    fingerprint: "pull-\(projectID)-\(snapshot.headCommit ?? "unknown")"
                ))
            }
        }

        if let oldToolActivity = previous.toolActivity {
            for (tool, newDate) in snapshot.toolActivity {
                guard let oldDate = oldToolActivity[tool], newDate.timeIntervalSince(oldDate) > 1 else { continue }
                events.append(ProjectActivityEvent(
                    projectID: projectID,
                    occurredAt: newDate,
                    source: activitySource(for: tool),
                    kind: .toolConfiguration,
                    title: "\(tool.title) project activity",
                    detail: "Project-local \(tool.title) files changed.",
                    fingerprint: "tool-\(projectID)-\(tool.rawValue)-\(newDate.timeIntervalSinceReferenceDate)"
                ))
            }
        }

        return events
    }

    private func ingestHookEvents() {
        let result = hookInbox.readNewEvents(from: persistence.hookInboxOffset)
        persistence.hookInboxOffset = result.nextOffset
        guard !result.events.isEmpty else { return }

        var mapped: [ProjectActivityEvent] = []
        for hook in result.events {
            guard let project = projects
                .filter({ hook.cwd == $0.path || hook.cwd.hasPrefix($0.path + "/") })
                .max(by: { $0.path.count < $1.path.count }) else { continue }

            let source = hookSource(hook.source)
            let description = hookDescription(hook, source: source)
            mapped.append(ProjectActivityEvent(
                id: hook.id,
                projectID: project.id,
                occurredAt: hook.occurredAt,
                source: source,
                kind: description.kind,
                title: description.title,
                detail: description.detail,
                fingerprint: "hook-\(hook.id.uuidString)"
            ))

            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].lastActivityAt = max(projects[index].lastActivityAt, hook.occurredAt)
                if let tool = developerTool(for: source) {
                    var activity = projects[index].toolActivity ?? [:]
                    activity[tool] = max(activity[tool] ?? .distantPast, hook.occurredAt)
                    projects[index].toolActivity = activity
                }
            }
        }
        addActivities(mapped)
    }

    private func hookDescription(
        _ hook: HookInboxEvent,
        source: ActivitySource
    ) -> (kind: ActivityKind, title: String, detail: String) {
        switch hook.event {
        case "SessionStart":
            return (.agentStarted, "\(source.title) session started", "A coding session opened in this project.")
        case "PostToolUse":
            return (.agentProgress, "\(source.title) changed project files", "The coding agent completed a \(hook.toolName ?? "file-edit") action.")
        case "Stop":
            return (.agentFinished, "\(source.title) turn completed", "A coding-agent work turn finished.")
        case "SessionEnd":
            return (.agentFinished, "\(source.title) session ended", "The coding session closed and its progress was saved.")
        default:
            return (.agentProgress, "\(source.title) activity", "A connected development tool reported progress.")
        }
    }

    private func hookSource(_ value: String) -> ActivitySource {
        switch value.lowercased() {
        case "codex": .codex
        case "claude", "claudecode", "claude-code": .claudeCode
        case "opencode", "open-code": .openCode
        case "vscode", "visual-studio-code": .vscode
        case "cursor": .cursor
        case "xcode": .xcode
        default: .system
        }
    }

    private func activitySource(for tool: DeveloperTool) -> ActivitySource {
        switch tool {
        case .git: .git
        case .github: .github
        case .xcode: .xcode
        case .vscode: .vscode
        case .cursor: .cursor
        case .codex: .codex
        case .claudeCode: .claudeCode
        case .openCode: .openCode
        }
    }

    private func developerTool(for source: ActivitySource) -> DeveloperTool? {
        switch source {
        case .xcode: .xcode
        case .vscode: .vscode
        case .cursor: .cursor
        case .codex: .codex
        case .claudeCode: .claudeCode
        case .openCode: .openCode
        default: nil
        }
    }

    private func addActivities(_ newEvents: [ProjectActivityEvent]) {
        guard !newEvents.isEmpty else { return }
        let fingerprints = Set(activities.map(\.fingerprint))
        activities.append(contentsOf: newEvents.filter { !fingerprints.contains($0.fingerprint) })
        activities.sort { $0.occurredAt > $1.occurredAt }
        if activities.count > 500 { activities = Array(activities.prefix(500)) }
        persistence.saveActivities(activities)
    }

    func openProject(_ project: TracketProject, with tool: DeveloperTool? = nil) {
        if !project.isLocalProject {
            if let remote = project.deploymentURL.flatMap(URL.init(string:))
                ?? project.remoteURL.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(remote)
            } else {
                alertMessage = "This imported project does not have a local folder or dashboard URL yet."
            }
            return
        }
        let url = URL(fileURLWithPath: project.path)
        switch tool {
        case .xcode:
            if let xcodeFile = firstXcodeFile(in: url) {
                NSWorkspace.shared.open(xcodeFile)
            } else {
                openApplication(named: "Xcode", url: url)
            }
        case .vscode:
            openApplication(named: "Visual Studio Code", url: url)
        case .cursor:
            openApplication(named: "Cursor", url: url)
        case .github:
            if let remote = project.remoteURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(remote) }
        case .codex, .claudeCode, .openCode:
            openApplication(named: "Terminal", url: url)
        default:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func openApplication(named name: String, url: URL) {
        let bundleIdentifiers = [
            "Xcode": "com.apple.dt.Xcode",
            "Visual Studio Code": "com.microsoft.VSCode",
            "Cursor": "com.todesktop.230313mzl4w4u92",
            "Terminal": "com.apple.Terminal"
        ]
        guard let bundleIdentifier = bundleIdentifiers[name],
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            alertMessage = "\(name) is not installed on this Mac."
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            if let error {
                Task { @MainActor in self.alertMessage = "Could not open \(name): \(error.localizedDescription)" }
            }
        }
    }

    private func firstXcodeFile(in url: URL) -> URL? {
        let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return children?.first { $0.pathExtension == "xcworkspace" }
            ?? children?.first { $0.pathExtension == "xcodeproj" }
    }

    private func apply(_ plan: AIProjectPlan, to projectID: UUID) {
        update(projectID) { project in
            let measuredCompletion = ProjectCompletionEstimator().estimate(project)
            let blendedCompletion = Int((Double(plan.completionPercent) * 0.65 + Double(measuredCompletion) * 0.35).rounded())
            project.aiSummary = plan.summary
            project.nextSuggestion = plan.nextSuggestion
            if project.stage != .live {
                project.stage = ProjectStage(rawValue: plan.stage) ?? project.stage
            }
            project.aiCompletionPercent = project.stage == .live ? 100 : min(99, max(0, blendedCompletion))
            project.aiCompletionRationale = "AI assessment \(plan.completionPercent)% · measured signals \(measuredCompletion)%. \(plan.completionRationale)"
            project.aiAssessedAt = Date()
            project.roadmap = plan.milestones.enumerated().map { index, milestone in
                RoadmapItem(
                    title: milestone.title,
                    detail: milestone.detail,
                    status: index == 0 ? .active : .todo,
                    priority: RoadmapPriority(rawValue: milestone.priority) ?? .medium,
                    dueDate: Calendar.current.date(
                        byAdding: .day,
                        value: milestone.dueInDays,
                        to: Date()
                    ) ?? project.deadline
                )
            }
        }
    }

    private func update(_ id: UUID, mutation: (inout TracketProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        mutation(&projects[index])
        save()
    }

    private func save() {
        persistence.saveProjects(projects)
        persistence.saveActivities(activities)
        persistence.saveConnections(connections)
    }

    private func persistProjectAIWorkspace(_ workspace: ProjectAIWorkspace) {
        projectAIWorkspaces[workspace.projectID] = workspace
        do {
            try projectAIWorkspaceStore.save(workspace)
        } catch {
            alertMessage = "Could not save this project's AI memory: \(error.localizedDescription)"
        }
    }

    private func credentialAccount(_ provider: ConnectionProvider) -> String {
        "provider.\(provider.rawValue).credential"
    }

    private func aiCredentialAccount(_ provider: CloudAIProvider) -> String {
        provider == .openAI ? "openai-api-key" : "ai.provider.\(provider.rawValue).api-key"
    }

    private func cloudAPIKey(for provider: CloudAIProvider) -> String? {
        keychain.loadSecret(account: aiCredentialAccount(provider))
    }

    private func saveOAuthCredential(_ credential: OAuthCredential, provider: ConnectionProvider) throws {
        let data = try JSONEncoder().encode(credential)
        guard let value = String(data: data, encoding: .utf8) else {
            throw OAuthServiceError.invalidAuthorizationResponse
        }
        try keychain.saveSecret(value, account: credentialAccount(provider))
    }

    private func fetchCloudProjects(
        provider: ConnectionProvider,
        accessToken: String
    ) async throws -> CloudImportResult {
        if provider == .cloudflare {
            return try await cloudflareMCP.fetchProjects(accessToken: accessToken)
        }
        if provider == .render {
            return try await renderMCP.fetchProjects(accessToken: accessToken)
        }
        return try await cloudImport.fetchProjects(provider: provider, credential: accessToken)
    }

    private func validAccessToken(for provider: ConnectionProvider) async throws -> String? {
        guard let stored = keychain.loadSecret(account: credentialAccount(provider)) else { return nil }
        guard let data = stored.data(using: .utf8),
              let credential = try? JSONDecoder().decode(OAuthCredential.self, from: data) else {
            return stored
        }
        guard credential.needsRefresh, let refreshToken = credential.refreshToken else {
            return credential.accessToken
        }
        guard let clientID = credential.clientID ?? oauthClientID(for: provider) else {
            throw OAuthServiceError.provider("The OAuth client ID for \(provider.title) is missing.")
        }
        let refreshed = try await oauth.refresh(
            provider: provider,
            clientID: clientID,
            refreshToken: refreshToken,
            tokenEndpoint: credential.tokenEndpoint,
            resource: credential.resource
        )
        try saveOAuthCredential(refreshed, provider: provider)
        return refreshed.accessToken
    }

    private func connectCodexApp() {
        isConnectingProvider = .codex
        Task {
            await refreshCodexConnection(importExisting: true)
            isConnectingProvider = nil
        }
    }

    private func connectAutomaticLocalApp(_ provider: ConnectionProvider) {
        isConnectingProvider = provider
        Task {
            await refreshAutomaticLocalApp(provider, importExisting: true)
            isConnectingProvider = nil
        }
    }

    private func refreshAutomaticLocalApp(_ provider: ConnectionProvider, importExisting: Bool) async {
        do {
            let discovery = localAppDiscovery
            let urls = try await Task.detached(priority: .userInitiated) {
                try discovery.discover(provider: provider)
            }.value
            let toImport = importExisting ? urls : urls.filter { url in
                !projects.contains { $0.path == url.path }
            }
            await importLocalProjects(toImport, provider: provider)
            upsertConnection(
                provider: provider,
                accountName: "\(provider.title) app",
                roots: [],
                importedCount: urls.count,
                error: nil
            )
            await refreshLocalToolUsage(provider, force: importExisting)
            if importExisting {
                alertMessage = "\(provider.title) connected. Imported or refreshed \(urls.count) project workspaces automatically."
            }
        } catch {
            if importExisting {
                upsertConnection(
                    provider: provider,
                    accountName: "\(provider.title) app",
                    roots: [],
                    importedCount: 0,
                    error: error.localizedDescription
                )
                alertMessage = error.localizedDescription
            }
        }
    }

    private func refreshCodexConnection(importExisting: Bool) async {
        do {
            let discovery = codexDiscovery
            let urls = try await Task.detached(priority: .userInitiated) {
                try discovery.discover()
            }.value
            let toImport = importExisting ? urls : urls.filter { url in
                !projects.contains { $0.path == url.path }
            }
            await importLocalProjects(toImport, provider: .codex)
            upsertConnection(
                provider: .codex,
                accountName: "Codex app",
                roots: [],
                importedCount: urls.count,
                error: nil
            )
            await refreshCodexUsage(force: importExisting)
            if importExisting {
                alertMessage = "Codex connected. Imported or refreshed \(urls.count) project workspaces automatically."
            }
        } catch {
            if importExisting {
                upsertConnection(
                    provider: .codex,
                    accountName: "Codex app",
                    roots: [],
                    importedCount: 0,
                    error: error.localizedDescription
                )
                alertMessage = error.localizedDescription
            }
        }
    }

    private func upsertConnection(
        provider: ConnectionProvider,
        accountName: String?,
        roots: [String],
        importedCount: Int,
        error: String?
    ) {
        let existing = connections.first { $0.provider == provider }
        let record = DeveloperConnection(
            provider: provider,
            connectedAt: existing?.connectedAt ?? Date(),
            lastSyncedAt: Date(),
            accountName: accountName ?? existing?.accountName,
            roots: roots,
            importedProjectCount: importedCount,
            lastError: error,
            usageStatus: existing?.usageStatus,
            accountUsage: existing?.accountUsage
        )
        connections.removeAll { $0.provider == provider }
        connections.append(record)
        connections.sort { $0.provider.title < $1.provider.title }
        save()
    }

    private func refreshProviderUsage(_ provider: ConnectionProvider, accessToken: String) async {
        var changed = false
        if let status = try? await providerUsage.status(provider: provider, accessToken: accessToken),
           let index = connections.firstIndex(where: { $0.provider == provider }) {
            connections[index].usageStatus = status
            changed = true
        }
        if let accountUsage = try? await providerUsage.accountUsage(provider: provider, accessToken: accessToken),
           let index = connections.firstIndex(where: { $0.provider == provider }) {
            connections[index].accountUsage = accountUsage
            changed = true
        }
        if changed { persistence.saveConnections(connections) }
    }

    private func refreshCodexUsage(force: Bool) async {
        guard let index = connections.firstIndex(where: { $0.provider == .codex }) else { return }
        if !force, let checkedAt = connections[index].accountUsage?.checkedAt,
           Date().timeIntervalSince(checkedAt) < 5 * 60 {
            return
        }
        guard let result = try? await codexUsage.readUsage(),
              let currentIndex = connections.firstIndex(where: { $0.provider == .codex }) else { return }
        connections[currentIndex].accountUsage = result.usage
        if let accountName = result.accountName?.nilIfBlank {
            connections[currentIndex].accountName = accountName
        }
        persistence.saveConnections(connections)
    }

    private func refreshLocalToolUsage(_ provider: ConnectionProvider, force: Bool) async {
        guard provider == .claudeCode || provider == .openCode,
              let index = connections.firstIndex(where: { $0.provider == provider }) else { return }
        if !force, let checkedAt = connections[index].accountUsage?.checkedAt,
           Date().timeIntervalSince(checkedAt) < 5 * 60 {
            return
        }
        guard let usage = await localToolUsage.usage(for: provider),
              let currentIndex = connections.firstIndex(where: { $0.provider == provider }) else { return }
        connections[currentIndex].accountUsage = usage
        persistence.saveConnections(connections)
    }

    private func importLocalProjects(_ urls: [URL], provider: ConnectionProvider) async {
        var importedIDs: [UUID] = []
        for url in urls {
            do {
                folderAccess.remember(url)
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try ProjectScanner().scan(url: url)
                }.value
                let id = importSnapshot(snapshot, provider: provider)
                importedIDs.append(id)
            } catch {
                continue
            }
        }
        save()
        let unassessed = importedIDs.filter { id in
            projects.first(where: { $0.id == id })?.aiCompletionPercent == nil
        }
        await assessImportedProjects(unassessed)
    }

    private func importSnapshot(_ snapshot: ProjectSnapshot, provider: ConnectionProvider) -> UUID {
        if let index = projects.firstIndex(where: { $0.path == snapshot.path }) {
            applySnapshot(snapshot, to: projects[index].id, recordActivity: true)
            if let tool = provider.tool, !projects[index].detectedTools.contains(tool) {
                projects[index].detectedTools.append(tool)
            }
            if let tool = provider.tool, tool.isDevelopmentEnvironment {
                var activity = projects[index].toolActivity ?? [:]
                activity[tool] = max(activity[tool] ?? .distantPast, snapshot.lastActivityAt)
                projects[index].toolActivity = activity
            }
            projects[index].sourceProvider = provider
            return projects[index].id
        }

        let deadline = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()
        var tools = snapshot.detectedTools
        if let tool = provider.tool, !tools.contains(tool) { tools.append(tool) }
        var toolActivity = snapshot.toolActivity
        if let tool = provider.tool, tool.isDevelopmentEnvironment {
            toolActivity[tool] = max(toolActivity[tool] ?? .distantPast, snapshot.lastActivityAt)
        }
        let project = TracketProject(
            name: snapshot.name,
            path: snapshot.path,
            goal: "Finish the smallest useful version and deploy it for real users.",
            stage: snapshot.stage,
            lastActivityAt: snapshot.lastActivityAt,
            deadline: deadline,
            branch: snapshot.branch,
            remoteURL: snapshot.remoteURL,
            deploymentURL: nil,
            uncommittedChanges: snapshot.uncommittedChanges,
            commitCountLast7Days: snapshot.commitCountLast7Days,
            detectedTools: tools,
            languages: snapshot.languages,
            roadmap: Self.defaultRoadmap(stage: snapshot.stage, deadline: deadline),
            aiSummary: nil,
            nextSuggestion: "Finish the smallest end-to-end path, then put it in front of one real user.",
            headCommit: snapshot.headCommit,
            headCommitMessage: snapshot.headCommitMessage,
            upstreamBranch: snapshot.upstreamBranch,
            aheadCount: snapshot.aheadCount,
            behindCount: snapshot.behindCount,
            toolActivity: toolActivity,
            lastMonitorAt: Date(),
            sourceProvider: provider
        )
        projects.append(project)
        addActivities([ProjectActivityEvent(
            projectID: project.id,
            source: activitySource(for: provider.tool ?? .git),
            kind: .monitoring,
            title: "Imported from \(provider.title)",
            detail: "Tracket discovered this project automatically from a connected adapter.",
            fingerprint: "import-\(provider.rawValue)-\(project.id.uuidString)"
        )])
        return project.id
    }

    private func importCloudProjects(_ descriptors: [ImportedProjectDescriptor]) -> [UUID] {
        var importedIDs: [UUID] = []
        for descriptor in descriptors {
            let matchIndex = projects.firstIndex {
                ($0.sourceProvider == descriptor.provider && $0.externalID == descriptor.externalID)
                    || (descriptor.remoteURL != nil && $0.remoteURL?.lowercased() == descriptor.remoteURL?.lowercased())
            }
            if let index = matchIndex {
                projects[index].sourceProvider = descriptor.provider
                projects[index].externalID = descriptor.externalID
                projects[index].remoteURL = descriptor.remoteURL ?? projects[index].remoteURL
                projects[index].deploymentURL = descriptor.deploymentURL ?? projects[index].deploymentURL
                projects[index].lastActivityAt = max(projects[index].lastActivityAt, descriptor.updatedAt)
                if projects[index].deploymentURL != nil { projects[index].stage = .live }
                importedIDs.append(projects[index].id)
                continue
            }

            let deadline = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
            let project = TracketProject(
                name: descriptor.name,
                path: "\(descriptor.provider.rawValue)://\(descriptor.externalID)",
                goal: "Finish, deploy, and validate this imported project with real users.",
                stage: descriptor.stage,
                lastActivityAt: descriptor.updatedAt,
                deadline: deadline,
                branch: nil,
                remoteURL: descriptor.remoteURL,
                deploymentURL: descriptor.deploymentURL,
                uncommittedChanges: 0,
                commitCountLast7Days: 0,
                detectedTools: descriptor.provider.tool.map { [$0] } ?? [],
                languages: [],
                roadmap: Self.defaultRoadmap(stage: descriptor.stage, deadline: deadline),
                aiSummary: nil,
                nextSuggestion: "Connect a local workspace or review the next deployment blocker.",
                sourceProvider: descriptor.provider,
                externalID: descriptor.externalID,
                aiCompletionPercent: descriptor.stage == .live ? 100 : nil
            )
            projects.append(project)
            importedIDs.append(project.id)
            addActivities([ProjectActivityEvent(
                projectID: project.id,
                source: descriptor.provider == .github ? .github : .system,
                kind: .monitoring,
                title: "Imported from \(descriptor.provider.title)",
                detail: "Cloud project metadata is now tracked automatically.",
                fingerprint: "cloud-import-\(descriptor.provider.rawValue)-\(descriptor.externalID)"
            )])
        }
        projects.sort { $0.lastActivityAt > $1.lastActivityAt }
        save()
        return importedIDs
    }

    private func assessImportedProjects(_ ids: [UUID]) async {
        let key = cloudAPIKey(for: aiSettings.cloudProvider)
        if aiSettings.mode == .cloud, key == nil { return }
        for id in ids {
            guard let project = projects.first(where: { $0.id == id }), project.stage != .live else { continue }
            do {
                let plan = try await ai.createPlan(for: project, settings: aiSettings, cloudAPIKey: key)
                apply(plan, to: id)
            } catch {
                // Import remains successful; the user can retry AI assessment from the project page.
            }
        }
    }

    nonisolated static func defaultRoadmap(stage: ProjectStage, deadline: Date) -> [RoadmapItem] {
        let calendar = Calendar.current
        let steps: [(String, String, RoadmapPriority)] = [
            ("Define the release promise", "Write one sentence describing who this helps and the result they get.", .high),
            ("Finish one complete user path", "Make the smallest core workflow work from start to finish.", .high),
            ("Remove launch blockers", "Fix crashes, confusing empty states, and missing setup instructions.", .high),
            ("Prepare deployment", "Choose the simplest hosting or distribution path and document it.", .medium),
            ("Ship and invite one user", "Publish the release, send the link, and collect one concrete reaction.", .high)
        ]

        let totalDays = max(5, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 14)
        return steps.enumerated().map { index, step in
            RoadmapItem(
                title: step.0,
                detail: step.1,
                status: index == 0 ? .active : .todo,
                priority: step.2,
                dueDate: calendar.date(
                    byAdding: .day,
                    value: min(totalDays, max(1, (index + 1) * totalDays / steps.count)),
                    to: Date()
                ) ?? deadline
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum DemoData {
    static let projects: [TracketProject] = {
        let now = Date()
        let deadline = Calendar.current.date(byAdding: .day, value: 12, to: now) ?? now
        return [
            TracketProject(
                name: "Focus Garden",
                path: "/Users/demo/Projects/focus-garden",
                goal: "Help remote workers finish one meaningful task each day.",
                stage: .building,
                lastActivityAt: Calendar.current.date(byAdding: .hour, value: -6, to: now) ?? now,
                deadline: deadline,
                branch: "main",
                remoteURL: "https://github.com/demo/focus-garden",
                deploymentURL: nil,
                uncommittedChanges: 4,
                commitCountLast7Days: 7,
                detectedTools: [.git, .github, .vscode, .cursor, .codex],
                languages: ["TypeScript", "JavaScript"],
                roadmap: AppStore.defaultRoadmap(stage: .building, deadline: deadline),
                aiSummary: "The core product is taking shape. The fastest route to real feedback is to finish the daily-focus loop and deploy it without adding another feature.",
                nextSuggestion: "Connect the focus timer completion to the daily progress view."
            ),
            TracketProject(
                name: "Receipt Lens",
                path: "/Users/demo/Projects/receipt-lens",
                goal: "Turn photographed receipts into clean expense rows.",
                stage: .polishing,
                lastActivityAt: Calendar.current.date(byAdding: .day, value: -9, to: now) ?? now,
                deadline: Calendar.current.date(byAdding: .day, value: 4, to: now) ?? now,
                branch: "feature/export",
                remoteURL: nil,
                deploymentURL: nil,
                uncommittedChanges: 1,
                commitCountLast7Days: 0,
                detectedTools: [.git, .xcode, .claudeCode],
                languages: ["Swift"],
                roadmap: AppStore.defaultRoadmap(stage: .polishing, deadline: deadline),
                aiSummary: nil,
                nextSuggestion: "Export one scanned receipt as CSV before touching the settings screen."
            )
        ]
    }()

    static func activities(for projects: [TracketProject]) -> [ProjectActivityEvent] {
        guard projects.count >= 2 else { return [] }
        return [
            ProjectActivityEvent(
                projectID: projects[0].id,
                occurredAt: Date().addingTimeInterval(-35 * 60),
                source: .codex,
                kind: .agentFinished,
                title: "Codex turn completed",
                detail: "A coding-agent work turn finished.",
                fingerprint: "demo-codex"
            ),
            ProjectActivityEvent(
                projectID: projects[0].id,
                occurredAt: Date().addingTimeInterval(-2 * 60 * 60),
                source: .github,
                kind: .push,
                title: "Push reached GitHub",
                detail: "The main branch is synchronized with its upstream.",
                fingerprint: "demo-push"
            ),
            ProjectActivityEvent(
                projectID: projects[1].id,
                occurredAt: Date().addingTimeInterval(-5 * 60 * 60),
                source: .workspace,
                kind: .workingTreeChanged,
                title: "Workspace edits detected",
                detail: "1 uncommitted file change is present.",
                fingerprint: "demo-workspace"
            )
        ]
    }
}

private struct MonitorScanResult: Sendable {
    let projectID: UUID
    let snapshot: ProjectSnapshot?
}
