import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settingsEnv
    @Environment(ModelManager.self) private var modelManager
    @Environment(AppState.self) private var appState
    @FocusState private var systemPromptFocused: Bool

    var body: some View {
        @Bindable var settings = settingsEnv
        let lang = settings.languageCode

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassHeader(title: Loc.t("tab_settings", lang: lang), subtitle: nil)

                GlassCard(title: Loc.t("max_memory", lang: lang)) {
                    HStack {
                        Slider(value: $settings.budgetGB, in: memoryBudgetRange, step: 0.5)
                        Text(String(format: "%.1f GB", settings.budgetGB)).monospacedDigit().frame(width: 70)
                    }
                    Toggle(Loc.t("force_swap", lang: lang), isOn: $settings.forceSwap)
                    Toggle(Loc.t("continue_response", lang: lang), isOn: $settings.continueResponse)
                }

                GlassCard(title: Loc.t("system_prompt_frame", lang: lang)) {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .staticBlurPanel(cornerRadius: 12)
                        .focused($systemPromptFocused)

                    GlassActionButton(
                        title: Loc.t("hide_keyboard", lang: lang),
                        systemImage: "keyboard.chevron.compact.down"
                    ) {
                        systemPromptFocused = false
                    }
                }

                terminalCard(lang: lang)

                GlassCard(title: Loc.t("semantic_memory", lang: lang)) {
                    Toggle(Loc.t("semantic_memory_enabled", lang: lang), isOn: $settings.semanticMemoryEnabled)
                    Text(String(format: Loc.t("semantic_memory_count", lang: lang), appState.semanticMemoryCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GlassActionButton(
                        title: Loc.t("clear_semantic_memory", lang: lang),
                        systemImage: "trash",
                        isDisabled: appState.semanticMemoryCount == 0
                    ) {
                        appState.clearSemanticMemory()
                    }
                }

                GlassCard(title: Loc.t("select_language", lang: lang)) {
                    Picker(Loc.t("select_language", lang: lang), selection: $settings.languageCode) {
                        ForEach(Loc.languages, id: \.code) { entry in
                            Text(entry.name).tag(entry.code)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GlassCard(title: Loc.t("models_folder", lang: lang)) {
                    Text(settings.modelsBaseDir.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(String(format: Loc.t("free_disk", lang: lang), modelManager.freeDiskGB(at: settings.modelsBaseDir)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    GlassActionButton(title: "Choose…", systemImage: "folder", action: chooseFolder)
                    #endif
                }
            }
            .padding(16)
        }
    }

    /// Terminal access for the models. macOS only: iOS apps cannot spawn processes.
    @ViewBuilder
    private func terminalCard(lang: String) -> some View {
        @Bindable var settings = settingsEnv
        GlassCard(title: Loc.t("terminal_access", lang: lang), tint: settings.terminalEnabled ? .orange : nil) {
            #if os(macOS)
            Toggle(Loc.t("terminal_enable", lang: lang), isOn: $settings.terminalEnabled)
            if settings.terminalEnabled {
                Toggle(Loc.t("terminal_auto_approve", lang: lang), isOn: $settings.terminalAutoApprove)
                if settings.terminalAutoApprove {
                    Text(Loc.t("terminal_auto_warning", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent(Loc.t("terminal_workdir", lang: lang)) {
                    TextField("~", text: $settings.terminalWorkingDirectory)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
                Stepper(
                    String(format: Loc.t("terminal_timeout", lang: lang), settings.terminalTimeoutSeconds),
                    value: $settings.terminalTimeoutSeconds, in: 5...300, step: 5
                )
                Stepper(
                    String(format: Loc.t("terminal_max_steps", lang: lang), settings.terminalMaxSteps),
                    value: $settings.terminalMaxSteps, in: 1...15
                )
                if TerminalService.isSandboxed {
                    Text(Loc.t("terminal_sandbox_note", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            #else
            Text(Loc.t("terminal_ios_note", lang: lang))
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    private var memoryBudgetRange: ClosedRange<Double> {
        #if os(iOS)
        2...8
        #else
        2...16
        #endif
    }

    #if os(macOS)
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let old = settingsEnv.modelsBaseDir
            try? modelManager.moveModels(from: old, to: url)
            settingsEnv.modelsBaseDir = url
            modelManager.refresh(base: url)
        }
    }
    #endif
}

#if os(macOS)
import AppKit
#endif
