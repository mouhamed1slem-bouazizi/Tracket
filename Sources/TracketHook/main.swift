import Darwin
import Foundation

private struct InboxEvent: Codable {
    let id: UUID
    let occurredAt: Date
    let source: String
    let event: String
    let cwd: String
    let sessionID: String?
    let turnID: String?
    let toolName: String?
}

private func argument(named name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

private let inputData = FileHandle.standardInput.readDataToEndOfFile()
private let payload = (try? JSONSerialization.jsonObject(with: inputData)) as? [String: Any] ?? [:]

private let record = InboxEvent(
    id: UUID(),
    occurredAt: Date(),
    source: argument(named: "--source") ?? "codex",
    event: argument(named: "--event") ?? payload["hook_event_name"] as? String ?? "activity",
    cwd: argument(named: "--cwd") ?? payload["cwd"] as? String ?? FileManager.default.currentDirectoryPath,
    sessionID: payload["session_id"] as? String,
    turnID: payload["turn_id"] as? String,
    toolName: payload["tool_name"] as? String
)

do {
    let inbox: URL
    if let override = ProcessInfo.processInfo.environment["TRACKET_INBOX_PATH"], !override.isEmpty {
        inbox = URL(fileURLWithPath: override)
        try FileManager.default.createDirectory(
            at: inbox.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    } else {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("Tracket", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        inbox = directory.appendingPathComponent("activity-inbox.jsonl")
    }
    if !FileManager.default.fileExists(atPath: inbox.path) {
        FileManager.default.createFile(atPath: inbox.path, contents: nil)
    }

    var bytes = Array(try JSONEncoder().encode(record))
    bytes.append(0x0A)
    let descriptor = open(inbox.path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR)
    if descriptor >= 0 {
        _ = bytes.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        }
        close(descriptor)
    }
} catch {
    // Hooks must never block the coding agent because telemetry could not be saved.
}

// A JSON object is valid output for every Codex lifecycle event used by Tracket.
print("{}")
