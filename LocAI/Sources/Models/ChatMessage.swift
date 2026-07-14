import Foundation

/// Mirrors the role/content dict shape the Python backend used
/// (`{"role": ..., "content": ...}`) so prompt-building logic stays familiar.
enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var role: ChatRole
    var content: String
    var isStreaming: Bool = false

    init(id: UUID = UUID(), role: ChatRole, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }

    /// The dict shape passed to the model's chat template / prompt builder.
    var apiPayload: [String: String] {
        ["role": role.rawValue, "content": content]
    }
}
