import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    // Memory / runtime
    #if os(iOS)
    var budgetGB: Double = 3.0
    #else
    var budgetGB: Double = 6.0
    #endif
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

    var maxResponseTokens: Int {
        #if os(iOS)
        continueResponse ? 2048 : 384
        #else
        continueResponse ? 4096 : 512
        #endif
    }

    var maxPromptMessages: Int {
        #if os(iOS)
        8
        #else
        24
        #endif
    }

    }

