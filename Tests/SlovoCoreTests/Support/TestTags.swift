import Testing

extension Tag {
    /// Exercises a real system API (NSSpellChecker / Text Input Sources); runs in
    /// the local gate, skipped where the environment is not faithful.
    @Tag static var integration: Tag
}
