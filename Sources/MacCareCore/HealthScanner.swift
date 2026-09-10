import Foundation

public struct HealthScanner: Sendable {
    private let runner = FixedCommandRunner()
    public init() {}

    public func scan() throws -> HealthSnapshot {
        let fm = FileManager.default
        let fs = try fm.attributesOfFileSystem(forPath: "/")
        let total = (fs[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (fs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let memory = try memorySnapshot()
        return .init(
            diskTotalBytes: total,
            diskFreeBytes: free,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            memoryUsedBytes: memory.used,
            memoryPressure: memory.pressure,
            swapUsedBytes: swapUsedBytes(),
            cpuUsedPercent: cpuPercent(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            battery: batterySnapshot()
        )
    }

    private func memorySnapshot() throws -> (used: Int64?, pressure: String) {
        let text = try runner.run(executable: "/usr/bin/memory_pressure", arguments: ["-Q"])
        let freePercent = text.split(separator: "\n").compactMap { line -> Int? in
            guard line.contains("System-wide memory free percentage:") else { return nil }
            return Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "") ?? "")
        }.first
        guard let freePercent else { return (nil, "unknown") }
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        let used = physical - (physical * Int64(freePercent) / 100)
        let pressure = freePercent >= 25 ? "normal" : (freePercent >= 10 ? "elevated" : "critical")
        return (used, pressure)
    }

    private func swapUsedBytes() -> Int64? {
        guard let text = try? runner.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"]),
              let range = text.range(of: #"used = ([0-9.]+)([MG])"#, options: .regularExpression) else { return nil }
        let match = String(text[range])
        let parts = match.replacingOccurrences(of: "used = ", with: "").split(whereSeparator: { $0 == "M" || $0 == "G" })
        guard let value = parts.first.flatMap({ Double($0) }) else { return nil }
        let multiplier: Double = match.contains("G") ? 1_073_741_824 : 1_048_576
        return Int64(value * multiplier)
    }

    private func cpuPercent() -> Double? {
        guard let text = try? runner.run(executable: "/bin/ps", arguments: ["-A", "-o", "%cpu="]) else { return nil }
        let sum = text.split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" }).compactMap { Double($0) }.reduce(0, +)
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return min(100, sum / Double(cores))
    }

    private func batterySnapshot() -> BatterySnapshot? {
        guard let text = try? runner.run(executable: "/usr/sbin/ioreg", arguments: ["-r", "-c", "AppleSmartBattery"]) else { return nil }
        func integer(_ key: String) -> Int? {
            guard let range = text.range(of: "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\" = [0-9]+", options: .regularExpression) else { return nil }
            return Int(text[range].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        let cycle = integer("CycleCount")
        let current = integer("CurrentCapacity")
        let maxCapacity = integer("AppleRawMaxCapacity") ?? integer("MaxCapacity")
        let design = integer("DesignCapacity")
        let health = (maxCapacity != nil && design != nil && design! > 0) ? min(100, Double(maxCapacity!) / Double(design!) * 100) : nil
        let charge = (current != nil && maxCapacity != nil && maxCapacity! > 0) ? min(100, Double(current!) / Double(maxCapacity!) * 100) : nil
        guard cycle != nil || health != nil || charge != nil else { return nil }
        return .init(cycleCount: cycle, healthPercent: health, chargePercent: charge)
    }
}
