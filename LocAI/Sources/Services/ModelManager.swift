import Foundation
import Observation

/// Ported from the local-storage side of model_manager.py:
/// list_local_gguf_models, list_local_mlx_models, mlx_folder_size_bytes,
/// delete_local_model, get_free_disk_gb, get/set_models_base_dir.
@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()

    private(set) var localModels: [LocalModel] = []

    private let fm = FileManager.default

    private func gguf(under base: URL) -> URL { base.appendingPathComponent("gguf", isDirectory: true) }
    private func mlx(under base: URL) -> URL { base.appendingPathComponent("mlx", isDirectory: true) }

    func ensureDirectories(base: URL) {
        try? fm.createDirectory(at: gguf(under: base), withIntermediateDirectories: true)
        try? fm.createDirectory(at: mlx(under: base), withIntermediateDirectories: true)
    }

    /// list_local_gguf_models + list_local_mlx_models combined into one
    /// display list, refreshed after downloads/deletes/base-dir changes.
    func refresh(base: URL) {
        ensureDirectories(base: base)
        var results: [LocalModel] = []

        if let repoDirs = try? fm.contentsOfDirectory(at: gguf(under: base), includingPropertiesForKeys: nil) {
            for repoDir in repoDirs where isDirectory(repoDir) {
                if let files = try? fm.contentsOfDirectory(at: repoDir, includingPropertiesForKeys: [.fileSizeKey]) {
                    for file in files where file.pathExtension.lowercased() == "gguf" {
                        let size = fileSize(file)
                        results.append(LocalModel(path: file, backend: .llamaCpp, displayName: file.lastPathComponent, sizeBytes: size))
                    }
                }
            }
        }

        if let repoDirs = try? fm.contentsOfDirectory(at: mlx(under: base), includingPropertiesForKeys: nil) {
            for repoDir in repoDirs where isDirectory(repoDir) {
                guard fm.fileExists(atPath: repoDir.appendingPathComponent("config.json").path) else { continue }
                results.append(LocalModel(
                    path: repoDir, backend: .mlx,
                    displayName: repoDir.lastPathComponent.replacingOccurrences(of: "__", with: "/"),
                    sizeBytes: folderSizeBytes(repoDir)
                ))
            }
        }

        localModels = results.sorted { $0.displayName < $1.displayName }
    }

    /// delete_local_model: safe for either a single .gguf file or an MLX folder.
    func delete(_ model: LocalModel) throws {
        guard fm.fileExists(atPath: model.path.path) else { return }
        try fm.removeItem(at: model.path)
    }

    /// mlx_folder_size_bytes
    func folderSizeBytes(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(file)
        }
        return total
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    /// get_free_disk_gb
    func freeDiskGB(at url: URL) -> Double {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Double(capacity) / 1_073_741_824.0
    }

    /// set_models_base_dir(move_existing=true) equivalent.
    func moveModels(from oldBase: URL, to newBase: URL) throws {
        ensureDirectories(base: newBase)
        for sub in ["gguf", "mlx"] {
            let oldDir = oldBase.appendingPathComponent(sub, isDirectory: true)
            let newDir = newBase.appendingPathComponent(sub, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let dest = newDir.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: item, to: dest)
            }
        }
    }
}
