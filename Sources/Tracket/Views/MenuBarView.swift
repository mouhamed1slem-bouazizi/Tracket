import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    projectsSection
                    recentActivitySection
                    connectionUsageSection
                }
                .padding(16)
            }
            // MenuBarExtra otherwise accepts the ScrollView's zero-height ideal
            // size and renders only the header and footer.
            .frame(height: 500)

            Divider()
            controls
        }
        .frame(width: 370)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TracketTheme.brandGradient)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Tracket")
                        .font(.headline)
                    Circle()
                        .fill(store.monitoringEnabled ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isBackgroundScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    store.monitorNow(forceRemoteSync: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Scan projects and sync Git remotes")
                .disabled(!store.monitoringEnabled)
            }
        }
        .padding(14)
    }

    private var statusText: String {
        guard store.monitoringEnabled else { return "Background monitoring paused" }
        if store.isBackgroundScanning { return "Checking development progress…" }
        if let date = store.lastMonitorAt { return "Last checked \(date.compactRelative)" }
        return "Background monitoring active"
    }

    @ViewBuilder
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RECENT DEVELOPMENT")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            if store.recentDevelopmentProjects.isEmpty {
                Text("Recent projects from connected development tools will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.recentDevelopmentProjects.prefix(5))) { project in
                    Button {
                        store.selection = .project(project.id)
                        showMainWindow()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(project.stage.tint.opacity(0.18), lineWidth: 4)
                                Circle()
                                    .trim(from: 0, to: CGFloat(project.completionPercent) / 100)
                                    .stroke(project.stage.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 31, height: 31)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.subheadline.weight(.semibold))
                                if let tool = project.latestDevelopmentTool {
                                    Label("\(tool.title) · \(project.latestDevelopmentActivityAt.compactRelative)", systemImage: tool.symbol)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(project.completionPercent)% done")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            if store.recentActivities.isEmpty {
                Text("New commits, pushes, edits, and agent events will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.recentActivities.prefix(5))) { activity in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: activity.source.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(activity.source.tint)
                            .frame(width: 24, height: 24)
                            .background(activity.source.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(store.projectName(for: activity)) · \(activity.occurredAt.compactRelative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionUsageSection: some View {
        let connected = store.connections.filter { $0.lastError == nil }
        if !connected.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONNECTED SERVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(connected) { connection in
                    providerUsageCard(connection)
                }
            }
        }
    }

    private func providerUsageCard(_ connection: DeveloperConnection) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: connection.provider.symbol)
                    .foregroundStyle(connection.provider.tint)
                    .frame(width: 18, height: 18)
                    .background(connection.provider.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.provider.title)
                        .font(.caption.weight(.bold))
                    if let account = connection.accountUsage?.accountEmail ?? connection.accountName {
                        Text(account)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let plan = connection.accountUsage?.planName {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(connection.provider.tint)
                }
            }

            if let usage = connection.accountUsage {
                Divider()
                if let primary = usage.primary {
                    usageWindow(primary, tint: connection.provider.tint)
                }
                if let secondary = usage.secondary {
                    usageWindow(secondary, tint: connection.provider.tint)
                }

                if usage.availableResetCredits != nil || usage.creditBalance != nil || usage.unlimitedCredits {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Limit reset credits")
                                .font(.caption.weight(.semibold))
                            if let count = usage.availableResetCredits {
                                Text("\(count) available")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(connection.provider.tint)
                            }
                        }
                        Spacer()
                        if usage.unlimitedCredits {
                            Text("Unlimited")
                                .font(.caption2.weight(.semibold))
                        } else if let balance = usage.creditBalance {
                            Text(formattedCredit(balance, currency: usage.creditCurrency))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                        }
                    }
                    if let expiration = usage.resetCreditExpirations.min() {
                        Text("Next credit expires \(expiration.compactRelative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let metrics = usage.metrics, !metrics.isEmpty {
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(metric.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                if let detail = metric.detail {
                                    Text(detail)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                if let note = usage.note {
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let value = usage.detailsURL, let url = URL(string: value) {
                    Link("Open usage dashboard", destination: url)
                        .font(.caption2.weight(.semibold))
                }

                HStack {
                    if let model = usage.modelName {
                        Text("Model: \(model)")
                    } else {
                        Text("Usage details")
                    }
                    Spacer()
                    Text("Updated \(usage.checkedAt.compactRelative)")
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            } else if let usage = connection.usageStatus {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(usage.label)
                            .font(.caption2.weight(.semibold))
                        Spacer()
                        Text("\(usage.remaining.formatted()) / \(usage.limit.formatted()) left")
                            .font(.caption2.monospacedDigit())
                    }
                    ProgressView(value: usage.fractionRemaining)
                        .tint(usage.fractionRemaining < 0.15 ? .orange : connection.provider.tint)
                    if let resetAt = usage.resetAt {
                        Text("Resets \(resetAt.compactRelative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let url = usageDashboardURL(connection.provider) {
                        Link("Open usage dashboard", destination: url)
                            .font(.caption2.weight(.semibold))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(unavailableUsageText(connection.provider))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = usageDashboardURL(connection.provider) {
                        Link("Open usage dashboard", destination: url)
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func usageWindow(_ window: ProviderUsageWindow, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(window.title) \(window.remainingPercent)% left")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let reset = window.resetAt {
                    Text("Resets \(reset.compactRelative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: window.fractionRemaining)
                .tint(window.remainingPercent <= 15 ? .red : tint)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                store.setMonitoringEnabled(!store.monitoringEnabled)
            } label: {
                Label(store.monitoringEnabled ? "Pause" : "Resume", systemImage: store.monitoringEnabled ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Open Tracket") {
                showMainWindow()
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button("Settings…") {
                    store.selection = .settings
                    showMainWindow()
                }
                Divider()
                Button("Quit Tracket") {
                    if let delegate = NSApplication.shared.delegate as? TracketAppDelegate {
                        delegate.quitFromMenuBar()
                    } else {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func unavailableUsageText(_ provider: ConnectionProvider) -> String {
        switch provider {
        case .github, .cloudflare, .vercel:
            "API allowance will appear after a successful account sync."
        case .render:
            "Render exposes API allowance here; billing usage remains in its dashboard."
        case .codex:
            "Open Codex and sign in, then refresh Tracket to load plan usage."
        default:
            "This local adapter does not expose subscription usage to Tracket."
        }
    }

    private func formattedCredit(_ balance: String, currency: String?) -> String {
        if currency == nil || currency == "USD" {
            return balance == "0" ? "$0.00" : "$\(balance)"
        }
        return "\(currency!) \(balance)"
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
