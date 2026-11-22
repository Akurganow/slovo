extension String {
    /// True when the text holds a character that is not whitespace. A transcript or a
    /// cleanup reply without one is empty: it is never cleaned or inserted
    /// (`AGENTS.md`, "Product intent — how the app must work", "Empty result").
    var hasVisibleCharacter: Bool { contains { !$0.isWhitespace } }
}
