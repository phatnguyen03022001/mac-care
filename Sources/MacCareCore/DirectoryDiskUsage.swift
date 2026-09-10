import Foundation

struct DirectoryDiskUsage: Sendable {
    func size(of directory: URL) throws -> Int64 {
        let url = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: url.path) else {
            throw MacCareError.commandFailed("Directory usage unavailable.")
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MacCareError.commandFailed("Directory usage unavailable.")
        }
        return try parseKiB(data)
    }
}

private extension DirectoryDiskUsage {
    func parseKiB(_ data: Data) throws -> Int64 {
        let text = String(decoding: data, as: UTF8.self)
        guard let firstLine = text.split(separator: "\n", maxSplits: 1).first,
              let firstField = firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
              let kib = UInt64(firstField),
              kib <= UInt64(Int64.max) / 1024 else {
            throw MacCareError.commandFailed("Directory usage output was invalid.")
        }
        return Int64(kib * 1024)
    }
}
