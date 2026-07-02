import Foundation

/// Builds the prompt-token text used to bias WhisperKit toward user vocabulary.
public enum WhisperKitBiasPromptBuilder {
    /// Upper bound on the tokens handed to `DecodingOptions.promptTokens`.
    ///
    /// WhisperKit trims `promptTokens` to `(Constants.maxTokenContext / 2) - 1` and
    /// keeps only the `.suffix` (WhisperKit `Core/TextDecoder.swift`), where
    /// `Constants.maxTokenContext = Int(448 / 2) = 224` (WhisperKit `Core/Models.swift`)
    /// — half of Whisper's 448-token decoder context. So the SDK retains at most
    /// `(224 / 2) - 1 = 111` prompt tokens and drops the rest from the FRONT, which
    /// would discard our highest-weight head (terms arrive weight-desc). We budget
    /// below that 111-token ceiling with a safety margin so our head always survives
    /// the SDK's own clamp, with headroom for BPE tokenizing the joined lines more
    /// densely than any per-line estimate.
    public static let promptTokenBudget = 96

    public static func prompt(for biasTerms: [Term]) -> String? {
        let lines = spokenHintLines(for: biasTerms)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public static func promptTokens(
        for biasTerms: [Term],
        tokenizer: (String) -> [Int]
    ) -> [Int]? {
        let lines = spokenHintLines(for: biasTerms)
        guard !lines.isEmpty else {
            return nil
        }

        // Grow the prompt head-first (weight-desc) one line at a time, keeping the
        // last tokenization that stays within budget and dropping the tail once the
        // next line would exceed it. Tokenizing the joined prefix (not per-line
        // concatenation) keeps the result identical to the uncapped prompt when the
        // whole vocabulary fits.
        var budgetedTokens: [Int] = []
        for lineCount in 1...lines.count {
            let candidate = tokenizer(lines.prefix(lineCount).joined(separator: "\n"))
            if candidate.count > promptTokenBudget {
                break
            }
            budgetedTokens = candidate
        }
        return budgetedTokens.isEmpty ? nil : budgetedTokens
    }

    private static func spokenHintLines(for biasTerms: [Term]) -> [String] {
        biasTerms.map(\.spokenHint).filter { !$0.isEmpty }
    }
}

private extension Term {
    var spokenHint: String {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expansion = expansion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expansion.isEmpty
        else {
            return trimmedTerm
        }
        return "\(trimmedTerm) \(expansion)"
    }
}
