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
@MainActor
@Observable
final class LoRATrainingManager {
    var isTraining = false
    var status = ""
    var errorMessage: String?
    var completedIterations = 0
    var totalIterations = 0
    var estimatedSecondsRemaining: TimeInterval?
    private var currentStage = "preparing training"

    func train(configuration: LoRATrainingConfiguration) async {
        guard !isTraining else { return }
        isTraining = true
        errorMessage = nil
        currentStage = "preparing training data"
        status = "Preparing training data…"
        completedIterations = 0
        totalIterations = configuration.iterations
        estimatedSecondsRemaining = nil
        defer { isTraining = false }

        do {
            let accessibleResources = [
                configuration.datasetURL,
                configuration.modelDirectory,
                configuration.adapterURL.deletingLastPathComponent(),
            ].map { url in (url, url.startAccessingSecurityScopedResource()) }
            defer {
                for (url, didAccess) in accessibleResources where didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try configuration.validate()
            #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXOptimizers) && canImport(Tokenizers)
            let examples = try TrainingDatasetLoader.load(url: configuration.datasetURL)
            guard examples.count >= 2 else { throw LoRATrainingError.tooFewExamples }
            let validationCount = max(1, examples.count / 10)
            let trainSet = Array(examples.dropLast(validationCount))
            let validationSet = Array(examples.suffix(validationCount))

            currentStage = "creating the adapter output folder"
            try FileManager.default.createDirectory(at: configuration.adapterURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            currentStage = "loading the base model"
            status = "Loading model and LoRA adapters…"
            let modelConfiguration = ModelConfiguration(directory: configuration.modelDirectory)
            let container = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration)

            currentStage = "adding LoRA layers and training"
            try await container.perform { [configuration] context in
                guard let loraModel = context.model as? LoRAModel else {
                    throw LoRATrainingError.unsupportedModel
                }
                LoRATrain.convert(model: context.model, layers: loraModel.loraLinearLayers(configuration.loraLayers))

                var parameters = LoRATrain.Parameters()
                parameters.batchSize = configuration.batchSize
                parameters.iterations = configuration.iterations
                parameters.stepsPerReport = min(10, configuration.iterations)
                parameters.stepsPerEval = min(100, configuration.iterations)
                parameters.validationBatches = min(10, validationSet.count)
                parameters.saveEvery = min(100, configuration.iterations)
                parameters.adapterURL = configuration.adapterURL

                let optimizer = Adam(learningRate: configuration.learningRate)
                try LoRATrain.train(model: context.model, train: trainSet, validate: validationSet, optimizer: optimizer, tokenizer: context.tokenizer, parameters: parameters) { [weak self] progress in
                    if case let .train(iteration, _, iterationsPerSecond, _) = progress {
                        Task { @MainActor [weak self] in
                            self?.updateProgress(
                                completed: iteration + 1,
                                total: configuration.iterations,
                                iterationsPerSecond: iterationsPerSecond
                            )
                        }
                    }
                    return .more
                }
                try LoRATrain.saveLoRAWeights(model: context.model, url: configuration.adapterURL)
            }
            completedIterations = configuration.iterations
            estimatedSecondsRemaining = 0
            status = "Adapter saved to \(configuration.adapterURL.lastPathComponent)"
            #else
            throw LoRATrainingError.missingMLX
            #endif
        } catch {
            errorMessage = detailedErrorMessage(for: error)
            status = ""
        }
    }

    private func updateProgress(completed: Int, total: Int, iterationsPerSecond: Double) {
        guard isTraining else { return }
        completedIterations = min(completed, total)
        guard iterationsPerSecond > 0 else { return }
        estimatedSecondsRemaining = Double(total - completedIterations) / iterationsPerSecond
    }

    private func detailedErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let technicalDetail = nsError.localizedDescription
        if nsError.domain.lowercased().contains("mlx"), nsError.code == 0 {
            return "MLX failed while \(currentStage), but did not provide a detailed reason. Check that the selected MLX model supports LoRA and that enough unified memory is available; try a smaller model or batch size 1."
        }
        return "Failed while \(currentStage): \(technicalDetail)"
    }
}

struct LoRATrainingConfiguration: Sendable {
    let datasetURL: URL
    let modelDirectory: URL
    let adapterURL: URL
    let loraLayers: Int
    let batchSize: Int
    let iterations: Int
    let learningRate: Float

    func validate() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: datasetURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else { throw LoRATrainingError.invalidDatasetFile }
        guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw LoRATrainingError.invalidDirectory("Model") }
        guard loraLayers > 0, batchSize > 0, iterations > 0, learningRate > 0 else { throw LoRATrainingError.invalidConfiguration }
    }
}

enum LoRATrainingError: LocalizedError {
    case invalidDirectory(String)
    case invalidDatasetFile
    case tooFewExamples
    case invalidConfiguration
    case unsupportedModel
    case missingMLX

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let name): "\(name) folder was not found."
        case .invalidDatasetFile: "Choose a JSON, JSONL, or TXT dataset file."
        case .tooFewExamples: "The dataset needs at least two training examples."
        case .invalidConfiguration: "LoRA layers, batch size, iterations, and learning rate must be greater than zero."
        case .unsupportedModel: "This MLX model architecture does not support LoRA training."
        case .missingMLX: "MLX training libraries are not linked to this target."
        }
    }
}

private enum TrainingDatasetLoader {
    static func load(url: URL) throws -> [String] {
        switch url.pathExtension.lowercased() {
        case "json":
            return examples(from: try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        case "jsonl":
            var parsedExamples: [String] = []
            for line in try String(contentsOf: url).split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                parsedExamples.append(contentsOf: examples(from: object))
            }
            return parsedExamples
        case "txt":
            return try String(contentsOf: url).split(whereSeparator: \.isNewline).map(String.init)
        default:
            throw LoRATrainingError.invalidDatasetFile
        }
    }

    private static func examples(from object: Any) -> [String] {
        if let strings = object as? [String] { return strings.filter { !$0.isEmpty } }
        if let dictionary = object as? [String: Any] {
            if let items = dictionary["data"] ?? dictionary["examples"] { return examples(from: items) }
            if let text = dictionary["text"] as? String { return [text] }
            if let prompt = dictionary["prompt"] as? String, let completion = dictionary["completion"] as? String { return ["\(prompt)\n\(completion)"] }
            if let messages = dictionary["messages"] as? [[String: Any]] {
                let text = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
                return text.isEmpty ? [] : [text]
            }
        }
        if let items = object as? [Any] { return items.flatMap(examples(from:)) }
        return []
    }
}
