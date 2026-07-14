import Foundation
// Add the "mlx-swift-examples" package in Xcode (File > Add Package
// Dependencies... > https://github.com/ml-explore/mlx-swift-examples)
// and link the MLXLLM + MLXLMCommon products against this target.
import MLX
import MLXLLM
import MLXLMCommon

/// Ported from llm_backends.MlxBackend. Loads an MLX model folder
/// (config.json + tokenizer + *.safetensors, as produced by
/// download_mlx_repo) and streams chat completions.
///
/// NOTE: mlx-swift-examples' public API has moved around between
/// releases; this targets the ModelContainer/GenerateParameters shape
/// current as of early 2026. If Xcode reports mismatches after adding
/// the package, this is the file to reconcile against whatever version
/// you pin - the load/stream logic itself (memory budget -> runtime
/// config, prompt building) is unchanged from the Python original.
final class MLXChatBackend: ChatBackend {
    private var container: ModelContainer?

    func load(path: URL, budgetGB: Double, forceSwap: Bool) async throws -> RuntimeConfig {
        // Mirrors llm_backends.MlxBackend.load: MLX exposes a real memory
        // cap via GPU.set(memoryLimit:); forced swap mode skips the cap so
        // macOS's compressed memory / swapfile can absorb the overflow.
        if forceSwap {
            GPU.set(cacheLimit: 0)
        } else {
            let budgetBytes = Int(budgetGB * 1_073_741_824)
            GPU.set(memoryLimit: budgetBytes)
            GPU.set(cacheLimit: Int(Double(budgetBytes) * 0.25))
        }

        let configuration = ModelConfiguration(directory: path)
        container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)

        return RuntimeConfigCalculator.suggest(budgetGB: budgetGB, forceSwap: forceSwap)
    }

    func streamChat(messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let container else {
                continuation.finish(throwing: NSError(domain: "MLXChatBackend", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No model loaded."
                ]))
                return
            }
            let chatMessages = messages.map { Chat.Message(role: $0.role.asMLXRole, content: $0.content) }
            let parameters = GenerateParameters(maxTokens: maxTokens)

            Task {
                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(input: .init(chat: chatMessages))
                        _ = try MLXLMCommon.generate(input: input, parameters: parameters, context: context) { tokens in
                            if let text = try? context.tokenizer.decode(tokens: tokens) {
                                continuation.yield(text)
                            }
                            return .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unload() {
        container = nil
    }
}

private extension ChatRole {
    var asMLXRole: Chat.Message.Role {
        switch self {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}
