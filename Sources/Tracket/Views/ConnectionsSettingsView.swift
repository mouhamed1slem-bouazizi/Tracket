import SwiftUI

struct ConnectionsSettingsView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [
        GridItem(.adaptive(minimum: 225, maximum: 320), spacing: 12, alignment: .top)
    ]

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                header
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(ConnectionProvider.allCases) { provider in
                        connectionCard(provider)
                    }
                }
                Divider()
                Label(
                    "Local adapters read each app's recent-workspace index. OAuth credentials stay in your Mac Keychain. Connecting imports projects automatically and AI-assesses unfinished work when an OpenAI key is available.",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TracketTheme.accent)
                .frame(width: 38, height: 38)
                .background(TracketTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Connections")
                    .font(.title3.bold())
                Text("Import every project from the tools and deployment accounts you already use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func connectionCard(_ provider: ConnectionProvider) -> some View {
        let connection = store.connection(for: provider)
        let connected = store.isConnected(provider)
        let busy = store.isConnectingProvider == provider

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(provider.tint)
                    .frame(width: 32, height: 32)
                    .background(provider.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.title).font(.headline)
                    Text(provider.connectionLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(connected ? Color.green : connection?.lastError == nil ? Color.secondary.opacity(0.35) : Color.orange)
                    .frame(width: 8, height: 8)
            }

            if let connection, connected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.accountName ?? "Connected")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(connection.importedProjectCount) projects · synced \((connection.lastSyncedAt ?? connection.connectedAt).compactRelative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                usageView(connection, provider: provider)
            } else if let error = connection?.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                Text(connectionDescription(provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 7) {
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Importing…").font(.caption).foregroundStyle(.secondary)
                } else if connected {
                    Button("Sync") { store.syncConnection(provider) }
                        .buttonStyle(.bordered)
                    Menu {
                        Button("Disconnect", role: .destructive) { store.disconnect(provider) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Button("Connect") {
                        if provider.mode == .localAdapter {
                            store.connectLocalAdapter(provider)
                        } else {
                            store.connectCloudOAuth(provider)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(minHeight: 24)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func connectionDescription(_ provider: ConnectionProvider) -> String {
        if provider == .codex {
            return "Reads Codex's local workspace index and imports its project folders automatically."
        }
        if provider.mode == .localAdapter {
            return "Reads \(provider.title)'s recent workspace index and imports project folders automatically."
        }
        if provider == .render {
            return "Browser OAuth through Render's hosted MCP server; no API key is requested."
        }
        return "Connect the account and import its repositories or deployed projects."
    }

    @ViewBuilder
    private func usageView(_ connection: DeveloperConnection, provider: ConnectionProvider) -> some View {
        if let accountUsage = connection.accountUsage {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if let account = accountUsage.accountEmail {
                        Text(account)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let plan = accountUsage.planName {
                        Text(plan)
                            .foregroundStyle(provider.tint)
                    }
                }
                .font(.caption2.weight(.semibold))

                if let primary = accountUsage.primary {
                    accountUsageWindow(primary, tint: provider.tint)
                }
                if let secondary = accountUsage.secondary {
                    accountUsageWindow(secondary, tint: provider.tint)
                }
                if let count = accountUsage.availableResetCredits {
                    Text("\(count) limit reset credit\(count == 1 ? "" : "s") available")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(provider.tint)
                }
                if let metrics = accountUsage.metrics, !metrics.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(Array(metrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(metric.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                            }
                        }
                    }
                }
                if let note = accountUsage.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let value = accountUsage.detailsURL, let url = URL(string: value) {
                    Link("Open usage dashboard", destination: url)
                        .font(.caption2.weight(.semibold))
                }
            }
            .padding(.top, 3)
        } else if let usage = connection.usageStatus {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(usage.label)
                    Spacer()
                    Text("\(usage.remaining.formatted()) / \(usage.limit.formatted())")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.medium))
                ProgressView(value: usage.fractionRemaining)
                    .tint(usage.fractionRemaining < 0.15 ? .orange : provider.tint)
                if let resetAt = usage.resetAt {
                    Text("Allowance resets \(resetAt.compactRelative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let url = usageDashboardURL(provider) {
                    Link("Open usage dashboard", destination: url)
                        .font(.caption2.weight(.semibold))
                }
            }
            .padding(.top, 3)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Label(usageUnavailableText(provider), systemImage: "gauge.with.dots.needle.33percent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = usageDashboardURL(provider) {
                    Link("Open usage dashboard", destination: url)
                        .font(.caption2.weight(.semibold))
                }
            }
        }
    }

    private func accountUsageWindow(_ window: ProviderUsageWindow, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(window.title) \(window.remainingPercent)% left")
                Spacer()
                if let resetAt = window.resetAt {
                    Text("Resets \(resetAt.compactRelative)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2.weight(.medium))
            ProgressView(value: window.fractionRemaining)
                .tint(window.remainingPercent <= 15 ? .red : tint)
        }
    }

    private func usageUnavailableText(_ provider: ConnectionProvider) -> String {
        switch provider {
        case .github, .cloudflare, .vercel:
            "API allowance will appear after the next successful sync."
        case .render:
            "Render exposes API allowance; billing usage remains in its dashboard."
        case .codex:
            "Open Codex and sign in, then sync to load plan usage."
        default:
            "Subscription credits are not exposed to local adapters."
        }
    }

    private func usageDashboardURL(_ provider: ConnectionProvider) -> URL? {
        let value: String? = switch provider {
        case .claudeCode: "https://claude.ai/settings/usage"
        case .openCode: "https://opencode.ai/console/usage"
        case .cursor: "https://cursor.com/dashboard"
        case .github: "https://github.com/settings/billing/usage"
        case .cloudflare: "https://dash.cloudflare.com/?to=/:account/billing"
        case .vercel: "https://vercel.com/dashboard/usage"
        case .render: "https://dashboard.render.com/billing"
        case .codex, .vscode, .xcode: nil
        }
        return value.flatMap(URL.init(string:))
    }
}
