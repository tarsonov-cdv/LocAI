import Foundation

/// TODO: not yet ported. The Python original (llm_backends.LlamaCppBackend)
/// wraps llama-cpp-python; on Swift the equivalent is linking against
/// llama.cpp's C API directly (either via the official `llama.cpp` SPM
/// package, or a hand-rolled bridging header + XCFramework build of
/// libllama). That's a self-contained follow-up:
///   1. Add the llama.cpp Swift package (or vendor libllama.xcframework).
///   2. Bridge llama_model_load / llama_new_context / llama_decode.
///   3. Port suggest_runtime_config's n_ctx/n_gpu_layers/n_batch mapping
///      (already available in Swift as RuntimeConfigCalculator).
/// Until then this backend loads the Models tab UI (so GGUF downloads
/// still work) but throws on load/chat, matching the Python app's
/// behavior when llama-cpp-python isn't installed.
final class LlamaCppChatBackend: ChatBackend {
    func load(path: URL, budgetGB: Double, forceSwap: Bool) async throws -> RuntimeConfig {
        throw NSError(domain: "LlamaCppChatBackend", code: 501, userInfo: [
            NSLocalizedDescriptionKey: "The llama.cpp (GGUF) backend isn't ported to Swift yet - use MLX for now."
        ])
    }

    func streamChat(messages: [ChatMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: NSError(domain: "LlamaCppChatBackend", code: 501, userInfo: [
                NSLocalizedDescriptionKey: "The llama.cpp (GGUF) backend isn't ported to Swift yet - use MLX for now."
            ]))
        }
    }

    func unload() {}
}
