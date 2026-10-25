// swift-tools-version: 6.3
import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-warnings-as-errors",
        "-strict-concurrency=complete",
        "-enable-actor-data-race-checks",
    ]),
]

let package = Package(
    name: "slovo",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Zetetic's SQLCipher-enabled distribution of upstream GRDB (tags
        // mirror groue/GRDB.swift): the personalization DB is encrypted at rest.
        .package(url: "https://github.com/sqlcipher/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        // Command plugin only (Scripts/lint.sh). No target uses the build-tool
        // plugin: it hands its prebuild command the whole process environment
        // (SwiftLintPlugins 0.65.1 source, SwiftLintBuildToolPlugin.swift:87),
        // and on a lint failure SwiftPM prints that command with its environment,
        // API keys included (swift-package-manager swift-6.4.0-RELEASE source,
        // Sources/Build/BuildPlan/BuildPlan.swift:907; reproduced on 6.4.0).
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
        .package(url: "https://github.com/sindresorhus/Settings", from: "3.1.1"),
        // Sparkle 2 auto-update engine. App target only — SlovoCore stays
        // Sparkle-free, enforced by the SwiftPM target graph (an `import Sparkle`
        // in the core cannot compile).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5"),
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
            // Product-owned resources travel in the SlovoCore bundle: the prompt
            // examples plus the user-approved dictation cue triplet.
            resources: [
                .copy("Resources/PromptExamples.xml"),
                .copy("Resources/AudioCues"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // Test-only fakes for the seam protocols. A separate library target so the
        // shipped `slovo` executable never links it; only test targets depend on it.
        .target(
            name: "SlovoTestSupport",
            dependencies: ["SlovoCore"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "CleanupBenchmark",
            dependencies: ["SlovoCore"],
            path: "Tools/cleanup-benchmark",
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "slovo-cleanup-benchmark",
            dependencies: ["CleanupBenchmark"],
            path: "Tools/cleanup-benchmark-cli",
            swiftSettings: strictSwiftSettings
        ),
        // Application entrypoint and AppKit composition owner.
        .executableTarget(
            name: "slovo",
            dependencies: [
                "SlovoCore",
                .product(name: "Settings", package: "Settings"),
                // App-shell auto-update; never linked into SlovoCore so the core
                // stays updater-free (target-graph enforced).
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: strictSwiftSettings,
            // The staged bundle carries Sparkle.framework in Contents/Frameworks;
            // this rpath lets the launched executable resolve it, declared here
            // instead of mutating the binary in the packaging scripts.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // Unit/behavioral tests for the core library.
        .testTarget(
            name: "SlovoCoreTests",
            dependencies: ["SlovoCore", "SlovoTestSupport", "SlovoObjC"],
            swiftSettings: strictSwiftSettings
        ),
        // Unit tests for the non-product cleanup benchmark harness.
        .testTarget(
            name: "CleanupBenchmarkTests",
            dependencies: ["CleanupBenchmark", "SlovoCore"],
            swiftSettings: strictSwiftSettings
        ),
        // The L1 prevention gates, implemented as source-tree-scanning tests. The
        // scanner (`GateChecks`) lives in this target — it is a build-time gate,
        // not shipped product code, so it does not depend on `SlovoCore`. The
        // `.swifttext` fixtures are read from disk via `#filePath`, not loaded as
        // SwiftPM resources, so they are excluded from the build graph.
        .testTarget(
            name: "GateChecksTests",
            exclude: ["Fixtures"],
            swiftSettings: strictSwiftSettings
        ),
    ]
)
