import Foundation
// Add the "mlx-swift-examples" package in Xcode (File > Add Package
// Dependencies... > https://github.com/ml-explore/mlx-swift-examples)
// and link the MLXLLM + MLXLMCommon products against this target.
#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon
import Tokenizers
#endif

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
#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
    private static let cacheLimitBytes = 32 * 1024 * 1024
    private var container: ModelContainer?

    func load(path: URL, budgetGB: Double, forceSwap: Bool) async throws -> RuntimeConfig {
        // Keep MLX's reusable buffer cache small so process memory stays
        // available for model weights and KV cache, especially on iOS.
        if forceSwap {
            GPU.set(cacheLimit: 0)
        } else {
            let budgetBytes = Int(budgetGB * 1_073_741_824)
            GPU.set(memoryLimit: budgetBytes)
            GPU.set(cacheLimit: min(Self.cacheLimitBytes, Int(Double(budgetBytes) * 0.05)))
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

                        var previousText = ""

                        _ = try MLXLMCommon.generate(input: input, parameters: parameters, context: context) { tokens in
                            let text = context.tokenizer.decode(tokens: tokens)

                            if text.count > previousText.count {
                                let delta = String(text.dropFirst(previousText.count))
                                previousText = text
                                continuation.yield(delta)
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
        GPU.set(cacheLimit: 0)
    }
#else
    func load(path: URL, budgetGB: Double, forceSwap: Bool) async throws -> RuntimeConfig {
        throw NSError(domain: "MLXChatBackend", code: 501, userInfo: [
            NSLocalizedDescriptionKey: "The MLX backend package is not linked. Add mlx-swift-examples and link MLXLLM + MLXLMCommon to use MLX models."
        ])
    }

    func streamChat(messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NSError(domain: "MLXChatBackend", code: 501, userInfo: [
                NSLocalizedDescriptionKey: "The MLX backend package is not linked. Add mlx-swift-examples and link MLXLLM + MLXLMCommon to use MLX models."
            ]))
        }
    }

    func unload() {}
#endif
}

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
private extension ChatRole {
    var asMLXRole: Chat.Message.Role {
        switch self {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }
}
#endif
