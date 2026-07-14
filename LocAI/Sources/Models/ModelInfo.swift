import Foundation

enum Backend: String, CaseIterable, Identifiable, Codable, Hashable {
    case mlx = "MLX"
    case llamaCpp = "llama.cpp (GGUF)"

    var id: String { rawValue }
}

/// A single quantized GGUF file inside an HF repo. Ported 1:1 from
/// model_manager.GGUFFile.
struct GGUFFile: Identifiable, Hashable {
    var id: String { "\(repoID)/\(filename)" }
    let repoID: String
    let filename: String
    let sizeBytes: Int64

    var sizeGB: Double { Double(sizeBytes) / 1_073_741_824.0 }
}

/// A whole-folder MLX repo (config.json + tokenizer + safetensors).
struct MLXRepo: Identifiable, Hashable {
    var id: String { repoID }
    let repoID: String
    var totalSizeBytes: Int64?

    var sizeGB: Double? { totalSizeBytes.map { Double($0) / 1_073_741_824.0 } }
}

/// A model that has already been downloaded locally, either a single
/// .gguf file or an MLX model folder.
struct LocalModel: Identifiable, Hashable {
    var id: String { path.path }
    let path: URL
    let backend: Backend
    let displayName: String
    let sizeBytes: Int64
}

/// Mirrors model_manager.RuntimeConfig - the knobs each backend derives
/// from the user's memory budget.
struct RuntimeConfig {
    var contextLength: Int
    var gpuLayers: Int   // llama.cpp only; -1 == "all layers"
    var batchSize: Int
    var forceSwap: Bool = false
}

/// Ported from model_manager.suggest_runtime_config - same thresholds,
/// same reasoning (see comments in the original Python file for the
/// llama.cpp / MLX memory-pinning rationale).
enum RuntimeConfigCalculator {
    static func suggest(budgetGB: Double, forceSwap: Bool) -> RuntimeConfig {
        if forceSwap {
            return RuntimeConfig(contextLength: 2048, gpuLayers: 0, batchSize: 128, forceSwap: true)
        }
        switch budgetGB {
        case ...4:
            return RuntimeConfig(contextLength: 2048, gpuLayers: 16, batchSize: 256)
        case ...6:
            return RuntimeConfig(contextLength: 4096, gpuLayers: 24, batchSize: 384)
        case ...8:
            return RuntimeConfig(contextLength: 4096, gpuLayers: -1, batchSize: 512)
        default:
            return RuntimeConfig(contextLength: 8192, gpuLayers: -1, batchSize: 512)
        }
    }

    static func estimatedRAMNeededGB(modelFileSizeBytes: Int64, contextLength: Int) -> Double {
        let weightsGB = Double(modelFileSizeBytes) / 1_073_741_824.0
        let kvCacheGB = (Double(contextLength) / 4096.0) * 0.5
        let overheadGB = 0.5
        return weightsGB + kvCacheGB + overheadGB
    }

    static func fitsBudget(modelFileSizeBytes: Int64, budgetGB: Double, forceSwap: Bool) -> Bool {
        if forceSwap { return true }
        let cfg = suggest(budgetGB: budgetGB, forceSwap: false)
        return estimatedRAMNeededGB(modelFileSizeBytes: modelFileSizeBytes, contextLength: cfg.contextLength) <= budgetGB
    }
}

/// Curated quick-pick repos, same list as model_manager.py, chosen to be
/// comfortable on an 8GB Mac.
enum CuratedModels {
    static let gguf = [
        "bartowski/Llama-3.2-3B-Instruct-GGUF",
        "bartowski/Qwen2.5-3B-Instruct-GGUF",
        "bartowski/Phi-3.5-mini-instruct-GGUF",
        "bartowski/gemma-2-2b-it-GGUF",
        "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
    ]
    static let mlx = [
        "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Phi-3.5-mini-instruct-4bit",
        "mlx-community/gemma-2-2b-it-4bit",
        "mlx-community/Qwen2.5-7B-Instruct-4bit",
    ]
}
