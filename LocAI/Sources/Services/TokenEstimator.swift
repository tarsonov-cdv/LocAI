import Foundation

/// A fast, backend-agnostic token estimate (~4 characters per token, the
/// standard rule of thumb for BPE tokenizers). This intentionally does
/// NOT call into the loaded model's real tokenizer: that would mean an
/// async round-trip into the MLX container on every keystroke, which is
/// both slow and backend-specific (llama.cpp has none right now). Good
/// enough to gauge "am I near the context limit", not meant to be exact.
enum TokenEstimator {
    static func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let charEstimate = Int((Double(text.count) / 4.0).rounded(.up))
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // Never estimate below the word count - short/punctuation-heavy
        // text under-counts on the char/4 rule alone.
        return max(charEstimate, wordCount)
    }

    static func count(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + count($1.content) }
    }
}
