import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    // Memory / runtime
    var budgetGB: Double = 6.0
    var forceSwap: Bool = false
    var continueResponse: Bool = false   // allow up to 4k tokens instead of 512

    // Backend selection
    var backend: Backend = .mlx

    // Prompting
    var systemPrompt: String = "You are a helpful local assistant. Always answer clearly and politely."
    var censorEnabled: Bool = false
    var censorWords: String = "restricted, blocked, censored"

    // Locale - keeps the four languages the Python app shipped with
    var languageCode: String = Locale.current.language.languageCode?.identifier == "ru" ? "ru" : "en"

    // Storage
    var modelsBaseDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocAI/models", isDirectory: true)
    }()

    func applyCensoring(to text: String) -> String {
        guard censorEnabled else { return text }
        let words = censorWords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = text
        for word in words where !word.isEmpty {
            let replacement = String(repeating: "*", count: word.count)
            result = result.replacingOccurrences(of: word, with: replacement, options: .caseInsensitive)
        }
        return result
    }
}
