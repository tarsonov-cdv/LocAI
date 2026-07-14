import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settingsEnv
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        @Bindable var settings = settingsEnv
        let lang = settings.languageCode

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassHeader(title: Loc.t("tab_settings", lang: lang), subtitle: nil)

                GlassCard(title: Loc.t("max_memory", lang: lang)) {
                    HStack {
                        Slider(value: $settings.budgetGB, in: 2...16, step: 0.5)
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
                        .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                GlassCard {
                    Toggle(Loc.t("censor_filter", lang: lang), isOn: $settings.censorEnabled)
                    if settings.censorEnabled {
                        Text(Loc.t("censor_custom_words", lang: lang)).font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $settings.censorWords)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
