import SwiftUI
import UniformTypeIdentifiers

struct TuningView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModelManager.self) private var modelManager
    @State private var trainer = LoRATrainingManager()
    @State private var datasetPath = ""
    @State private var outputDir = ""
    @State private var selectedModelPath = ""
    @State private var loraLayers = "4"
    @State private var batchSize = "1"
    @State private var iterations = "100"
    @State private var showingDatasetPicker = false
    @State private var showingOutputPicker = false

    var body: some View {
        let lang = settings.languageCode
        let mlxModels = modelManager.localModels.filter { $0.backend == .mlx }

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
                    LabeledContent(Loc.t("tuning_output", lang: lang)) {
                        HStack {
                            TextField("…/LocAI-adapter", text: $outputDir).textFieldStyle(.plain)
                            Button(Loc.t("open_file", lang: lang)) { showingOutputPicker = true }
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
                    Text(Loc.t("tuning_data_hint", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GlassCard {
                    GlassActionButton(
                        title: trainer.isTraining ? Loc.t("tuning_running", lang: lang) : Loc.t("tuning_start", lang: lang),
                        systemImage: "wand.and.stars",
                        prominent: true,
                        isDisabled: trainer.isTraining,
                        action: startTraining
                    )
                    if trainer.isTraining {
                        ProgressView(value: Double(trainer.completedIterations), total: Double(max(trainer.totalIterations, 1)))
                        Text(trainingProgressText(lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !trainer.status.isEmpty {
                        Text(trainer.status).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = trainer.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
        .onAppear { modelManager.refresh(base: settings.modelsBaseDir) }
        .fileImporter(isPresented: $showingDatasetPicker, allowedContentTypes: datasetTypes, allowsMultipleSelection: false) {
            if let path = selectedPath(from: $0) { datasetPath = path }
        }
        .fileImporter(isPresented: $showingOutputPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) {
            if let path = selectedPath(from: $0) { outputDir = path }
        }
    }

    private func startTraining() {
        guard let layers = Int(loraLayers), let batch = Int(batchSize), let steps = Int(iterations) else {
            trainer.errorMessage = "Training parameters must be whole numbers."
            return
        }

        let configuration = LoRATrainingConfiguration(
            datasetURL: localURL(for: datasetPath),
            modelDirectory: localURL(for: selectedModelPath),
            adapterURL: localURL(for: outputDir).appendingPathComponent("adapter.safetensors"),
            loraLayers: layers,
            batchSize: batch,
            iterations: steps,
            learningRate: 1e-5
        )
        Task { await trainer.train(configuration: configuration) }
    }

    private func localURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private var datasetTypes: [UTType] {
        [.json, UTType(filenameExtension: "jsonl") ?? .json, .plainText]
    }

    private func selectedPath(from result: Result<[URL], Error>) -> String? {
        guard case .success(let urls) = result, let url = urls.first else { return nil }
        return url.path
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
