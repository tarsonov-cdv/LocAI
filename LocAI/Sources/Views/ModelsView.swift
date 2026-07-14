import SwiftUI

struct ModelsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager

    @State private var searchQuery = ""
    @State private var repos: [String] = []
    @State private var selectedRepo: String?
    @State private var ggufFiles: [GGUFFile] = []
    @State private var selectedFile: GGUFFile?
    @State private var mlxRepoSize: Int64?
    @State private var isSearching = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var taskLabel = ""
    @State private var errorMessage: String?
    @State private var modelPendingDelete: LocalModel?

    var body: some View {
        let lang = settings.languageCode

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassHeader(title: Loc.t("tab_models", lang: lang), subtitle: nil)

                GlassCard {
                    Picker(Loc.t("backend", lang: lang), selection: Bindable(settings).backend) {
                        ForEach(Backend.allCases) { b in Text(b.rawValue).tag(b) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField(Loc.t("search_label", lang: lang), text: $searchQuery)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .staticBlurPanel(cornerRadius: 12)
                            .onSubmit(search)
                        GlassActionButton(title: Loc.t("search_button", lang: lang), systemImage: "magnifyingglass", prominent: true, isDisabled: isSearching, action: search)
                    }

                    quickPicks
                }

                GlassCard(title: Loc.t("repos_found", lang: lang)) {
                    repoList
                }

                if !ggufFiles.isEmpty || mlxRepoSize != nil {
                    GlassCard(title: settings.backend == .llamaCpp ? Loc.t("files_label_gguf", lang: lang) : Loc.t("files_label_mlx", lang: lang)) {
                        fileList
                    }
                }

                GlassCard {
                    HStack {
                        GlassActionButton(
                            title: Loc.t("download_selected", lang: lang),
                            systemImage: "arrow.down.circle.fill",
                            prominent: true,
                            isDisabled: isDownloading || (selectedFile == nil && (settings.backend == .mlx ? selectedRepo == nil : true)),
                            action: startDownload
                        )
                        if isDownloading {
                            ProgressView(value: downloadProgress)
                                .frame(maxWidth: .infinity)
                        }
                        Text(taskLabel.isEmpty ? Loc.t("ready", lang: lang) : taskLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }

                GlassCard(title: Loc.t("downloaded_models", lang: lang)) {
                    localModelsList
                }
            }
            .padding(16)
        }
        .onAppear { modelManager.refresh(base: settings.modelsBaseDir) }
        .alert(
            Loc.t("delete_confirm_title", lang: lang),
            isPresented: Binding(
                get: { modelPendingDelete != nil },
                set: { if !$0 { modelPendingDelete = nil } }
            ),
            presenting: modelPendingDelete
        ) { model in
            Button(Loc.t("delete_selected", lang: lang), role: .destructive) {
                deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text(model.displayName)
        }
    }

    private var quickPicks: some View {
        let picks = settings.backend == .llamaCpp ? CuratedModels.gguf : CuratedModels.mlx
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Text(Loc.t("quick_picks", lang: settings.languageCode)).font(.caption).foregroundStyle(.secondary)
                ForEach(picks, id: \.self) { repo in
                    Button(repo.components(separatedBy: "/").last ?? repo) {
                        selectRepo(repo)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
    }

    private var repoList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if repos.isEmpty {
                Text(isSearching ? "…" : "—").foregroundStyle(.secondary)
            }
            ForEach(repos, id: \.self) { repo in
                Button {
                    selectRepo(repo)
                } label: {
                    HStack {
                        Text(repo)
                        Spacer()
                        if selectedRepo == repo {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(selectedRepo == repo ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if settings.backend == .llamaCpp {
                ForEach(ggufFiles) { file in
                    Button {
                        selectedFile = (selectedFile == file) ? nil : file
                    } label: {
                        HStack {
                            Text(file.filename)
                            Spacer()
                            Text(String(format: "%.2f GB", file.sizeGB)).foregroundStyle(.secondary)
                            if selectedFile == file {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(selectedFile == file ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
            } else if let mlxRepoSize {
                Text(String(format: "%.2f GB total", Double(mlxRepoSize) / 1_073_741_824.0))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var localModelsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if modelManager.localModels.isEmpty {
                Text("—").foregroundStyle(.secondary)
            }
            ForEach(modelManager.localModels) { model in
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text(model.displayName)
                            if appState.loadedModelPath == model.path {
                                Text("●").foregroundStyle(.green).font(.caption)
                            }
                        }
                        Text("\(model.backend.rawValue) · \(String(format: "%.2f GB", Double(model.sizeBytes) / 1_073_741_824.0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassActionButton(title: Loc.t("send", lang: settings.languageCode), systemImage: "play.fill") {
                        Task { await appState.loadModel(model, settings: settings) }
                    }
                    Button(role: .destructive) {
                        modelPendingDelete = model
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(6)
            }
        }
    }

    // MARK: - Selection

    private func selectRepo(_ repo: String) {
        if selectedRepo == repo {
            // Tapping the already-selected repo deselects it.
            selectedRepo = nil
            ggufFiles = []
            mlxRepoSize = nil
            selectedFile = nil
            return
        }
        selectedRepo = repo
        Task { await loadFiles(for: repo) }
    }

    // MARK: - Actions

    private func search() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                repos = settings.backend == .llamaCpp
                    ? try await HuggingFaceService.shared.searchGGUFRepos(query: searchQuery)
                    : try await HuggingFaceService.shared.searchMLXRepos(query: searchQuery)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func loadFiles(for repo: String) async {
        ggufFiles = []
        mlxRepoSize = nil
        selectedFile = nil
        do {
            if settings.backend == .llamaCpp {
                ggufFiles = try await HuggingFaceService.shared.listGGUFFiles(repoID: repo)
            } else {
                mlxRepoSize = try await HuggingFaceService.shared.repoTotalSizeBytes(repoID: repo)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        IdleTimerManager.shared.preventSleep()

        Task {
            defer {
                IdleTimerManager.shared.allowSleep()
                isDownloading = false
            }

            do {
                if settings.backend == .llamaCpp, let file = selectedFile {
                    _ = try await HuggingFaceService.shared.downloadGGUFFile(
                        file,
                        into: settings.modelsBaseDir
                    ) { done, total in
                        Task { @MainActor in
                            downloadProgress = total > 0
                            ? Double(done) / Double(total)
                            : 0
                        }
                    }
                } else if settings.backend == .mlx, let repo = selectedRepo {
                    _ = try await HuggingFaceService.shared.downloadMLXRepo(
                        repoID: repo,
                        into: settings.modelsBaseDir
                    ) { done, total in
                        Task { @MainActor in
                            downloadProgress = total > 0
                            ? Double(done) / Double(total)
                            : 0
                        }
                    }
                }

                modelManager.refresh(base: settings.modelsBaseDir)

            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Deletes a local model file/folder. If it's the one currently
    /// loaded, unloads it first so AppState doesn't keep a backend
    /// pointing at files that no longer exist.
    private func deleteModel(_ model: LocalModel) {
        appState.unloadIfCurrent(path: model.path)
        try? modelManager.delete(model)
        modelManager.refresh(base: settings.modelsBaseDir)
        modelPendingDelete = nil
    }
}
