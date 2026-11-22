import Testing

@testable import SlovoCore

@Suite("Visible text")
struct VisibleTextTests {
    /// Stated sensitivity: `!isEmpty` -> the `" "`, `"\n"`, `"\t"` and no-break-space rows
    /// go RED. Treating only space, newline and tab as blank -> the no-break-space row
    /// goes RED. `allSatisfy { !$0.isWhitespace }` -> the `""` row goes RED.
    /// `$0.isLetter` as the test of visible -> the emoji and zero-width-space rows go RED.
    /// Counting U+200B as blank -> the zero-width-space row goes RED.
    @Test(arguments: [
        ("", false),
        (" ", false),
        ("\n", false),
        ("\t", false),
        ("\u{00A0}", false),
        ("a", true),
        ("🙂", true),
        ("\u{200B}", true),
    ])
    func hasVisibleCharacterIsFalseOnlyWhenEveryCharacterIsWhitespace(text: String, expected: Bool) {
        #expect(text.hasVisibleCharacter == expected)
    }
}
