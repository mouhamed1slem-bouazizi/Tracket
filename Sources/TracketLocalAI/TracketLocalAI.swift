import Darwin
import Foundation
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

private struct LocalAIHelperRequest: Decodable {
    let snapshotPath: String
    let systemPrompt: String
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let validateOnly: Bool
}

@main
private struct TracketLocalAI {
    static func main() async {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(LocalAIHelperRequest.self, from: input)
            let snapshot = URL(fileURLWithPath: request.snapshotPath, isDirectory: true)
            let container = try await LLMModelFactory.shared.loadContainer(
                from: snapshot,
                using: #huggingFaceTokenizerLoader()
            )
            if request.validateOnly {
                FileHandle.standardOutput.write(Data("ready".utf8))
                return
            }
            var parameters = GenerateParameters()
            parameters.maxTokens = request.maxTokens
            parameters.temperature = request.temperature
            let session = ChatSession(
                container,
                instructions: request.systemPrompt,
                generateParameters: parameters
            )
            let output = try await session.respond(to: request.prompt)
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch {
            let message = "\(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }
}
