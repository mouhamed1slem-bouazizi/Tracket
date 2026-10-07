import Foundation
import HuggingFace

actor LocalAIService: AIPlanningProvider {
    private var selectedModel: LocalAIModel = .qwenCoder7B
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootDirectory = support.appendingPathComponent("Tracket/Models", isDirectory: true)
        }
    }

    func select(_ model: LocalAIModel) {
        selectedModel = model
    }

    func state(for model: LocalAIModel) -> LocalModelState {
        let directory = modelDirectory(for: model)
        let size = directorySize(directory)
        if let snapshot = cachedSnapshotDirectory(for: model), isCompleteSnapshot(snapshot) {
            if !FileManager.default.fileExists(atPath: readyMarker(for: model).path) {
                try? Data("ready".utf8).write(to: readyMarker(for: model), options: .atomic)
            }
            return .ready(bytes: size)
        }
        return size > 1_000_000 ? .partial(bytes: size) : .notDownloaded
    }

    func download(
        _ model: LocalAIModel,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        select(model)
        let directory = modelDirectory(for: model)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: readyMarker(for: model))
        guard let repository = Repo.ID(rawValue: model.repositoryID) else {
            throw AIProviderError.api("The local model repository identifier is invalid.")
        }
        let client = HubClient(cache: HubCache(cacheDirectory: directory))
        let snapshot = try await client.downloadSnapshot(
            of: repository,
            progressHandler: { value in progress(value.fractionCompleted) }
        )
        guard isCompleteSnapshot(snapshot) else {
            throw AIProviderError.api("The model download finished without all required files. Choose Resume to retry it.")
        }
        let validation = try await runInferenceHelper(
            snapshot: snapshot,
            systemPrompt: "",
            prompt: "",
            maxTokens: 0,
            validateOnly: true
        )
        guard validation == "ready" else {
            throw AIProviderError.api("The downloaded model could not be verified. Choose Resume to repair it.")
        }
        try Data("ready".utf8).write(to: readyMarker(for: model), options: .atomic)
    }

    func remove(_ model: LocalAIModel) throws {
        let directory = modelDirectory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func createPlan(context: AIProjectContext) async throws -> AIProjectPlan {
        guard state(for: selectedModel).isReady else {
            throw AIProviderError.localModelRequired(selectedModel)
        }
        guard let snapshot = cachedSnapshotDirectory(for: selectedModel), isCompleteSnapshot(snapshot) else {
            throw AIProviderError.localModelRequired(selectedModel)
        }
        let output = try await runInferenceHelper(
            snapshot: snapshot,
            systemPrompt: AIPlanPrompt.system,
            prompt: AIPlanPrompt.input(for: context),
            maxTokens: 2_200,
            validateOnly: false
        )
        return try decodePlan(output)
    }

    func respond(systemPrompt: String, prompt: String, maxTokens: Int = 1_800) async throws -> String {
        guard state(for: selectedModel).isReady else {
            throw AIProviderError.localModelRequired(selectedModel)
        }
        guard let snapshot = cachedSnapshotDirectory(for: selectedModel), isCompleteSnapshot(snapshot) else {
            throw AIProviderError.localModelRequired(selectedModel)
        }
        return try await runInferenceHelper(
            snapshot: snapshot,
            systemPrompt: systemPrompt,
            prompt: prompt,
            maxTokens: maxTokens,
            validateOnly: false
        )
    }

    private func runInferenceHelper(
        snapshot: URL,
        systemPrompt: String,
        prompt: String,
        maxTokens: Int,
        validateOnly: Bool
    ) async throws -> String {
        guard let executable = inferenceHelperURL() else {
            throw AIProviderError.api("The Local AI helper is missing. Install the latest Tracket build and try again.")
        }
        let request = LocalAIHelperRequest(
            snapshotPath: snapshot.path,
            systemPrompt: systemPrompt,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: 0.2,
            validateOnly: validateOnly
        )
        let input = try JSONEncoder().encode(request)
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.currentDirectoryURL = snapshot

        do {
            try process.run()
        } catch {
            inputPipe.fileHandleForWriting.closeFile()
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            throw AIProviderError.api("Local AI could not start: \(error.localizedDescription)")
        }
        let outputTask = Task.detached { outputPipe.fileHandleForReading.readDataToEndOfFile() }
        let errorTask = Task.detached { errorPipe.fileHandleForReading.readDataToEndOfFile() }
        inputPipe.fileHandleForWriting.write(input)
        inputPipe.fileHandleForWriting.closeFile()

        await withTaskCancellationHandler {
            await Task.detached { process.waitUntilExit() }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        let outputData = await outputTask.value
        let errorData = await errorTask.value
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = (detail?.isEmpty == false) ? detail! : "The model runtime exited with status \(process.terminationStatus)."
            throw AIProviderError.api("Local AI stopped safely without closing Tracket. \(reason)")
        }
        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            throw AIProviderError.missingOutput
        }
        return output
    }

    private func inferenceHelperURL() -> URL? {
        let manager = FileManager.default
        let packaged = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tracket-local-ai")
        if manager.isExecutableFile(atPath: packaged.path) { return packaged }
        if let executable = Bundle.main.executableURL {
            let besideExecutable = executable.deletingLastPathComponent().appendingPathComponent("tracket-local-ai")
            if manager.isExecutableFile(atPath: besideExecutable.path) { return besideExecutable }
            let helpers = executable.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Helpers/tracket-local-ai")
            if manager.isExecutableFile(atPath: helpers.path) { return helpers }
        }
        return nil
    }

    private func modelDirectory(for model: LocalAIModel) -> URL {
        rootDirectory.appendingPathComponent(model.rawValue, isDirectory: true)
    }

    private func readyMarker(for model: LocalAIModel) -> URL {
        modelDirectory(for: model).appendingPathComponent(".tracket-ready")
    }

    private func cachedSnapshotDirectory(for model: LocalAIModel) -> URL? {
        guard let repository = Repo.ID(rawValue: model.repositoryID) else { return nil }
        let cache = HubCache(cacheDirectory: modelDirectory(for: model))
        guard let commit = cache.resolveRevision(repo: repository, kind: .model, ref: "main") else { return nil }
        return try? cache.snapshotPath(repo: repository, kind: .model, commitHash: commit)
    }

    private func isCompleteSnapshot(_ snapshot: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: snapshot.appendingPathComponent("config.json").path) else { return false }
        let tokenizerNames = ["tokenizer.json", "tokenizer_config.json", "tokenizer.model"]
        guard tokenizerNames.contains(where: { manager.fileExists(atPath: snapshot.appendingPathComponent($0).path) }) else {
            return false
        }
        guard let enumerator = manager.enumerator(
            at: snapshot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        var weightFiles = Set<String>()
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasSuffix(".incomplete") { return false }
            if url.pathExtension == "safetensors",
               let size = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 0 {
                weightFiles.insert(url.lastPathComponent)
            }
        }
        guard !weightFiles.isEmpty else { return false }

        let indexURL = snapshot.appendingPathComponent("model.safetensors.index.json")
        if manager.fileExists(atPath: indexURL.path) {
            guard let data = try? Data(contentsOf: indexURL),
                  let index = try? JSONDecoder().decode(SafetensorsIndex.self, from: data) else {
                return false
            }
            let requiredShards = Set(index.weightMap.values)
            guard !requiredShards.isEmpty else { return false }
            for shard in requiredShards {
                let shardURL = snapshot.appendingPathComponent(shard)
                guard manager.fileExists(atPath: shardURL.path),
                      let size = try? shardURL.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0 else {
                    return false
                }
            }
        }
        return true
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var size: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { continue }
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }
}

