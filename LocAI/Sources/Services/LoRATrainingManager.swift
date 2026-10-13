import Foundation
import Observation

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXOptimizers) && canImport(Tokenizers)
import MLX
import MLXLLM
import MLXLMCommon
import MLXOptimizers
#endif

/// Runs MLX Swift's LoRA training loop against a locally downloaded MLX model.
/// Only adapter weights are trained and saved; the source model is never changed.
///
/// QLoRA needs no separate code path: when the base model is quantized
/// (e.g. mlx-community/...-4bit) MLX converts its layers to quantized LoRA
/// layers, so the frozen base stays 4-bit and only the small adapter trains.
@MainActor
@Observable
final class LoRATrainingManager {
    var isTraining = false
    var status = ""
    var errorMessage: String?
    var completedIterations = 0
    var totalIterations = 0
    var estimatedSecondsRemaining: TimeInterval?
    /// Last line reported by the MLX training loop (iteration, loss, speed / validation loss).
    var lastLogLine = ""
    /// Set after a successful run so the UI can offer "use in chat".
    var lastAdapter: LoRAAdapter?
    private var currentStage = "preparing training"
    @ObservationIgnored private var cancelFlag: CancelFlag?

    /// Asks the training loop to stop at the next progress report. The adapter
    /// trained so far is still saved.
    func stop() {
        cancelFlag?.cancel()
        if isTraining { status = "Stopping…" }
    }

    func train(configuration: LoRATrainingConfiguration) async {
        guard !isTraining else { return }
        isTraining = true
        errorMessage = nil
        lastAdapter = nil
        lastLogLine = ""
        currentStage = "preparing training data"
        status = "Preparing training data…"
        completedIterations = 0
        totalIterations = configuration.iterations
        estimatedSecondsRemaining = nil
        let cancelFlag = CancelFlag()
        self.cancelFlag = cancelFlag
        defer {
            isTraining = false
            self.cancelFlag = nil
        }

        do {
            // These must be the URLs handed out by the file pickers: only those
            // carry a security scope (required on iOS and in the macOS sandbox).
            var scopedURLs = [configuration.datasetURL]
            if let export = configuration.exportDirectory { scopedURLs.append(export) }
            let accessed = scopedURLs.map { url in (url, url.startAccessingSecurityScopedResource()) }
            defer {
                for (url, didAccess) in accessed where didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try configuration.validate()

            let examples = try TrainingDatasetLoader.load(url: configuration.datasetURL).shuffled()
            let split = try DatasetSplit(examples: examples, batchSize: configuration.batchSize)
            let quantizationBits = ModelQuantization.bits(in: configuration.modelDirectory)

            #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXOptimizers) && canImport(Tokenizers)
            currentStage = "creating the adapter folder"
            try FileManager.default.createDirectory(at: configuration.adapterDirectory, withIntermediateDirectories: true)

            // Keep MLX's buffer cache small; the chat model has already been
            // unloaded by the UI so the training run gets the memory.
            GPU.set(cacheLimit: 32 * 1024 * 1024)
            defer { GPU.set(cacheLimit: 0) }

            currentStage = "loading the base model"
            status = "Loading model…"
            let modelConfiguration = ModelConfiguration(directory: configuration.modelDirectory)
            let container = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration)

            currentStage = "adding LoRA layers and training"
            status = quantizationBits == nil ? "Training LoRA…" : "Training QLoRA (\(quantizationBits ?? 4)-bit base)…"

            let trainSet = split.train
            let validationSet = split.validation
            let adapterURL = configuration.adapterURL
            let loraLayerCount = configuration.loraLayers
            let batchSize = configuration.batchSize
            let iterations = configuration.iterations
            let learningRate = configuration.learningRate

            let wasStopped = try await container.perform { context -> Bool in
                guard let loraModel = context.model as? LoRAModel else {
                    throw LoRATrainingError.unsupportedModel
                }
                // `loraLinearLayers()` returns the attention layers of *all*
                // transformer blocks; LoRA is applied to the last N of them.
                LoRATrain.convert(model: context.model, layers: Array(loraModel.loraLinearLayers().suffix(loraLayerCount)))

                var parameters = LoRATrain.Parameters()
                parameters.batchSize = batchSize
                parameters.iterations = iterations
                parameters.stepsPerReport = max(1, min(10, iterations))
                parameters.stepsPerEval = max(1, min(100, iterations))
                parameters.validationBatches = max(1, min(10, validationSet.count / batchSize))
                parameters.saveEvery = max(1, min(100, iterations))
                parameters.adapterURL = adapterURL

                let optimizer = Adam(learningRate: learningRate)
                try LoRATrain.train(model: context.model, train: trainSet, validate: validationSet, optimizer: optimizer, tokenizer: context.tokenizer, parameters: parameters) { [weak self] progress in
                    let description = progress.description
                    var iteration: Int?
                    var speed: Double?
                    if case let .train(it, _, iterationsPerSecond, _) = progress {
                        iteration = it + 1
                        speed = iterationsPerSecond
                    }
                    Task { @MainActor [weak self] in
                        self?.updateProgress(description: description, completed: iteration, total: iterations, iterationsPerSecond: speed)
                    }
                    return cancelFlag.isCancelled ? .stop : .more
                }
                try LoRATrain.saveLoRAWeights(model: context.model, url: adapterURL)
                return cancelFlag.isCancelled
            }

            currentStage = "saving the adapter"
            let metadata = LoRAAdapter.Metadata(
                baseModel: configuration.modelDirectory.lastPathComponent,
                loraLayers: loraLayerCount,
                iterations: wasStopped ? completedIterations : iterations,
                quantizationBits: quantizationBits,
                createdAt: Date()
            )
            let adapter = LoRAAdapter(directory: configuration.adapterDirectory, metadata: metadata)
            try adapter.writeMetadata()
            if let export = configuration.exportDirectory {
                currentStage = "exporting a copy of the adapter"
                try adapter.copy(to: export)
            }

            lastAdapter = adapter
            if !wasStopped { completedIterations = iterations }
            estimatedSecondsRemaining = 0
            status = wasStopped
                ? "Stopped at step \(completedIterations). Adapter saved: \(adapter.displayName)"
                : "Adapter saved: \(adapter.displayName)"
            #else
            throw LoRATrainingError.missingMLX
            #endif
        } catch {
            errorMessage = detailedErrorMessage(for: error)
            status = ""
        }
    }

