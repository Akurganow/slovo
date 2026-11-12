import Foundation

// The App runtime suite's own source list, split out to keep the suite file under the
// project length limit. The shared source-reading helpers live in `SourceText`.
extension AppRuntimeSourceGuardTests {
    static func productionAsrRuntimeSources() throws -> [SourceFile] {
        let sourcePaths = try [
            "Sources/SlovoCore/ASR",
            "Sources/SlovoCore/Composition",
            "Sources/slovo",
        ].flatMap { try SourceText.swiftFiles(under: $0) } + ["Package.swift"]

        return try sourcePaths
            .sorted()
            .map { (relativePath: $0, contents: try SourceText.code($0)) }
    }

    typealias SourceFile = (relativePath: String, contents: String)
}
