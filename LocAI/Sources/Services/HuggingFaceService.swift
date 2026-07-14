import Foundation

/// Ported from model_manager.py's HF-related functions (search_gguf_repos,
/// list_gguf_files, search_mlx_repos, get_repo_files, download_gguf_file,
/// download_mlx_repo). Uses HF's plain REST API directly over URLSession -
/// no huggingface_hub dependency needed on this side.
actor HuggingFaceService {
    static let shared = HuggingFaceService()

    private let session: URLSession = .shared
    private let apiBase = "https://huggingface.co/api/models"

    // MARK: - Search

    private struct SearchHit: Decodable { let id: String }

    /// search_gguf_repos: biases the query towards GGUF quantizations.
    func searchGGUFRepos(query: String, limit: Int = 20) async throws -> [String] {
        let q = query.lowercased().contains("gguf") ? query : "\(query) GGUF"
        return try await search(query: q, limit: limit)
    }

    /// search_mlx_repos: biases towards mlx-community, mlx-community repos first.
    func searchMLXRepos(query: String, limit: Int = 20) async throws -> [String] {
        let q = query.lowercased().contains("mlx") ? query : "\(query) mlx"
        let ids = try await search(query: q, limit: limit)
        return ids.sorted { a, b in
            let aFirst = a.hasPrefix("mlx-community/")
            let bFirst = b.hasPrefix("mlx-community/")
            if aFirst == bFirst { return false }
            return aFirst && !bFirst
        }
    }

    private func search(query: String, limit: Int) async throws -> [String] {
        var comps = URLComponents(string: apiBase)!
        comps.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await session.data(from: comps.url!)
        let hits = try JSONDecoder().decode([SearchHit].self, from: data)
        return hits.map(\.id)
    }

    // MARK: - Repo file listings

    private struct RepoInfo: Decodable {
        let siblings: [Sibling]
        struct Sibling: Decodable {
            let rfilename: String
            let size: Int64?
        }
    }

    /// list_gguf_files: GGUF files in a repo, sorted smallest -> largest.
    func listGGUFFiles(repoID: String) async throws -> [GGUFFile] {
        let info = try await repoInfo(repoID: repoID)
        let files = info.siblings.compactMap { sib -> GGUFFile? in
            guard sib.rfilename.lowercased().hasSuffix(".gguf"), let size = sib.size, size > 0 else { return nil }
            return GGUFFile(repoID: repoID, filename: sib.rfilename, sizeBytes: size)
        }
        return files.sorted { $0.sizeBytes < $1.sizeBytes }
    }

    /// get_repo_files / repo_total_size_bytes
    func repoTotalSizeBytes(repoID: String) async throws -> Int64 {
        let info = try await repoInfo(repoID: repoID)
        return info.siblings.reduce(0) { $0 + ($1.size ?? 0) }
    }

    private func repoInfo(repoID: String) async throws -> RepoInfo {
        var comps = URLComponents(string: "\(apiBase)/\(repoID)")!
        comps.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        let (data, response) = try await session.data(from: comps.url!)
        try Self.checkOK(response)
        return try JSONDecoder().decode(RepoInfo.self, from: data)
    }

    // MARK: - Download

    /// download_gguf_file: streams a single file to disk with progress.
    func downloadGGUFFile(
        _ file: GGUFFile,
        into baseDir: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let destDir = baseDir
            .appendingPathComponent("gguf", isDirectory: true)
            .appendingPathComponent(file.repoID.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destPath = destDir.appendingPathComponent(file.filename)

        if let existing = try? FileManager.default.attributesOfItem(atPath: destPath.path)[.size] as? Int64,
           existing == file.sizeBytes {
            return destPath
        }

        let url = URL(string: "https://huggingface.co/\(file.repoID)/resolve/main/\(file.filename)")!
        try await streamDownload(from: url, to: destPath, expectedSize: file.sizeBytes, progress: progress)
        return destPath
    }

    /// download_mlx_repo: mirrors every file in the repo under a local folder.
    func downloadMLXRepo(
        repoID: String,
        into baseDir: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let destDir = baseDir
            .appendingPathComponent("mlx", isDirectory: true)
            .appendingPathComponent(repoID.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let info = try await repoInfo(repoID: repoID)
        let totalSize = max(info.siblings.reduce(0) { $0 + ($1.size ?? 0) }, 1)
        var doneSize: Int64 = 0

        for sib in info.siblings {
            let destPath = destDir.appendingPathComponent(sib.rfilename)
            try FileManager.default.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            if let existing = try? FileManager.default.attributesOfItem(atPath: destPath.path)[.size] as? Int64,
               let expected = sib.size, existing == expected {
                doneSize += expected
                progress(doneSize, totalSize)
                continue
            }

            let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(sib.rfilename)")!
            let before = doneSize
            try await streamDownload(from: url, to: destPath, expectedSize: sib.size ?? 0) { downloaded, _ in
                progress(before + downloaded, totalSize)
            }
            doneSize += sib.size ?? 0
        }
        return destDir
    }

    /// Uses a real URLSessionDownloadTask (not byte-by-byte AsyncBytes,
    /// which is far too slow for multi-GB model files) so the OS handles
    /// buffering efficiently; progress comes from the delegate callback.
    private func streamDownload(
        from url: URL,
        to destPath: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        try await DownloadTaskRunner.run(url: url, destPath: destPath, expectedSize: expectedSize, progress: progress)
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "HuggingFaceService", code: code, userInfo: [
                NSLocalizedDescriptionKey: "Hugging Face request failed (HTTP \(code))"
            ])
        }
    }
}
