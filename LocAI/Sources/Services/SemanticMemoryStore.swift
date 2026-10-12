import Foundation

/// A small, private retrieval store for facts established in previous chats.
///
/// Entries never leave the device. The vectorizer intentionally has no model
/// dependency: it uses multilingual word and character features, so memory is
/// available even before an MLX model is loaded and works for every UI language.
@MainActor
final class SemanticMemoryStore {
    private static let maximumEntries = 200
    private let fileURL: URL
    private(set) var entries: [SemanticMemoryEntry]

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("LocAI", isDirectory: true)
        fileURL = directory.appendingPathComponent("semantic-memory.json")

        guard let data = try? Data(contentsOf: fileURL),
              let savedEntries = try? JSONDecoder().decode([SemanticMemoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = savedEntries
    }

    /// Stores a completed exchange. Streaming/error placeholders are excluded
    /// by the caller, and each field is capped to keep retrieval lightweight.
    func remember(question: String, answer: String) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !trimmedAnswer.isEmpty else { return }

        entries.append(SemanticMemoryEntry(
            question: String(trimmedQuestion.prefix(700)),
            answer: String(trimmedAnswer.prefix(1_400))
        ))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        persist()
    }

    /// Returns the most relevant past exchanges, not the whole chat archive.
    func relevantEntries(for query: String, limit: Int = 3) -> [SemanticMemoryEntry] {
        let queryVector = SemanticMemoryVectorizer.vector(for: query)
        guard !queryVector.isEmpty else { return [] }

        return entries
            .map { entry in
                (entry, SemanticMemoryVectorizer.similarity(queryVector, SemanticMemoryVectorizer.vector(for: entry.searchableText)))
            }
            .filter { $0.1 >= 0.12 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Memory is an enhancement; a storage failure must never interrupt chat.
        }
    }
}

struct SemanticMemoryEntry: Codable, Identifiable {
    let id: UUID
    let question: String
    let answer: String
    let createdAt: Date

    init(id: UUID = UUID(), question: String, answer: String, createdAt: Date = .now) {
        self.id = id
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
    }

    var searchableText: String { "\(question) \(answer)" }
}

private enum SemanticMemoryVectorizer {
    /// A sparse multilingual vector. Word features capture concepts; character
    /// trigrams keep matches useful across inflected forms and short phrases.
    static func vector(for text: String) -> [String: Double] {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        var features: [String: Double] = [:]

        for word in words {
            features["w:\(word)", default: 0] += 1.0
            let padded = "^\(word)$"
            let characters = Array(padded)
            guard characters.count >= 3 else { continue }
            for index in 0...(characters.count - 3) {
                features["c:\(String(characters[index..<(index + 3)]))", default: 0] += 0.35
            }
        }

        let magnitude = sqrt(features.values.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return [:] }
        return features.mapValues { $0 / magnitude }
    }

    static func similarity(_ left: [String: Double], _ right: [String: Double]) -> Double {
        let smaller = left.count < right.count ? left : right
        let larger = left.count < right.count ? right : left
        return smaller.reduce(0) { partial, feature in
            partial + feature.value * (larger[feature.key] ?? 0)
        }
    }
}
