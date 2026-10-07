import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: AppStore
    let project: TracketProject

    @State private var showingEditor = false
    @State private var showingLiveSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var chatDraft = ""

    private var isWorking: Bool { store.workingProjectID == project.id }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [project.stage.tint.opacity(0.10), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    projectHeader
                    if let summary = project.aiSummary {
                        aiSummary(summary)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 18) {
                            nextMove
                            recentActivity
                            roadmap
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 18) {
                            momentum
                            health
                            integrations
                        }
                        .frame(width: 300)
                    }
                    projectAIChat
                }
                .padding(30)
                .frame(maxWidth: 1_200, alignment: .leading)
            }
        }
        .navigationTitle(project.name)
        .toolbar { toolbar }
        .sheet(isPresented: $showingEditor) {
            ProjectEditorSheet(project: project)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingLiveSheet) {
            MarkLiveSheet(project: project)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Stop tracking \(project.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Tracking", role: .destructive) { store.delete(project) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project files will not be changed. Only Tracket's local record will be removed.")
        }
    }

    private var projectHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(project.stage.tint.opacity(0.13))
                Image(systemName: project.stage.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(project.stage.tint)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(project.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    StagePill(stage: project.stage)
                }
                Text(project.goal)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 14) {
                    if let branch = project.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    Label(project.path, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    ProgressView(value: Double(project.completionPercent), total: 100)
                        .frame(width: 150)
                        .tint(project.stage.tint)
                    Text("AI estimate: \(project.completionPercent)% complete · \(project.remainingPercent)% remaining")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(project.stage.tint)
                }
            }
            Spacer()
        }
    }

    private func aiSummary(_ summary: String) -> some View {
        Surface(padding: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(TracketTheme.brandGradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI project read")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(summary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rationale = project.aiCompletionRationale {
                        Text(rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
        }
    }

    private var nextMove: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Next move", systemImage: "scope")
                        .font(.headline)
                    Spacer()
                    if let active = project.activeTask {
                        Text(active.priority.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active.priority == .high ? .orange : .secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(project.activeTask?.title ?? project.nextSuggestion ?? "Choose a launch milestone")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(project.activeTask?.detail ?? "Use the AI planner to turn this project into a concrete release roadmap.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if let active = project.activeTask {
                        Label("Due \(active.dueDate.compactRelative)", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.toggleRoadmapItem(projectID: project.id, itemID: active.id)
                        } label: {
                            Label("Mark complete", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Spacer()
                        Button("Build roadmap with AI") { store.generateAIPlan(for: project) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var roadmap: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Road to live")
                            .font(.title3.bold())
                        Text("\(project.completedTaskCount) of \(project.roadmap.count) milestones complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView(value: project.progress)
                        .frame(width: 120)
                        .tint(project.stage.tint)
                }

                Divider()

                ForEach(Array(project.roadmap.enumerated()), id: \.element.id) { index, item in
                    RoadmapRow(
                        number: index + 1,
                        item: item,
                        onToggle: { store.toggleRoadmapItem(projectID: project.id, itemID: item.id) }
                    )
                    if index < project.roadmap.count - 1 { Divider().padding(.leading, 45) }
                }

                if project.roadmap.allSatisfy({ $0.status == .done }) && project.stage != .live {
                    Button {
                        showingLiveSheet = true
                    } label: {
                        Label("Add live URL and celebrate the launch", systemImage: "party.popper.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        let events = store.recentActivities(for: project.id)
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Development activity")
                            .font(.title3.bold())
                        Text("Captured while the Tracket window is open or closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isBackgroundScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Sync now") { store.monitorNow(forceRemoteSync: true) }
                            .buttonStyle(.bordered)
                    }
                }

                if events.isEmpty {
                    Label(
                        "No new activity yet. Tracket is watching workspace and Git signals.",
                        systemImage: "waveform.path.ecg"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    ForEach(events) { activity in
                        ActivityRow(activity: activity)
                        if activity.id != events.last?.id { Divider().padding(.leading, 42) }
                    }
                }
            }
        }
    }

    private var momentum: some View {
        Surface {
            VStack(spacing: 15) {
                MomentumRing(score: project.momentumScore)
                VStack(spacing: 3) {
                    Text("\(project.momentumLabel) momentum")
                        .font(.headline)
                    Text(momentumExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var momentumExplanation: String {
        if project.daysSinceActivity == 0 { return "Meaningful activity today—keep the loop open." }
        if project.daysSinceActivity == 1 { return "Last meaningful activity was yesterday." }
        return "Last meaningful activity was \(project.daysSinceActivity) days ago."
    }

    private var health: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Text("Project signals")
                    .font(.headline)
                SignalRow(
                    label: "Deadline",
                    value: project.daysUntilDeadline < 0 ? "\(-project.daysUntilDeadline)d overdue" : "\(project.daysUntilDeadline)d left",
                    symbol: "calendar",
                    tint: project.daysUntilDeadline < 0 ? .red : .blue
                )
                SignalRow(
                    label: "Recent commits",
                    value: "\(project.commitCountLast7Days) this week",
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    tint: project.commitCountLast7Days > 0 ? .green : .orange
                )
                SignalRow(
                    label: "Working tree",
                    value: project.uncommittedChanges == 0 ? "Clean" : "\(project.uncommittedChanges) changes",
                    symbol: "arrow.triangle.branch",
                    tint: project.uncommittedChanges == 0 ? .green : .yellow
                )
                if !project.languages.isEmpty {
                    SignalRow(
                        label: "Stack",
                        value: project.languages.joined(separator: ", "),
                        symbol: "chevron.left.forwardslash.chevron.right",
                        tint: .purple
                    )
                }
            }
        }
    }

    private var integrations: some View {
        Surface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Connected workspace")
                        .font(.headline)
                    Spacer()
                    Text("Detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if project.detectedTools.isEmpty {
                    Text("No supported developer tools were detected in this folder yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], alignment: .leading, spacing: 8) {
                        ForEach(project.detectedTools) { tool in
                            Button { store.openProject(project, with: tool) } label: {
                                ToolChip(tool: tool)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let url = project.deploymentURL, let liveURL = URL(string: url) {
                    Divider()
                    Link(destination: liveURL) {
                        Label("Open live product", systemImage: "arrow.up.right.square")
                    }
                }

                Divider()
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex event bridge")
                            .font(.subheadline.weight(.semibold))
                        Text(store.isCodexConnected(to: project) ? "Lifecycle events connected" : "Adds privacy-safe project hooks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isCodexConnected(to: project) ? "Connected" : "Connect") {
                        store.connectCodex(to: project)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isCodexConnected(to: project))
                }
            }
        }
    }

    private var projectAIChat: some View {
        let workspace = store.projectAIWorkspace(for: project.id)
        let session = workspace.currentSession
        let isReplying = store.aiChattingProjectIDs.contains(project.id)
        return Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.title2)
                        .foregroundStyle(TracketTheme.brandGradient)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Talk with your project AI")
                            .font(.title3.bold())
                        Text("Uses \(store.activeAIProviderTitle) and keeps memory separate for \(project.name).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if workspace.sessions.count > 1 {
                        Menu {
                            ForEach(workspace.sessions.reversed()) { item in
                                Button {
                                    store.selectProjectAISession(projectID: project.id, sessionID: item.id)
                                } label: {
                                    HStack {
                                        Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        if item.id == workspace.currentSessionID { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(isReplying)
                    }
                    Button {
                        store.startNewProjectAISession(projectID: project.id)
                    } label: {
                        Label("New session", systemImage: "plus.bubble")
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.messages.isEmpty || isReplying)
                }

                HStack(spacing: 8) {
                    Label(store.activeAIProviderTitle, systemImage: "cpu")
                    Label(store.activeAIChatContextTitle, systemImage: "doc.text.magnifyingglass")
                    if !workspace.memory.summary.isEmpty || !workspace.memory.skills.isEmpty {
                        Label("Memory loaded", systemImage: "brain.head.profile.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !workspace.memory.summary.isEmpty || !workspace.memory.skills.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            if !workspace.memory.summary.isEmpty {
                                Text(workspace.memory.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if !workspace.memory.skills.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 7) {
                                    ForEach(workspace.memory.skills) { skill in
                                        Text(skill.name)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.quaternary, in: Capsule())
                                            .help(skill.detail)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Project memory and learned skills")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Divider()

                if session.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ask about architecture, bugs, implementation choices, testing, or the fastest path to deployment.")
                            .font(.subheadline)
                        Text("A new session starts with this project's saved memory and skills, without mixing information from other projects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(session.messages.suffix(30))) { message in
                            ProjectAIMessageBubble(message: message)
                        }
                        if isReplying {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text("Reading the project and thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask anything about this project…", text: $chatDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...7)
                        .onSubmit(sendChatMessage)
                    Button(action: sendChatMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TracketTheme.accent)
                    .disabled(chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReplying)
                }
            }
        }
    }

    private func sendChatMessage() {
        let message = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !store.aiChattingProjectIDs.contains(project.id) else { return }
        chatDraft = ""
        store.sendProjectAIMessage(message, projectID: project.id)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let provider = project.sourceProvider, !project.isLocalProject {
                    store.syncConnection(provider)
                } else {
                    store.rescan(project)
                }
            } label: {
                Label(project.isLocalProject ? "Refresh" : "Sync provider", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking)

            Button {
                store.generateAIPlan(for: project)
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("AI Plan", systemImage: "sparkles")
                }
            }
            .disabled(isWorking)
            .buttonStyle(.borderedProminent)

            Menu {
                Button(project.isLocalProject ? "Show in Finder" : "Open project") { store.openProject(project) }
                ForEach(project.isLocalProject ? project.detectedTools.filter { $0 != .git } : []) { tool in
                    Button("Open with \(tool.title)") { store.openProject(project, with: tool) }
                }
                Divider()
                Button("Edit project…") { showingEditor = true }
                Button("Mark as live…") { showingLiveSheet = true }
                Divider()
                Button("Stop tracking…", role: .destructive) { showingDeleteConfirmation = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private struct ProjectAIMessageBubble: View {
    let message: ProjectChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.role == .user ? "You" : "Project AI")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                messageText
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                message.role == .user ? TracketTheme.accent.opacity(0.14) : Color.secondary.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            if message.role == .assistant { Spacer(minLength: 50) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var messageText: some View {
        if let attributed = try? AttributedString(markdown: message.content) {
            Text(attributed)
        } else {
            Text(message.content)
        }
    }
}

private struct RoadmapRow: View {
    let number: Int
    let item: RoadmapItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(circleColor.opacity(item.status == .done ? 1 : 0.12))
                    if item.status == .done {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.caption.bold())
                            .foregroundStyle(circleColor)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .strikethrough(item.status == .done)
                        .foregroundStyle(item.status == .done ? .secondary : .primary)
                    if item.status == .active {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(TracketTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(TracketTheme.accent.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Text(item.dueDate.compactDate)
                        .font(.caption)
                        .foregroundStyle(item.dueDate < Date() && item.status != .done ? .red : .secondary)
                }
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var circleColor: Color {
        switch item.status {
        case .done: .green
        case .active: TracketTheme.accent
        case .todo: .secondary
        }
    }
}

private struct SignalRow: View {
    let label: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

private struct ProjectEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TracketProject

    init(project: TracketProject) {
        _draft = State(initialValue: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit project")
                .font(.title2.bold())
            Form {
                TextField("Name", text: $draft.name)
                TextField("Release goal", text: $draft.goal, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Stage", selection: $draft.stage) {
                    ForEach(ProjectStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                DatePicker("Deadline", selection: $draft.deadline, displayedComponents: .date)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.updateProject(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

private struct MarkLiveSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let project: TracketProject

    @State private var url: String = "https://"

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 42))
                .foregroundStyle(TracketTheme.brandGradient)
            Text("Make it real")
                .font(.title.bold())
            Text("Add the public URL for \(project.name). This is the finish line Tracket is designed to protect.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("https://your-project.com", text: $url)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Mark as live") {
                    store.markLive(projectID: project.id, deploymentURL: url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(URL(string: url)?.scheme == nil || url == "https://")
            }
        }
        .padding(28)
        .frame(width: 470)
    }
}
