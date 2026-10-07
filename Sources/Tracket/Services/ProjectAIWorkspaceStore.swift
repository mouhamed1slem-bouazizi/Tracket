import Foundation

struct ProjectAIWorkspaceStore {
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootDirectory = support.appendingPathComponent("Tracket/AIWorkspaces", isDirectory: true)
        }
    }

    func loadAll() -> [UUID: ProjectAIWorkspace] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [UUID: ProjectAIWorkspace] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let workspace = try? JSONDecoder().decode(ProjectAIWorkspace.self, from: data) else { continue }
            result[workspace.projectID] = workspace
        }
        return result
    }

    func save(_ workspace: ProjectAIWorkspace) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(workspace)
        try data.write(to: fileURL(for: workspace.projectID), options: .atomic)
    }

    func remove(projectID: UUID) throws {
        let url = fileURL(for: projectID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func reset() throws {
        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.removeItem(at: rootDirectory)
        }
    }

    private func fileURL(for projectID: UUID) -> URL {
        rootDirectory.appendingPathComponent(projectID.uuidString).appendingPathExtension("json")
    }
}