    private func updateProgress(description: String, completed: Int?, total: Int, iterationsPerSecond: Double?) {
        guard isTraining else { return }
        lastLogLine = description
        guard let completed else { return }
        completedIterations = min(completed, total)
        guard let iterationsPerSecond, iterationsPerSecond > 0 else { return }
        estimatedSecondsRemaining = Double(total - completedIterations) / iterationsPerSecond
    }

    private func detailedErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let technicalDetail = nsError.localizedDescription
        if let known = error as? LoRATrainingError {
            return known.errorDescription ?? technicalDetail
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
            return "Failed while \(currentStage): permission denied. Pick the dataset / export folder with the Open… button instead of typing the path, and make sure the target has \"User Selected File: Read/Write\" enabled."
        }
        if nsError.domain.lowercased().contains("mlx"), nsError.code == 0 {
            return "MLX failed while \(currentStage), but did not provide a detailed reason. Usually this means the model does not fit into memory: use a 4-bit model (QLoRA), batch size 1 and fewer LoRA layers, and close other heavy apps."
        }
        return "Failed while \(currentStage): \(technicalDetail)"
    }
}

/// Thread-safe flag shared between the UI and the training loop (which runs
/// on the model container's executor, not on the main actor).
nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

nonisolated struct LoRATrainingConfiguration: Sendable {
    /// Must be the picker's URL when the file came from a picker (see `train`).
    let datasetURL: URL
    let modelDirectory: URL
    /// Always inside the app's own storage; weights are written here.
    let adapterDirectory: URL
    /// Optional extra copy of the finished adapter (picker URL).
    let exportDirectory: URL?
    let loraLayers: Int
    let batchSize: Int
    let iterations: Int
    let learningRate: Float

    var adapterURL: URL { adapterDirectory.appendingPathComponent(LoRAAdapter.weightsFileName) }

    func validate() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: datasetURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else { throw LoRATrainingError.invalidDatasetFile }
        // An empty path would silently resolve to the current directory, which
        // exists - so check for it explicitly.
        guard !modelDirectory.lastPathComponent.isEmpty, modelDirectory.path != "/",
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("config.json").path) else {
            throw LoRATrainingError.invalidDirectory("Model")
        }
        guard loraLayers > 0, batchSize > 0, iterations > 0, learningRate > 0 else { throw LoRATrainingError.invalidConfiguration }
    }
}

