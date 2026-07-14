import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @State private var inputText: String = ""

    private var inputTokenCount: Int { TokenEstimator.count(inputText) }

    var body: some View {
        @Bindable var appState = appState
        let lang = settings.languageCode

        VStack(spacing: 12) {
            GlassHeader(
                title: Loc.t("app_title", lang: lang),
                subtitle: appState.loadedModelLabel.isEmpty
                    ? Loc.t("no_model_loaded", lang: lang)
                    : "\(Loc.t("loaded_model", lang: lang)) \(appState.loadedModelLabel)"
            )

            tokenCounterBar

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: appState.messages.last?.content) {
                    if let lastID = appState.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollProxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            .staticBlurPanel(cornerRadius: 18)

            inputBar
        }
        .padding(16)
    }

    /// Total tokens committed to the conversation so far vs. the loaded
    /// model's context window, plus how many tokens the draft in the
    /// input box would add.
    private var tokenCounterBar: some View {
        HStack(spacing: 12) {
            Label {
                if let contextLength = appState.contextLength {
                    Text("\(appState.totalTokenCount) / \(contextLength)")
                } else {
                    Text("\(appState.totalTokenCount)")
                }
            } icon: {
                Image(systemName: "number")
            }
            .font(.caption)
            .foregroundStyle(tokenBarColor)

            if !inputText.isEmpty {
                Text("+\(inputTokenCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var tokenBarColor: Color {
        guard let contextLength = appState.contextLength, contextLength > 0 else { return .secondary }
        let ratio = Double(appState.totalTokenCount + inputTokenCount) / Double(contextLength)
        if ratio >= 0.95 { return .red }
        if ratio >= 0.75 { return .orange }
        return .secondary
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                Loc.t("send", lang: settings.languageCode),
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(12)
            .staticBlurPanel(cornerRadius: 14)
            .onSubmit(sendMessage)

            VStack(spacing: 6) {
                GlassActionButton(
                    title: Loc.t("send", lang: settings.languageCode),
                    systemImage: "paperplane.fill",
                    prominent: true,
                    isDisabled: appState.backend == nil || appState.isGenerating,
                    action: sendMessage
                )
                GlassActionButton(
                    title: Loc.t("clear_chat", lang: settings.languageCode),
                    systemImage: "trash"
                ) {
                    appState.clearChat(settings: settings)
                }
            }
        }
    }

    private func sendMessage() {
        guard appState.backend != nil else { return }
        let text = inputText
        inputText = ""
        appState.send(text: text, settings: settings)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !message.isStreaming && !message.content.isEmpty {
                        Text("· \(TokenEstimator.count(message.content)) tok")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                    .textSelection(.enabled)
            }
            .padding(12)
            .staticBlurPanel(cornerRadius: 16, tint: isUser ? .accentColor : nil)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
