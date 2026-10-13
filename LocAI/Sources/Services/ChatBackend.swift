import Foundation

/// Ported from llm_backends.BackendBase. Any inference backend (MLX now,
/// llama.cpp/GGUF later) conforms to this so the UI stays backend-agnostic.
protocol ChatBackend: AnyObject {
    /// Loads a local model file/folder and returns the runtime config
    /// derived from the memory budget (see RuntimeConfigCalculator).
    /// `adapter` is an optional LoRA / QLoRA adapter trained for this model.
    func load(path: URL, budgetGB: Double, forceSwap: Bool, adapter: LoRAAdapter?) async throws -> RuntimeConfig

    /// Streams response text deltas for the given chat history. Ending the
    /// iteration early (break / task cancellation) must stop generation.
    func streamChat(messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error>

    func unload()
}

enum ChatBackendFactory {
    static func make(_ backend: Backend) -> ChatBackend {
        switch backend {
        case .mlx:
            return MLXChatBackend()
        case .llamaCpp:
            return LlamaCppChatBackend()
        }
    }
}
