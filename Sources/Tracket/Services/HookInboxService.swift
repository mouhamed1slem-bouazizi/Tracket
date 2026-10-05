import Foundation

struct HookInboxReadResult {
    let events: [HookInboxEvent]
    let nextOffset: UInt64
}

struct HookInboxService {
    private let overrideInboxURL: URL?

    init(inboxURL: URL? = nil) {
        self.overrideInboxURL = inboxURL
    }

    func readNewEvents(from savedOffset: UInt64) -> HookInboxReadResult {
        guard let inboxURL else { return HookInboxReadResult(events: [], nextOffset: savedOffset) }
        guard let handle = try? FileHandle(forReadingFrom: inboxURL) else {
            return HookInboxReadResult(events: [], nextOffset: 0)
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let startOffset = savedOffset <= fileSize ? savedOffset : 0
        try? handle.seek(toOffset: startOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            return HookInboxReadResult(events: [], nextOffset: startOffset)
        }

        let bytes = Array(data)
        guard let finalNewline = bytes.lastIndex(of: 0x0A) else {
            return HookInboxReadResult(events: [], nextOffset: startOffset)
        }

        let completeData = Data(bytes[0...finalNewline])
        let lines = completeData.split(separator: 0x0A)
        let decoder = JSONDecoder()
        let events = lines.compactMap { try? decoder.decode(HookInboxEvent.self, from: Data($0)) }
        return HookInboxReadResult(
            events: events,
            nextOffset: startOffset + UInt64(finalNewline + 1)
        )
    }

    private var inboxURL: URL? {
        if let overrideInboxURL { return overrideInboxURL }
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return appSupport
            .appendingPathComponent("Tracket", isDirectory: true)
            .appendingPathComponent("activity-inbox.jsonl")
    }
}
