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
                    title: "OpenAI project coach",
                    caption: "Generates a release-focused roadmap from project metadata.",
                    symbol: "sparkles",
                    tint: TracketTheme.accent
                )

                HStack(spacing: 8) {
                    Circle()
                        .fill(store.hasAPIKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(store.hasAPIKey ? "Connected" : "API key required")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Model: \(OpenAIService.model)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                SecureField(store.hasAPIKey ? "Enter a replacement API key" : "OpenAI API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("The key is stored in your Mac's Keychain and is never saved in project data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.hasAPIKey {
                        Button("Remove", role: .destructive) { store.removeAPIKey() }
                    }
                    Button("Save key") {
                        store.saveAPIKey(apiKey)
                        apiKey = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()
                Label(
                    "Before a public release, route OpenAI requests through a small server so API credentials never ship inside the client.",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
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
                privacyRow("Source code is not sent to OpenAI in this MVP; only the displayed project metadata is used for planning.")
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

                Text("All tracked projects, folder links, activity history, connected services, credentials, and monitor settings will be forgotten. Source folders and cloud projects remain untouched.")
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
