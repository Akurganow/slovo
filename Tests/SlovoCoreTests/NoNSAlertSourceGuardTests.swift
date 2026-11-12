import Foundation
import Testing

// The project surfaces errors and configuration through the menu bar and native
// windows — never a focus-stealing modal. No `NSAlert` is constructed anywhere
// under Sources/.
@Suite("No NSAlert source guard")
struct NoNSAlertSourceGuardTests {
    /// Stated sensitivity: reintroduce any `NSAlert(` construction under Sources/ →
    /// the offending file is listed → RED. Comments/doc mentioning NSAlert are
    /// stripped first, so only real construction counts.
    @Test
    func noNSAlertIsConstructedUnderSources() throws {
        let offenders = try SourceText.swiftFiles(under: "Sources").filter { path in
            try SourceText.code(path).contains("NSAlert(")
        }
        #expect(offenders.isEmpty, "NSAlert must not be constructed under Sources/: \(offenders)")
    }
}
