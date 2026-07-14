import Foundation

/// Ported from llm_backends.BackendBase. Any inference backend (MLX now,
/// llama.cpp/GGUF later) conforms to this so the UI stays backend-agnostic.
protocol ChatBackend: AnyObject {
    /// Loads a local model file/folder and returns the runtime config
    /// derived from the memory budget (see RuntimeConfigCalculator).
    func load(path: URL, budgetGB: Double, forceSwap: Bool) async throws -> RuntimeConfig

    /// Streams response text deltas for the given chat history.
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
