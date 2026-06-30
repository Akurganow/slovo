import CleanupBenchmark
import Foundation

@main
enum CleanupBenchmarkCommand {
    static func main() async {
        let result = await CleanupBenchmarkCommandDriver().run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: ProcessInfo.processInfo.environment
        )
        if !result.stdout.isEmpty {
            print(result.stdout)
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr, stderr)
        }
        Foundation.exit(result.exitCode)
    }
}
