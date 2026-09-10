import Foundation

struct FixedCommandRunner: Sendable {
    func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe(); let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MacCareError.commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct BrewCommandRunner: Sendable {
    enum Operation: Sendable { case version, cachePath, outdated, cleanupDryRun, autoremoveDryRun, cleanup, autoremove }
    let executable: String
    private let runner = FixedCommandRunner()

    init?(executable: String? = nil) {
        let candidates = executable.map { [$0] } ?? ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        self.executable = found
    }

    func run(_ operation: Operation) throws -> String {
        let args: [String]
        switch operation {
        case .version: args = ["--version"]
        case .cachePath: args = ["--cache"]
        case .outdated: args = ["outdated", "--json=v2"]
        case .cleanupDryRun: args = ["cleanup", "--dry-run"]
        case .autoremoveDryRun: args = ["autoremove", "--dry-run"]
        case .cleanup: args = ["cleanup"]
        case .autoremove: args = ["autoremove"]
        }
        return try runner.run(executable: executable, arguments: args)
    }
}
