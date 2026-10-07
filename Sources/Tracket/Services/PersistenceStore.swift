import Foundation

struct PersistenceStore {
    private let projectsKey = "tracket.projects.v1"
    private let activitiesKey = "tracket.activities.v1"
    private let monitoringEnabledKey = "tracket.monitoring.enabled"
    private let remoteSyncEnabledKey = "tracket.monitoring.remote-sync"
    private let monitorIntervalKey = "tracket.monitoring.interval-minutes"
    private let lastMonitorKey = "tracket.monitoring.last-scan"
    private let lastRemoteFetchKey = "tracket.monitoring.last-remote-fetch"
    private let hookInboxOffsetKey = "tracket.hooks.inbox-offset"
    private let connectionsKey = "tracket.connections.v1"
    private let oauthClientIDPrefix = "tracket.oauth.client-id."
    private let openAIKeyConfiguredKey = "tracket.openai-key-configured"
    private let aiSettingsKey = "tracket.ai.settings.v1"
    private let configuredAIProvidersKey = "tracket.ai.configured-providers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadProjects() -> [TracketProject] {
        guard let data = defaults.data(forKey: projectsKey) else { return [] }
        return (try? JSONDecoder().decode([TracketProject].self, from: data)) ?? []
    }

    func saveProjects(_ projects: [TracketProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: projectsKey)
    }

    func loadActivities() -> [ProjectActivityEvent] {
        guard let data = defaults.data(forKey: activitiesKey) else { return [] }
        return (try? JSONDecoder().decode([ProjectActivityEvent].self, from: data)) ?? []
    }

    func saveActivities(_ activities: [ProjectActivityEvent]) {
        guard let data = try? JSONEncoder().encode(Array(activities.prefix(500))) else { return }
        defaults.set(data, forKey: activitiesKey)
    }

    func loadConnections() -> [DeveloperConnection] {
        guard let data = defaults.data(forKey: connectionsKey) else { return [] }
        return (try? JSONDecoder().decode([DeveloperConnection].self, from: data)) ?? []
    }

    func saveConnections(_ connections: [DeveloperConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: connectionsKey)
    }

    func oauthClientID(for provider: ConnectionProvider) -> String? {
        defaults.string(forKey: oauthClientIDPrefix + provider.rawValue)?.nilIfBlank
    }

    func saveOAuthClientID(_ clientID: String, for provider: ConnectionProvider) {
        defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: oauthClientIDPrefix + provider.rawValue)
    }

    var hasOpenAIKeyConfigured: Bool {
        get { defaults.bool(forKey: openAIKeyConfiguredKey) }
        set { defaults.set(newValue, forKey: openAIKeyConfiguredKey) }
    }

    func loadAISettings() -> AISettings {
        guard let data = defaults.data(forKey: aiSettingsKey),
              let settings = try? JSONDecoder().decode(AISettings.self, from: data) else {
            return AISettings()
        }
        return settings
    }

    func saveAISettings(_ settings: AISettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: aiSettingsKey)
    }

    var configuredAIProviders: Set<CloudAIProvider> {
        get {
            Set((defaults.array(forKey: configuredAIProvidersKey) as? [String] ?? [])
                .compactMap(CloudAIProvider.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: configuredAIProvidersKey) }
    }

    var monitoringEnabled: Bool {
        get { defaults.object(forKey: monitoringEnabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: monitoringEnabledKey) }
    }

    var remoteSyncEnabled: Bool {
        get { defaults.object(forKey: remoteSyncEnabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: remoteSyncEnabledKey) }
    }

    var monitorIntervalMinutes: Int {
        get { max(1, defaults.object(forKey: monitorIntervalKey) as? Int ?? 2) }
        set { defaults.set(max(1, newValue), forKey: monitorIntervalKey) }
    }

    var lastMonitorAt: Date? {
        get { defaults.object(forKey: lastMonitorKey) as? Date }
        set { defaults.set(newValue, forKey: lastMonitorKey) }
    }

    var lastRemoteFetchAt: Date? {
        get { defaults.object(forKey: lastRemoteFetchKey) as? Date }
        set { defaults.set(newValue, forKey: lastRemoteFetchKey) }
    }

    var hookInboxOffset: UInt64 {
        get { UInt64(max(0, defaults.object(forKey: hookInboxOffsetKey) as? Int ?? 0)) }
        set { defaults.set(Int(newValue), forKey: hookInboxOffsetKey) }
    }

    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("tracket.") {
            defaults.removeObject(forKey: key)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
