import Foundation

public struct ProcessScanner: Sendable {
    private let runner = FixedCommandRunner()
    public init() {}

    public func scan(limit: Int = 50) throws -> [ProcessSnapshot] {
        let output = try runner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss=,etime=,comm="])
        return output.split(separator: "\n").compactMap(parseLine).sorted { lhs, rhs in
            if lhs.cpuPercent == rhs.cpuPercent { return lhs.residentBytes > rhs.residentBytes }
            return lhs.cpuPercent > rhs.cpuPercent
        }.prefix(max(1, min(limit, 500))).map { $0 }
    }

    private func parseLine(_ line: Substring) -> ProcessSnapshot? {
        let fields = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 5,
              let pid = Int32(fields[0]),
              let cpu = Double(fields[1]),
              let rssKB = Int64(fields[2]) else { return nil }
        let executable = String(fields[4])
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return .init(pid: pid, name: name.isEmpty ? executable : name, cpuPercent: cpu, residentBytes: rssKB * 1024, uptimeSeconds: parseElapsed(String(fields[3])))
    }

    private func parseElapsed(_ raw: String) -> Int64? {
        var days: Int64 = 0
        var time = raw
        if let dash = raw.firstIndex(of: "-") {
            days = Int64(raw[..<dash]) ?? 0
            time = String(raw[raw.index(after: dash)...])
        }
        let parts = time.split(separator: ":").compactMap { Int64($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let h = parts.count == 3 ? parts[0] : 0
        let m = parts.count == 3 ? parts[1] : parts[0]
        let s = parts.count == 3 ? parts[2] : parts[1]
        return days * 86_400 + h * 3_600 + m * 60 + s
    }
}
