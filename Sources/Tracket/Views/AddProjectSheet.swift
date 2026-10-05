import AppKit
import SwiftUI

struct AddProjectSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var folderURL: URL?
    @State private var goal = ""
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 13) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TracketTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(TracketTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track a project")
                        .font(.title2.bold())
                    Text("Tracket reads project signals locally. It never edits your source files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Project folder")
                    .font(.headline)
                Button(action: chooseFolder) {
                    HStack(spacing: 12) {
                        Image(systemName: folderURL == nil ? "folder" : "checkmark.circle.fill")
                            .foregroundStyle(folderURL == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folderURL?.lastPathComponent ?? "Choose a local folder")
                                .fontWeight(.medium)
                            Text(folderURL?.path ?? "Git, languages, and developer tools will be detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text("Choose…")
                            .foregroundStyle(TracketTheme.accent)
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("What does “shipped” mean?")
                    .font(.headline)
                TextField(
                    "Example: A usable beta deployed for five freelance designers",
                    text: $goal,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }

            DatePicker("Target launch", selection: $deadline, in: Date()..., displayedComponents: .date)
                .font(.headline)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if store.isWorking { ProgressView().controlSize(.small) }
                Button("Start tracking") {
                    guard let folderURL else { return }
                    store.addProject(from: folderURL, goal: goal, deadline: deadline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(folderURL == nil || store.isWorking)
            }
        }
        .padding(26)
        .frame(width: 580)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project folder"
        panel.prompt = "Track Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            folderURL = panel.url
        }
    }
}