private struct LocalAIHelperRequest: Encodable {
    let snapshotPath: String
    let systemPrompt: String
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let validateOnly: Bool
}

private struct SafetensorsIndex: Decodable {
    let weightMap: [String: String]

    enum CodingKeys: String, CodingKey {
        case weightMap = "weight_map"
    }
}

actor AIService {
    private let local = LocalAIService()
    private let repositoryContext = RepositoryContextService()
    private let estimator = ProjectCompletionEstimator()

    func localState(for model: LocalAIModel) async -> LocalModelState {
        await local.state(for: model)
    }

    func download(
        _ model: LocalAIModel,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await local.download(model, progress: progress)
    }

    func remove(_ model: LocalAIModel) async throws {
        try await local.remove(model)
    }

    func createPlan(
        for project: TracketProject,
        settings: AISettings,
        cloudAPIKey: String?
    ) async throws -> AIProjectPlan {
        let context = AIProjectContext(
            project: project,
            measuredCompletion: estimator.estimate(project),
            repositoryEvidence: repositoryContext.build(for: project, sharing: settings.contextSharing)
        )
        await local.select(settings.localModel)

        switch settings.mode {
        case .local:
            return try await local.createPlan(context: context)
        case .cloud:
            return try await cloudPlan(context: context, settings: settings, key: cloudAPIKey)
        case .smartHybrid:
            do {
                return try await local.createPlan(context: context)
            } catch {
                guard settings.allowCloudFallback else { throw AIProviderError.cloudFallbackDisabled }
                return try await cloudPlan(context: context, settings: settings, key: cloudAPIKey)
            }
        }
    }

    func chat(
        for project: TracketProject,
        workspace: ProjectAIWorkspace,
        question: String,
        settings: AISettings,
        cloudAPIKey: String?
    ) async throws -> ProjectAIChatResponse {
        let chatSharing: AIContextSharing = settings.mode == .local ? .relevantSource : settings.contextSharing
        let evidence = repositoryContext.build(
            for: project,
            sharing: chatSharing,
            query: question
        )
        let prompt = ProjectAIChatPrompt.input(
            project: project,
            workspace: workspace,
            question: question,
            repositoryEvidence: evidence
        )
        await local.select(settings.localModel)
        let output: String

        switch settings.mode {
        case .local:
            output = try await local.respond(systemPrompt: ProjectAIChatPrompt.system, prompt: prompt)
        case .cloud:
            output = try await cloudResponse(
                systemPrompt: ProjectAIChatPrompt.system,
                prompt: prompt,
                settings: settings,
                key: cloudAPIKey
            )
        case .smartHybrid:
            do {
                output = try await local.respond(systemPrompt: ProjectAIChatPrompt.system, prompt: prompt)
            } catch {
                guard settings.allowCloudFallback else { throw AIProviderError.cloudFallbackDisabled }
                output = try await cloudResponse(
                    systemPrompt: ProjectAIChatPrompt.system,
                    prompt: prompt,
                    settings: settings,
                    key: cloudAPIKey
                )
            }
        }
        return decodeProjectChatResponse(output, previousMemory: workspace.memory)
    }

    private func cloudPlan(
        context: AIProjectContext,
        settings: AISettings,
        key: String?
    ) async throws -> AIProjectPlan {
        guard let key, !key.isEmpty else { throw AIProviderError.missingAPIKey(settings.cloudProvider.title) }
        guard let baseURL = URL(string: settings.effectiveBaseURL),
              let scheme = baseURL.scheme, ["https", "http"].contains(scheme) else {
            throw AIProviderError.api("Enter a valid provider base URL in Settings.")
        }
        return try await CloudAIService(
            provider: settings.cloudProvider,
            apiKey: key,
            model: settings.effectiveModel,
            baseURL: baseURL
        ).createPlan(context: context)
    }

    private func cloudResponse(
        systemPrompt: String,
        prompt: String,
        settings: AISettings,
        key: String?
    ) async throws -> String {
        guard let key, !key.isEmpty else { throw AIProviderError.missingAPIKey(settings.cloudProvider.title) }
        guard let baseURL = URL(string: settings.effectiveBaseURL),
              let scheme = baseURL.scheme, ["https", "http"].contains(scheme) else {
            throw AIProviderError.api("Enter a valid provider base URL in Settings.")
        }
        return try await CloudAIService(
            provider: settings.cloudProvider,
            apiKey: key,
            model: settings.effectiveModel,
            baseURL: baseURL
        ).respond(systemPrompt: systemPrompt, prompt: prompt)
    }
}
