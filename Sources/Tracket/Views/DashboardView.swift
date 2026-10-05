import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [
        GridItem(.adaptive(minimum: 310, maximum: 460), spacing: 16)
    ]

    var body: some View {
        ZStack {
            TracketTheme.softGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if store.projects.isEmpty {
                        emptyState
                    } else {
                        metrics
                        focusStrip
                        recentBackgroundActivity
                        projectGrid
                    }
                }
                .padding(30)
                .frame(maxWidth: 1_180, alignment: .leading)
            }
        }
        .navigationTitle("Mission control")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.isAddingProject = true
                } label: {
                    Label("Track Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var recentBackgroundActivity: some View {
        if !store.recentActivities.isEmpty {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Since you were away")
                                .font(.title3.bold())
                            Text("Collected continuously by the menu-bar monitor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.monitoringEnabled ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(store.monitoringEnabled ? "Monitoring" : "Paused")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(store.recentActivities.prefix(4))) { activity in
                        ActivityRow(activity: activity, context: store.projectName(for: activity))
                        if activity.id != store.recentActivities.prefix(4).last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                Text("Turn unfinished experiments into small, live products.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.projects.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline.weight(.semibold))
                    Text("One meaningful step is enough for today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            MetricCard(
                title: "Active projects",
                value: "\(store.activeProjects.count)",
                caption: "\(store.projects.filter { $0.stage == .live }.count) already live",
                symbol: "square.stack.3d.up.fill",
                tint: TracketTheme.accent
            )
            MetricCard(
                title: "Average momentum",
                value: "\(store.averageMomentum)%",
                caption: momentumCaption,
                symbol: "bolt.fill",
                tint: .yellow
            )
            MetricCard(
                title: "Needs attention",
                value: "\(store.atRiskProjects.count)",
                caption: store.atRiskProjects.isEmpty ? "Everything is moving" : "Stalled or past deadline",
                symbol: "exclamationmark.triangle.fill",
                tint: store.atRiskProjects.isEmpty ? .green : .orange
            )
        }
    }

    private var momentumCaption: String {
        switch store.averageMomentum {
        case 75...: "Strong shipping rhythm"
        case 45...: "Good—protect the streak"
        case 1...: "Choose one small next step"
        default: "Start with your first project"
        }
    }

    @ViewBuilder
    private var focusStrip: some View {
        if let project = store.activeProjects.sorted(by: { lhs, rhs in
            if lhs.isAtRisk != rhs.isAtRisk { return lhs.isAtRisk }
            return lhs.deadline < rhs.deadline
        }).first {
            Surface {
                HStack(spacing: 18) {
                    Image(systemName: project.isAtRisk ? "flame.fill" : "scope")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(project.isAtRisk ? .orange : TracketTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(
                            (project.isAtRisk ? Color.orange : TracketTheme.accent).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.isAtRisk ? "Rescue this project" : "Best next move")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(project.activeTask?.title ?? project.nextSuggestion ?? "Choose the next release milestone")
                            .font(.headline)
                        Text("\(project.name) · due \(project.deadline.compactRelative)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Focus") {
                        store.selection = .project(project.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var projectGrid: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Your projects")
                    .font(.title2.bold())
                Spacer()
                Text("\(store.projects.count) tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.projects) { project in
                    DashboardProjectCard(project: project)
                        .onTapGesture { store.selection = .project(project.id) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(TracketTheme.brandGradient)
                    .frame(width: 92, height: 92)
                    .blur(radius: 18)
                    .opacity(0.35)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 45, weight: .semibold))
                    .foregroundStyle(TracketTheme.brandGradient)
            }
            Text("Bring one project back to life")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Choose a local project folder. Tracket will read its development signals, build a launch roadmap, and help you keep momentum until it is live.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            Button {
                store.isAddingProject = true
            } label: {
                Label("Track your first project", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 480)
        .padding(32)
    }
}

private struct DashboardProjectCard: View {
    let project: TracketProject

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(project.name)
                            .font(.title3.bold())
                            .lineLimit(1)
                        StagePill(stage: project.stage)
                    }
                    Spacer()
                    MomentumRing(score: project.momentumScore, size: 72)
                }

                Text(project.activeTask?.title ?? project.nextSuggestion ?? "Plan the next release step")
                    .font(.headline)
                    .lineLimit(2)

                VStack(spacing: 7) {
                    HStack {
                        Text("AI completion")
                        Spacer()
                        Text("\(project.remainingPercent)% remaining")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    ProgressView(value: Double(project.completionPercent), total: 100)
                        .tint(project.stage.tint)
                }

                HStack {
                    Label(project.lastActivityAt.compactRelative, systemImage: "clock")
                    Spacer()
                    Label(
                        project.daysUntilDeadline < 0 ? "Overdue" : "\(project.daysUntilDeadline)d left",
                        systemImage: "calendar"
                    )
                    .foregroundStyle(project.daysUntilDeadline < 0 ? .red : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