/// Splits examples into train / validation parts that both hold at least one
/// full batch. MLX's batch iterator cannot work with fewer examples than the
/// batch size.
nonisolated struct DatasetSplit: Sendable {
    let train: [String]
    let validation: [String]

    init(examples: [String], batchSize: Int) throws {
        guard !examples.isEmpty else { throw LoRATrainingError.noExamples }
        let validationCount = max(batchSize, examples.count / 10)
        let needed = batchSize + validationCount
        guard examples.count >= needed else {
            throw LoRATrainingError.tooFewExamples(found: examples.count, needed: needed, batchSize: batchSize)
        }
        validation = Array(examples.suffix(validationCount))
        train = Array(examples.dropLast(validationCount))
    }
}

nonisolated enum LoRATrainingError: LocalizedError {
    case invalidDirectory(String)
    case invalidDatasetFile
    case noExamples
    case tooFewExamples(found: Int, needed: Int, batchSize: Int)
    case invalidConfiguration
    case unsupportedModel
    case missingMLX

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let name): "\(name) folder was not found or is not an MLX model (no config.json)."
        case .invalidDatasetFile: "Choose a JSON, JSONL, or TXT dataset file."
        case .noExamples: "No training examples were found in the dataset file. Check its format."
        case .tooFewExamples(let found, let needed, let batchSize): "The dataset has \(found) examples, but batch size \(batchSize) needs at least \(needed) (training and validation parts must each fill one batch). Add examples or lower the batch size."
        case .invalidConfiguration: "LoRA layers, batch size, iterations, and learning rate must be greater than zero."
        case .unsupportedModel: "This MLX model architecture does not support LoRA training."
        case .missingMLX: "MLX training libraries are not linked to this target (\(Self.linkDiagnostics))."
        }
    }

    /// Which of the modules the training code needs cannot be imported.
    private static var linkDiagnostics: String {
        var missing: [String] = []
        #if !canImport(MLX)
        missing.append("MLX")
        #endif
        #if !canImport(MLXLLM)
        missing.append("MLXLLM")
        #endif
        #if !canImport(MLXLMCommon)
        missing.append("MLXLMCommon")
        #endif
        #if !canImport(MLXOptimizers)
        missing.append("MLXOptimizers")
        #endif
        #if !canImport(Tokenizers)
        missing.append("Tokenizers")
        #endif
        return missing.isEmpty ? "all modules found" : "missing: " + missing.joined(separator: ", ")
    }
}

nonisolated private enum TrainingDatasetLoader {
    static func load(url: URL) throws -> [String] {
        switch url.pathExtension.lowercased() {
        case "json":
            return examples(from: try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        case "jsonl":
            var parsedExamples: [String] = []
            for line in try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                parsedExamples.append(contentsOf: examples(from: object))
            }
            return parsedExamples
        case "txt":
            // One example per non-empty line.
            return try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        default:
            throw LoRATrainingError.invalidDatasetFile
        }
    }

    private static func examples(from object: Any) -> [String] {
        if let strings = object as? [String] { return strings.filter { !$0.isEmpty } }
        if let dictionary = object as? [String: Any] {
            if let items = dictionary["data"] ?? dictionary["examples"] { return examples(from: items) }
            if let text = dictionary["text"] as? String { return text.isEmpty ? [] : [text] }
            if let prompt = dictionary["prompt"] as? String, let completion = dictionary["completion"] as? String { return ["\(prompt)\n\(completion)"] }
            // Alpaca style: instruction (+ optional input) -> output
            if let instruction = dictionary["instruction"] as? String, let output = dictionary["output"] as? String {
                let input = (dictionary["input"] as? String) ?? ""
                return [[instruction, input, output].filter { !$0.isEmpty }.joined(separator: "\n")]
            }
            if let question = dictionary["question"] as? String, let answer = dictionary["answer"] as? String { return ["\(question)\n\(answer)"] }
            if let input = dictionary["input"] as? String, let output = dictionary["output"] as? String { return ["\(input)\n\(output)"] }
            if let messages = dictionary["messages"] as? [[String: Any]] {
                let text = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
                return text.isEmpty ? [] : [text]
            }
        }
        if let items = object as? [Any] { return items.flatMap(examples(from:)) }
        return []
    }
}
