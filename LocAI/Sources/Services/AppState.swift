import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var backend: ChatBackend?
    var loadedModelPath: URL?
    var loadedModelLabel: String = ""
    var loadedBackendKind: Backend?
    var contextLength: Int?

    var messages: [ChatMessage] = []
    var isGenerating = false
    var statusText: String = ""

    var isLoadingModel = false
    var loadError: String?

    /// Estimated tokens currently committed to the conversation (system
    /// prompt + full history), for the "X / context limit" indicator.
    var totalTokenCount: Int = 0

    func loadModel(_ model: LocalModel, settings: AppSettings) async {
        isLoadingModel = true
        loadError = nil
        let newBackend = ChatBackendFactory.make(model.backend)
        do {
            let cfg = try await newBackend.load(path: model.path, budgetGB: settings.budgetGB, forceSwap: settings.forceSwap)
            backend?.unload()
            backend = newBackend
            loadedModelPath = model.path
            loadedBackendKind = model.backend
            contextLength = cfg.contextLength
            let swapNote = cfg.forceSwap ? " (forced swap)" : ""
            loadedModelLabel = "\(model.displayName) [\(model.backend.rawValue)]\(swapNote)"
            messages.removeAll()
            recomputeTokenCount(settings: settings)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingModel = false
    }

    /// Unloads the active model without deleting anything on disk - used
    /// when the user deletes the model file/folder that's currently
    /// loaded, so the UI doesn't keep pointing at a backend whose weights
    /// no longer exist.
    func unloadIfCurrent(path: URL) {
        guard loadedModelPath == path else { return }
        backend?.unload()
        backend = nil
        loadedModelPath = nil
        loadedBackendKind = nil
        contextLength = nil
        loadedModelLabel = ""
    }

    func send(text: String, settings: AppSettings) {
        guard let backend else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        recomputeTokenCount(settings: settings)
        let maxTokens = settings.maxResponseTokens

        var payload: [ChatMessage] = []
        if !settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.append(ChatMessage(role: .system, content: settings.systemPrompt))
        }
        payload.append(contentsOf: messages.suffix(settings.maxPromptMessages))

        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", isStreaming: true))
        isGenerating = true

        Task {
            var full = ""
            do {
                for try await delta in backend.streamChat(messages: payload, maxTokens: maxTokens) {
                    full += delta
                    updateAssistantMessage(id: assistantID, content: full, streaming: true)
                }
                updateAssistantMessage(id: assistantID, content: full, streaming: false)
                statusText = Loc.t("generation_complete", lang: settings.languageCode)
            } catch {
                updateAssistantMessage(id: assistantID, content: "⚠️ \(error.localizedDescription)", streaming: false)
            }
            isGenerating = false
            recomputeTokenCount(settings: settings)
        }
    }

    private func updateAssistantMessage(id: UUID, content: String, streaming: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
        messages[idx].isStreaming = streaming
    }

    func clearChat(settings: AppSettings) {
        messages.removeAll()
        recomputeTokenCount(settings: settings)
    }

    func recomputeTokenCount(settings: AppSettings) {
        totalTokenCount = TokenEstimator.count(settings.systemPrompt) + TokenEstimator.count(messages)
    }
}
