import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            detail
        }
        .tint(TracketTheme.accent)
        .sheet(isPresented: $store.isAddingProject) {
            AddProjectSheet()
                .environmentObject(store)
        }
        .alert(
            "Tracket",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            )
        ) {
            Button("OK") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .dashboard:
            DashboardView()
        case .project(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectDetailView(project: project)
            } else {
                DashboardView()
            }
        case .settings:
            SettingsView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TracketTheme.brandGradient)
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Tracket")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Build. Finish. Ship.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            List(selection: $store.selection) {
                Label("Mission control", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarSelection.dashboard)

                Section("Projects") {
                    ForEach(store.projects) { project in
                        ProjectSidebarRow(project: project)
                            .tag(SidebarSelection.project(project.id))
                            .contextMenu {
                                Button(project.isLocalProject ? "Show in Finder" : "Open project") { store.openProject(project) }
                                Button("Refresh") {
                                    if let provider = project.sourceProvider, !project.isLocalProject {
                                        store.syncConnection(provider)
                                    } else {
                                        store.rescan(project)
                                    }
                                }
                                Divider()
                                Button("Stop Tracking", role: .destructive) { store.delete(project) }
                            }
                    }

                    Button {
                        store.isAddingProject = true
                    } label: {
                        Label("Track a project", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)

            Divider()
            Button {
                store.selection = .settings
            } label: {
                HStack {
                    Label("Settings", systemImage: "gearshape.fill")
                    Spacer()
                    Circle()
                        .fill(store.hasAPIKey ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(store.selection == .settings ? Color.accentColor.opacity(0.12) : .clear)
        }
        .background(.ultraThinMaterial)
    }
}

private struct ProjectSidebarRow: View {
    let project: TracketProject

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(project.stage.tint)
                .frame(width: 8, height: 8)
                .shadow(color: project.stage.tint.opacity(0.5), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let tool = project.latestDevelopmentTool {
                        Image(systemName: tool.symbol)
                            .foregroundStyle(TracketTheme.accent)
                        Text(tool.title)
                            .foregroundStyle(.primary)
                    } else {
                        Image(systemName: "questionmark.app.dashed")
                        Text("IDE unknown")
                    }
                    Text("· \(project.remainingPercent)% left · \(project.stage.title)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if project.isAtRisk {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

enum TracketTheme {
    static let accent = Color(red: 0.36, green: 0.42, blue: 0.96)
    static let cyan = Color(red: 0.20, green: 0.78, blue: 0.91)
    static let brandGradient = LinearGradient(
        colors: [accent, Color(red: 0.63, green: 0.35, blue: 0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let softGradient = LinearGradient(
        colors: [accent.opacity(0.15), cyan.opacity(0.08), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
