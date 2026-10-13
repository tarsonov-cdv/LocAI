import Foundation

/// Mirrors the role/content dict shape the Python backend used
/// (`{"role": ..., "content": ...}`) so prompt-building logic stays familiar.
enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

/// `toolResult` messages carry terminal output back to the model. They are
/// sent to the model with the `user` role (the only role every chat template
/// supports besides `assistant`) but shown differently in the UI.
enum ChatMessageKind: String, Codable, Equatable {
    case normal
    case toolResult
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: ChatRole
    var content: String
    var isStreaming: Bool = false
    var kind: ChatMessageKind = .normal

    init(id: UUID = UUID(), role: ChatRole, content: String, isStreaming: Bool = false, kind: ChatMessageKind = .normal) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.kind = kind
    }

    /// The dict shape passed to the model's chat template / prompt builder.
    var apiPayload: [String: String] {
        ["role": role.rawValue, "content": content]
    }
}
