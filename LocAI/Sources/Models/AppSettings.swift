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
    var semanticMemoryEnabled: Bool = true

    // Backend selection
    var backend: Backend = .mlx

    // Prompting
    var systemPrompt: String = "You are a helpful local assistant. Always answer clearly and politely."
    var censorEnabled: Bool = false
    var censorWords: String = "restricted, blocked, censored"

    // Locale - keeps the four languages the Python app shipped with
    var languageCode: String = Locale.current.language.languageCode?.identifier == "ru" ? "ru" : "en"

    // Terminal access (macOS only). Deliberately NOT persisted anywhere: it is
    // off again on every launch, and every command asks for confirmation
    // unless auto-approve is switched on.
    var terminalEnabled: Bool = false
    var terminalAutoApprove: Bool = false
    var terminalTimeoutSeconds: Int = 30
    var terminalMaxSteps: Int = 5
    var terminalWorkingDirectory: String = NSHomeDirectory()

    /// Terminal tool is switched on *and* this platform can run commands.
    var terminalActive: Bool { TerminalService.isSupported && terminalEnabled }

    var terminalWorkingDirectoryURL: URL {
        let expanded = (terminalWorkingDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // LoRA / QLoRA adapter that is applied the next time a model is loaded
    // (LoRAAdapter.id, i.e. the adapter folder path).
    var activeAdapterID: String?

    // Storage
    var modelsBaseDir: URL = AppSettings.defaultModelsBaseDir()

    /// `~/Library/Application Support/LocAI/models`. When the app runs without
    /// the App Sandbox (needed for terminal access) but models were already
    /// downloaded by a sandboxed build, keep using that folder instead of
    /// silently "losing" them.
    private static func defaultModelsBaseDir() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let standard = appSupport.appendingPathComponent("LocAI/models", isDirectory: true)
        #if os(macOS)
        if !TerminalService.isSandboxed, let bundleID = Bundle.main.bundleIdentifier {
            let legacy = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/LocAI/models", isDirectory: true)
            if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: standard.path) {
                return legacy
            }
        }
        #endif
        return standard
    }

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
