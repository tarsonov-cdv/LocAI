import SwiftUI
import UniformTypeIdentifiers

struct TuningView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @State private var trainer = LoRATrainingManager()
    @State private var datasetPath = ""
    @State private var outputDir = ""
    @State private var selectedModelPath = ""
    @State private var loraLayers = "4"
    @State private var batchSize = "1"
    @State private var iterations = "100"
    @State private var learningRate = "1e-5"
    @State private var showingDatasetPicker = false
    @State private var showingOutputPicker = false
    // The URLs returned by the pickers carry the security scope; a URL rebuilt
    // from the displayed path would not, so keep them next to the text.
    @State private var pickedDatasetURL: URL?
    @State private var pickedOutputURL: URL?

    private var mlxModels: [LocalModel] { modelManager.localModels.filter { $0.backend == .mlx } }
    private var selectedModel: LocalModel? { mlxModels.first { $0.path.path == selectedModelPath } }

    var body: some View {
        let lang = settings.languageCode

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassHeader(title: Loc.t("tuning_header", lang: lang), subtitle: Loc.t("tuning_note", lang: lang))

                GlassCard(title: Loc.t("tuning_setup", lang: lang)) {
                    LabeledContent(Loc.t("tuning_dataset", lang: lang)) {
                        HStack {
                            TextField("…/dataset.json", text: $datasetPath).textFieldStyle(.plain)
                            Button(Loc.t("open_file", lang: lang)) { showingDatasetPicker = true }
                        }
                    }
                    LabeledContent(Loc.t("tuning_model", lang: lang)) {
                        Picker("", selection: $selectedModelPath) {
                            Text(Loc.t("tuning_no_model", lang: lang)).tag("")
                            ForEach(mlxModels) { model in
                                Text(model.displayName).tag(model.path.path)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(mlxModels.isEmpty)
                    }
                    if let modeText = trainingModeText(lang: lang) {
                        Text(modeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(Loc.t("tuning_output", lang: lang)) {
                        HStack {
                            TextField("…/LocAI-adapter", text: $outputDir).textFieldStyle(.plain)
                            Button(Loc.t("open_file", lang: lang)) { showingOutputPicker = true }
                        }
                    }
                }

                GlassCard(title: Loc.t("tuning_parameters", lang: lang)) {
                    LabeledContent(Loc.t("tuning_lora_layers", lang: lang)) {
                        TextField("4", text: $loraLayers).multilineTextAlignment(.trailing).textFieldStyle(.plain)
                    }
                    LabeledContent(Loc.t("tuning_batch_size", lang: lang)) {
                        TextField("1", text: $batchSize).multilineTextAlignment(.trailing).textFieldStyle(.plain)
                    }
                    LabeledContent(Loc.t("tuning_iterations", lang: lang)) {
                        TextField("100", text: $iterations).multilineTextAlignment(.trailing).textFieldStyle(.plain)
                    }
                    LabeledContent(Loc.t("tuning_lr", lang: lang)) {
                        TextField("1e-5", text: $learningRate).multilineTextAlignment(.trailing).textFieldStyle(.plain)
                    }
                    Text(Loc.t("tuning_data_hint", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Loc.t("tuning_unload_note", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GlassCard {
                    HStack {
                        GlassActionButton(
                            title: trainer.isTraining ? Loc.t("tuning_running", lang: lang) : Loc.t("tuning_start", lang: lang),
                            systemImage: "wand.and.stars",
                            prominent: true,
                            isDisabled: trainer.isTraining,
                            action: startTraining
                        )
                        if trainer.isTraining {
                            GlassActionButton(
                                title: Loc.t("tuning_stop", lang: lang),
                                systemImage: "stop.fill",
                                action: { trainer.stop() }
                            )
                        }
                    }
                    if trainer.isTraining {
                        ProgressView(value: Double(trainer.completedIterations), total: Double(max(trainer.totalIterations, 1)))
                        Text(trainingProgressText(lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !trainer.lastLogLine.isEmpty {
                        Text(trainer.lastLogLine)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if !trainer.status.isEmpty {
                        Text(trainer.status).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = trainer.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if !trainer.isTraining, let adapter = trainer.lastAdapter {
                        GlassActionButton(
                            title: Loc.t("tuning_use_in_chat", lang: lang),
                            systemImage: "bubble.left.and.bubble.right.fill",
                            prominent: true,
                            action: { useInChat(adapter) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            modelManager.refresh(base: settings.modelsBaseDir)
            selectDefaultModelIfNeeded()
        }
        .onChange(of: modelManager.localModels) { selectDefaultModelIfNeeded() }
        .fileImporter(isPresented: $showingDatasetPicker, allowedContentTypes: datasetTypes, allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pickedDatasetURL = url
                datasetPath = url.path
            }
        }
        .fileImporter(isPresented: $showingOutputPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pickedOutputURL = url
                outputDir = url.path
            }
        }
    }

    private func selectDefaultModelIfNeeded() {
        if selectedModel == nil, let first = mlxModels.first {
            selectedModelPath = first.path.path
        }
    }

    private func startTraining() {
        let lang = settings.languageCode
        guard let layers = Int(loraLayers.trimmingCharacters(in: .whitespaces)),
              let batch = Int(batchSize.trimmingCharacters(in: .whitespaces)),
              let steps = Int(iterations.trimmingCharacters(in: .whitespaces)),
              let rate = Float(learningRate.trimmingCharacters(in: .whitespaces)) else {
            trainer.errorMessage = Loc.t("tuning_numbers", lang: lang)
            return
        }
        guard let model = selectedModel else {
            trainer.errorMessage = Loc.t("tuning_pick_model", lang: lang)
            return
        }
        let trimmedDataset = datasetPath.trimmingCharacters(in: .whitespaces)
        guard !trimmedDataset.isEmpty else {
            trainer.errorMessage = Loc.t("tuning_pick_dataset", lang: lang)
            return
        }
        let trimmedOutput = outputDir.trimmingCharacters(in: .whitespaces)

        let base = settings.modelsBaseDir
        let configuration = LoRATrainingConfiguration(
            datasetURL: resolvedURL(path: trimmedDataset, picked: pickedDatasetURL),
            modelDirectory: model.path,
            adapterDirectory: modelManager.newAdapterDirectory(base: base, modelName: model.path.lastPathComponent),
            exportDirectory: trimmedOutput.isEmpty ? nil : resolvedURL(path: trimmedOutput, picked: pickedOutputURL),
            loraLayers: layers,
            batchSize: batch,
            iterations: steps,
            learningRate: rate
        )

        // Training needs the memory the chat model is holding (an 8 GB Mac
        // cannot keep both a chat copy and a training copy of the model).
        if appState.backend != nil { appState.unloadActiveModel() }

        Task {
            await trainer.train(configuration: configuration)
            modelManager.refresh(base: base)
        }
    }

    /// Makes the finished adapter the active one and reloads its base model with it.
    private func useInChat(_ adapter: LoRAAdapter) {
        settings.activeAdapterID = adapter.id
        modelManager.refresh(base: settings.modelsBaseDir)
        guard let model = mlxModels.first(where: { adapter.isCompatible(with: $0.path) }) else { return }
        Task { await appState.loadModel(model, settings: settings) }
    }

    /// Prefers the picker's (security-scoped) URL when the text still shows its path.
    private func resolvedURL(path: String, picked: URL?) -> URL {
        let typed = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        if let picked, picked.standardizedFileURL.path == typed.path { return picked }
        return typed
    }

    private func trainingModeText(lang: String) -> String? {
        guard let model = selectedModel else { return nil }
        if let bits = ModelQuantization.bits(in: model.path) {
            return Loc.t("tuning_mode_qlora", lang: lang, bits)
        }
        return Loc.t("tuning_mode_lora", lang: lang, Double(model.sizeBytes) / 1_073_741_824.0)
    }

    private var datasetTypes: [UTType] {
        [.json, UTType(filenameExtension: "jsonl") ?? .json, .plainText]
    }

    private func trainingProgressText(lang: String) -> String {
        let progress = String(format: Loc.t("tuning_progress", lang: lang), trainer.completedIterations, trainer.totalIterations)
        guard let seconds = trainer.estimatedSecondsRemaining else { return progress }
        return "\(progress) · \(Loc.t("tuning_etc", lang: lang)) \(durationText(seconds))"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let remaining = max(0, Int(seconds.rounded()))
        let minutes = remaining / 60
        return minutes > 0 ? "\(minutes)m \(remaining % 60)s" : "\(remaining)s"
    }
}
