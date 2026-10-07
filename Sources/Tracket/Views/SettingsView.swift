import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiKey = ""
    @State private var showingResetConfirmation = false

    var body: some View {
        ZStack {
            TracketTheme.softGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Settings")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                        Text("Connect intelligence and choose how Tracket keeps you moving.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    resetSection
                    aiSection
                    ConnectionsSettingsView()
                    backgroundMonitorSection
                    notificationSection
                    privacySection
                }
                .padding(30)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Tracket…", systemImage: "arrow.counterclockwise.circle")
                }
                .help("Remove all Tracket data and return to the first-launch state")
            }
        }
        .alert("Reset Tracket?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                store.resetApplication()
                apiKey = ""
            }
        } message: {
            Text("This removes every tracked project, saved folder authorization, activity, connected account, OAuth credential, OpenAI key, and Tracket preference from this Mac. Your project files and online accounts are not deleted.")
        }
    }

    private var backgroundMonitorSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                sectionHeader(
                    title: "Menu-bar monitor",
                    caption: "Keeps collecting progress after the main window closes.",
                    symbol: "menubar.rectangle",
                    tint: .green
                )

                Toggle(
                    "Monitor tracked projects in the background",
                    isOn: Binding(
                        get: { store.monitoringEnabled },
                        set: { store.setMonitoringEnabled($0) }
                    )
                )

                HStack {
                    Text("Check every")
                    Spacer()
                    Picker("Check every", selection: Binding(
                        get: { store.monitorIntervalMinutes },
                        set: { store.setMonitorInterval($0) }
                    )) {
                        Text("1 minute").tag(1)
                        Text("2 minutes").tag(2)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                .disabled(!store.monitoringEnabled)

                Toggle(
                    "Fetch Git remotes every 15 minutes",
                    isOn: Binding(
                        get: { store.remoteSyncEnabled },
                        set: { store.setRemoteSyncEnabled($0) }
                    )
                )
                .disabled(!store.monitoringEnabled)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.lastMonitorAt.map { "Last scan \($0.compactRelative)" } ?? "Waiting for the first scan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Git authentication prompts are disabled during background checks.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if store.isBackgroundScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Sync now") { store.monitorNow(forceRemoteSync: true) }
                            .buttonStyle(.bordered)
                            .disabled(!store.monitoringEnabled)
                    }
                }
            }
        }
    }

    private var aiSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                sectionHeader(
                    title: "AI project coach",
                    caption: "Run privately on this Mac, use your provider, or combine both.",
                    symbol: "sparkles",
                    tint: TracketTheme.accent
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Execution mode").font(.subheadline.weight(.semibold))
                    Picker("Execution mode", selection: aiModeBinding) {
                        ForEach(AIExecutionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(store.aiSettings.mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.aiSettings.mode != .cloud {
                    Divider()
                    localModelSettings
                }

                if store.aiSettings.mode != .local {
                    Divider()
                    cloudProviderSettings
                }

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Information shared with AI").font(.subheadline.weight(.semibold))
                    Picker("Information shared", selection: contextSharingBinding) {
                        ForEach(AIContextSharing.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text(store.aiSettings.contextSharing.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if store.aiSettings.mode == .smartHybrid {
                        Toggle("Allow cloud fallback when local AI cannot produce a valid plan", isOn: cloudFallbackBinding)
                        Text("This setting is explicit permission. Tracket never sends a request to the cloud while it is off.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var localModelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracket Local").font(.headline)
                    Text("This Mac has approximately \(store.physicalMemoryGB) GB memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Local model", selection: localModelBinding) {
                    ForEach(LocalAIModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .frame(width: 230)
            }

            let model = store.aiSettings.localModel
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(store.physicalMemoryGB >= model.minimumMemoryGB ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.subheadline.weight(.semibold))
                    Text("\(model.summary) Download: \(model.estimatedDownload); recommended memory: \(model.minimumMemoryGB) GB or more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    localModelStatus(model)
                }
                Spacer()
                localModelAction(model)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var cloudProviderSettings: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Cloud provider").font(.headline)
                Spacer()
                Picker("Cloud provider", selection: cloudProviderBinding) {
                    ForEach(CloudAIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .frame(width: 230)
            }

            TextField("Model identifier", text: cloudModelBinding)
                .textFieldStyle(.roundedBorder)
            TextField("Base URL", text: baseURLBinding)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Circle()
                    .fill(store.configuredAIProviders.contains(store.aiSettings.cloudProvider) ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.configuredAIProviders.contains(store.aiSettings.cloudProvider) ? "API key stored" : "API key required")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(store.aiSettings.effectiveModel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            SecureField("\(store.aiSettings.cloudProvider.title) API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Keys are stored in your Mac's Keychain and never saved with project data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.configuredAIProviders.contains(store.aiSettings.cloudProvider) {
                    Button("Remove", role: .destructive) {
                        store.removeCloudAPIKey(for: store.aiSettings.cloudProvider)
                    }
                }
                Button("Save key") {
                    store.saveCloudAPIKey(apiKey, for: store.aiSettings.cloudProvider)
                    apiKey = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func localModelStatus(_ model: LocalAIModel) -> some View {
        switch store.localModelStates[model] ?? .notDownloaded {
        case .notDownloaded:
            Text("Not downloaded").font(.caption2).foregroundStyle(.secondary)
        case .partial(let bytes):
            Text("Downloaded files found · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Resume or delete them.")
                .font(.caption2).foregroundStyle(.orange)
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text(progress >= 1 ? "Verifying model files…" : "Downloading \(Int(progress * 100))%")
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 280)
        case .ready(let bytes):
            Text("Ready · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                .font(.caption2).foregroundStyle(.green)
        case .loading:
            Text("Loading into memory…").font(.caption2).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption2).foregroundStyle(.red).lineLimit(2)
        }
    }

    @ViewBuilder
    private func localModelAction(_ model: LocalAIModel) -> some View {
        switch store.localModelStates[model] ?? .notDownloaded {
        case .ready:
            Button("Delete", role: .destructive) { store.removeLocalModel(model) }
        case .partial:
            HStack(spacing: 7) {
                Button("Delete", role: .destructive) { store.removeLocalModel(model) }
                Button("Resume") { store.downloadLocalModel(model) }
                    .buttonStyle(.borderedProminent)
            }
        case .downloading:
            Button("Cancel") { store.cancelLocalModelDownload(model) }
        case .loading:
            ProgressView().controlSize(.small)
        case .notDownloaded, .failed:
            Button("Download") { store.downloadLocalModel(model) }
                .buttonStyle(.borderedProminent)
                .disabled(store.physicalMemoryGB < model.minimumMemoryGB)
        }
    }

    private var aiModeBinding: Binding<AIExecutionMode> {
        Binding(get: { store.aiSettings.mode }, set: { value in
            var settings = store.aiSettings; settings.mode = value; store.updateAISettings(settings)
        })
    }

    private var localModelBinding: Binding<LocalAIModel> {
        Binding(get: { store.aiSettings.localModel }, set: { value in
            var settings = store.aiSettings; settings.localModel = value; store.updateAISettings(settings)
        })
    }

    private var cloudProviderBinding: Binding<CloudAIProvider> {
        Binding(get: { store.aiSettings.cloudProvider }, set: { value in
            var settings = store.aiSettings
            settings.cloudProvider = value
            settings.cloudModel = value.defaultModel
            settings.customBaseURL = value.defaultBaseURL
            store.updateAISettings(settings)
            apiKey = ""
        })
    }

    private var cloudModelBinding: Binding<String> {
        Binding(get: { store.aiSettings.cloudModel }, set: { value in
            var settings = store.aiSettings; settings.cloudModel = value; store.updateAISettings(settings)
        })
    }

    private var baseURLBinding: Binding<String> {
        Binding(get: { store.aiSettings.effectiveBaseURL }, set: { value in
            var settings = store.aiSettings; settings.customBaseURL = value; store.updateAISettings(settings)
        })
    }

    private var contextSharingBinding: Binding<AIContextSharing> {
        Binding(get: { store.aiSettings.contextSharing }, set: { value in
            var settings = store.aiSettings; settings.contextSharing = value; store.updateAISettings(settings)
        })
    }

    private var cloudFallbackBinding: Binding<Bool> {
        Binding(get: { store.aiSettings.allowCloudFallback }, set: { value in
            var settings = store.aiSettings; settings.allowCloudFallback = value; store.updateAISettings(settings)
        })
    }

    private var notificationSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                sectionHeader(
                    title: "Momentum nudges",
                    caption: "A local reminder points you back to the current milestone.",
                    symbol: "bell.badge.fill",
                    tint: .orange
                )

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.notificationsEnabled ? "Notifications enabled" : "Notifications are off")
                            .font(.headline)
                        Text("Tracket schedules one reminder at a time for active projects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.notificationsEnabled ? "Enabled" : "Enable notifications") {
                        store.enableNotifications()
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.notificationsEnabled)
                }
            }
        }
    }

    private var privacySection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                sectionHeader(
                    title: "Local-first by design",
                    caption: "Tracking should create clarity, not surveillance.",
                    symbol: "hand.raised.fill",
                    tint: .green
                )
                privacyRow("Project paths, roadmap state, and momentum stay on this Mac.")
                privacyRow("AI receives only the context level selected above; relevant-source mode uses bounded excerpts, never the whole repository.")
                privacyRow("Local AI runs through MLX on this Mac after an optional model download.")
                privacyRow("The menu-bar monitor reads file timestamps and Git metadata, not file contents.")
                privacyRow("Codex hooks record lifecycle and edit events without saving prompts, commands, or source code.")
                privacyRow("Provider credentials are stored in Keychain; imported cloud projects store metadata and URLs, not source code.")
            }
        }
    }

    private var resetSection: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                sectionHeader(
                    title: "Reset Tracket",
                    caption: "Return the app to its first-launch state.",
                    symbol: "arrow.counterclockwise.circle.fill",
                    tint: .red
                )

                Text("All tracked projects, folder links, activity history, AI conversations and project memory, connected services, credentials, and monitor settings will be forgotten. Source folders and cloud projects remain untouched.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("macOS may retain system-level notification or Privacy & Security choices, which can be changed in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Tracket…", role: .destructive) {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sectionHeader(title: String, caption: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func privacyRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
    }
}
