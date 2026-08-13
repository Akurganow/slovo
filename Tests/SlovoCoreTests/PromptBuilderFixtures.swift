/// Hand-authored cleanup-prompt fragments shared by the prompt suites. Authored from
/// the spec wording and never derived from `PromptBuilder`, so builder drift cannot
/// drag the expectation along with it.
enum PromptBuilderFixtures {
    static let parentheticalGuardLine = "The parenthetical is context only: never write it into the output, "
        + "and never expand an abbreviation the speaker said in short form."
}
