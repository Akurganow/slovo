import Foundation

/// Builds the prompt-token text used to bias WhisperKit toward user vocabulary.
public enum WhisperKitBiasPromptBuilder {
    public static func prompt(for biasTerms: [Term]) -> String? {
        let lines = biasTerms.map(\.spokenHint).filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public static func promptTokens(
        for biasTerms: [Term],
        tokenizer: (String) -> [Int]
    ) -> [Int]? {
        guard let prompt = prompt(for: biasTerms) else {
            return nil
        }
        let tokens = tokenizer(prompt)
        return tokens.isEmpty ? nil : tokens
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
