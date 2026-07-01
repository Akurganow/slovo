import Foundation
import Testing

@Suite("Development run script")
struct AppDevelopmentRunScriptTests {
    @Test
    func signsStagedAppBeforeLaunch() throws {
        let source = try String(
            contentsOf: Self.packageRoot.appending(path: "script/build_and_run.sh"),
            encoding: .utf8
        )

        #expect(source.contains(#"RUN_DIR="$ROOT_DIR/.build/dev-run""#))
        #expect(source.contains(#"cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist""#))
        #expect(source.contains("codesign"))
        #expect(source.contains("--options runtime"))
        #expect(source.contains(#"--entitlements "$ROOT_DIR/slovo.entitlements""#))
        #expect(source.contains("resolve_signing_identity()"))
        #expect(source.contains("Slovo Local Development"))
        #expect(source.contains("ALLOW_AD_HOC_SIGNING"))
        #expect(source.contains(#"--sign "$identity""#))
        #expect(source.contains("/usr/bin/open -n \"$APP_BUNDLE\""))
        #expect(source.contains("pgrep -x \"$PROCESS_NAME\""))
    }

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
