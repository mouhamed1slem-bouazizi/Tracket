import Foundation

enum ProjectChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ProjectChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var role: ProjectChatRole
    var content: String
    var createdAt: Date = Date()
}

struct ProjectChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var messages: [ProjectChatMessage] = []
}

struct ProjectAISkill: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var detail: String
    var updatedAt: Date = Date()
}

struct ProjectAIMemory: Codable, Hashable, Sendable {
    var summary: String = ""
    var skills: [ProjectAISkill] = []
    var updatedAt: Date = Date()
}

struct ProjectAIWorkspace: Codable, Hashable, Sendable {
    var projectID: UUID
    var sessions: [ProjectChatSession]
    var currentSessionID: UUID
    var memory: ProjectAIMemory

    init(projectID: UUID) {
        let session = ProjectChatSession()
        self.projectID = projectID
        self.sessions = [session]
        self.currentSessionID = session.id
        self.memory = ProjectAIMemory()
    }

    var currentSession: ProjectChatSession {
        sessions.first(where: { $0.id == currentSessionID }) ?? sessions.last ?? ProjectChatSession()
    }

    mutating func append(_ message: ProjectChatMessage, to sessionID: UUID? = nil) {
        let target = sessionID ?? currentSessionID
        guard let index = sessions.firstIndex(where: { $0.id == target }) else { return }
        sessions[index].messages.append(message)
        if sessions[index].messages.count > 100 {
            sessions[index].messages.removeFirst(sessions[index].messages.count - 100)
        }
    }

    mutating func startNewSession() {
        let session = ProjectChatSession()
        sessions.append(session)
        if sessions.count > 20 { sessions.removeFirst(sessions.count - 20) }
        currentSessionID = session.id
    }
}

struct ProjectAIChatResponse: Sendable {
    let answer: String
    let memorySummary: String
    let skills: [ProjectAISkill]
}
