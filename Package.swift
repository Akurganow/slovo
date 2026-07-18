// swift-tools-version: 6.3
import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-warnings-as-errors",
        "-strict-concurrency=complete",
        "-enable-actor-data-race-checks",
    ]),
]

let swiftLintPlugins: [Target.PluginUsage] = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
]

// Foundation shell for slovo. Production dictation runs on WhisperKit (argmax
// oss-swift); each heavy dependency is added by the epic that first uses it, so
// the foundation resolves only what is actually consumed. GRDB enters here
// (Epic 08) as the persistence library for the personalization store.
let package = Package(
    name: "slovo",
    // macOS-only app. The macOS 26 floor is driven by Apple's on-device
    // SpeechTranscriber / SpeechAnalyzer APIs (macOS 26+), which the dictation
    // pipeline depends on; earlier minimums would not resolve them.
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.0"),
        .package(url: "https://github.com/sindresorhus/Settings", from: "3.1.1"),
        // Modern (SMAppService-based) launch-at-login, for macOS 13+. Consumed by
        // the app target only — never SlovoCore, which must stay UI/login-free.
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.1.0"),
        // Sparkle 2 auto-update engine. App target only — SlovoCore stays
        // Sparkle-free, enforced by the SwiftPM target graph (an `import Sparkle`
        // in the core cannot compile).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        // Objective-C interop shims that Swift cannot express live here — a
        // deliberate C-only bucket, intentionally exempt from the Swift
        // settings/lint gates (they do not apply to `.m` sources). Currently one
        // function: it wraps AVFoundation calls that report failure by raising an
        // `NSException` (which Swift's do/catch cannot catch, so an uncaught one
        // aborts the process) and hands the error back to Swift instead.
        .target(name: "SlovoObjC"),
        // Testable core. Owns the only `import GRDB` (the persistence adapter);
        // role-tagged source modules must NOT import GRDB (dependency-direction gate).
        .target(
            name: "SlovoCore",
            dependencies: [
                "SlovoObjC",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            // The abandoned Apple-Speech transcriber is retained on disk but left
            // out of the build until its deletion is approved.
            exclude: ["ASR/SystemSpeechTranscriber.swift"],
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        // Test-only fakes for the seam protocols. A separate library target so the
        // shipped `slovo` executable never links it; only test targets depend on it.
        .target(
            name: "SlovoTestSupport",
            dependencies: ["SlovoCore"],
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        .target(
            name: "CleanupBenchmark",
            dependencies: ["SlovoCore"],
            path: "Tools/cleanup-benchmark",
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        .executableTarget(
            name: "slovo-cleanup-benchmark",
            dependencies: ["CleanupBenchmark"],
            path: "Tools/cleanup-benchmark-cli",
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        // Application entrypoint and AppKit composition owner.
        .executableTarget(
            name: "slovo",
            dependencies: [
                "SlovoCore",
                .product(name: "Settings", package: "Settings"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                // App-shell auto-update; never linked into SlovoCore so the core
                // stays updater-free (target-graph enforced).
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: strictSwiftSettings,
            // The staged bundle carries Sparkle.framework in Contents/Frameworks;
            // this rpath lets the launched executable resolve it, declared here
            // instead of mutating the binary in the packaging scripts.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])],
            plugins: swiftLintPlugins
        ),
        // Unit/behavioral tests for the core library.
        .testTarget(
            name: "SlovoCoreTests",
            dependencies: ["SlovoCore", "SlovoTestSupport", "SlovoObjC"],
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        // Unit tests for the non-product cleanup benchmark harness.
        .testTarget(
            name: "CleanupBenchmarkTests",
            dependencies: ["CleanupBenchmark", "SlovoCore"],
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
        // The L1 prevention gates, implemented as source-tree-scanning tests. The
        // scanner (`GateChecks`) lives in this target — it is a build-time gate,
        // not shipped product code, so it does not depend on `SlovoCore`. The
        // `.swifttext` fixtures are read from disk via `#filePath`, not loaded as
        // SwiftPM resources, so they are excluded from the build graph.
        .testTarget(
            name: "GateChecksTests",
            exclude: ["Fixtures"],
            swiftSettings: strictSwiftSettings,
            plugins: swiftLintPlugins
        ),
    ]
)
