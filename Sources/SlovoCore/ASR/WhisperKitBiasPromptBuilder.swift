import Foundation

/// Builds the prompt tokens that bias WhisperKit toward the user's vocabulary.
///
/// The prompt is a fictitious PRECEDING TRANSCRIPT, so it carries a one-line
/// glossary of bare surface forms — `"RCV, GitHub, OAuth."` — and never the
/// expansions, which belong to the downstream cleanup prompt.
enum WhisperKitBiasPromptBuilder {
    /// Upper bound on the tokens handed to `DecodingOptions.promptTokens`.
    ///
    /// The binding constraint is SAMPLING HEADROOM, not the SDK's 111-token prompt
    /// clamp. WhisperKit caps one decode window at 223 loop iterations
    /// (`min(initialPromptIndex - 1 + sampleLength, maxTokenContext - 1)`, with
    /// `sampleLength` defaulting to `maxTokenContext` = 224) and spends prefill
    /// tokens INSIDE that loop, so every prompt token costs one sampled output
    /// token. These 24 plus the 5 special prefill tokens leave 194 sampled tokens,
    /// against the ~143-178 a 30 s window of Russian at 120-150 wpm needs (~2.38
    /// tokens/word). The former 96-token budget left ~122 — below that demand — and
    /// truncated windows mid-speech: no closing timestamp, starved segment
    /// confirmation, temperature-fallback cascades, empty transcripts. Internal (not
    /// private) so a `@testable` test pins that inequality against this value.
    static let maxPromptTokens = 24

    /// The bias prompt for `biasTerms` (weight-descending), or `nil` when even its
    /// first term does not fit — an unbiased session beats a prompt that eats the
    /// window's sampling headroom.
    ///
    /// Trimming drops from the TAIL: the SDK keeps only the `.suffix` of an
    /// over-budget prompt, which would discard exactly the highest-weight head this
    /// budget exists to protect.
    static func promptTokens(
        for biasTerms: [Term],
        tokenizer: (String) -> [Int]
    ) -> [Int]? {
        // Lossless pre-bound on the key-down hot path: a surface costs at least one
        // token, so a prompt reaching index i spends at least i + 1 tokens and any
        // surface at index >= maxPromptTokens is already over budget. Trimming those
        // one at a time would re-tokenize the whole glossary per dropped surface.
        //
        // That >= 1 token per surface is a tokenizer property, not a guarantee — but
        // it fails benignly: a tokenizer packing several surfaces into one token would
        // only under-fill the budget (dropping surfaces that might have fit), never
        // overflow it. The loop below still enforces the ceiling either way.
        var surfaces = Array(distinctSurfaces(of: biasTerms).prefix(maxPromptTokens))
        while !surfaces.isEmpty {
            let tokens = tokenizer(promptText(for: surfaces))
            // No tokens for a non-empty glossary means the engine's tokenizer has not
            // loaded, so there is nothing to trim toward: the session runs unbiased.
            guard !tokens.isEmpty else { return nil }
            if tokens.count <= maxPromptTokens {
                return tokens
            }
            surfaces.removeLast()
        }
        return nil
    }

    private static func promptText(for surfaces: [String]) -> String {
        surfaces.joined(separator: ", ") + "."
    }

    /// Trimmed, non-empty surface forms in arrival order, with case-insensitive
    /// repeats collapsed onto the first occurrence — the highest-weighted one, and
    /// the spelling the user stored.
    private static func distinctSurfaces(of biasTerms: [Term]) -> [String] {
        var seen: Set<String> = []
        return biasTerms.compactMap { term in
            let surface = term.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surface.isEmpty, seen.insert(surface.lowercased()).inserted else { return nil }
            return surface
        }
    }
}
