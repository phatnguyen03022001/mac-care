import Foundation

public enum PrivacyDecision: String, Codable, Sendable { case allowed, protected }
public enum CleanupRisk: String, Codable, Sendable, CaseIterable { case safe = "SAFE", review = "REVIEW", protected = "PROTECTED" }

public struct CleanupCandidateSummary: Codable, Sendable, Identifiable, Hashable {
    public var id: String { candidateID }
    public let candidateID: String
    public let category: String
    public let displayPath: String
    public let estimatedBytes: Int64
    public let reason: String
    public let risk: CleanupRisk
    public let proposedAction: String
}

public struct CleanupPlan: Codable, Sendable {
    public let planID: String
    public let createdAt: Date
    public let expiresAt: Date
    public let candidates: [CleanupCandidateSummary]
}

public struct CleanupExecutionResult: Codable, Sendable {
    public let candidateID: String
    public let success: Bool
    public let message: String
}

enum CleanupTarget: Sendable {
    case file(URL)
    case brewCleanup
    case brewAutoremove
}

struct PlannedCleanupCandidate: Sendable {
    let candidateID: String
    let category: String
    let displayPath: String
    let estimatedBytes: Int64
    let reason: String
    let risk: CleanupRisk
    let proposedAction: String
    let target: CleanupTarget

    init(candidateID: String = UUID().uuidString, category: String, displayPath: String, estimatedBytes: Int64, reason: String, risk: CleanupRisk, proposedAction: String, target: CleanupTarget) {
        self.candidateID = candidateID; self.category = category; self.displayPath = displayPath
        self.estimatedBytes = estimatedBytes; self.reason = reason; self.risk = risk
        self.proposedAction = proposedAction; self.target = target
    }

    var summary: CleanupCandidateSummary {
        .init(candidateID: candidateID, category: category, displayPath: displayPath, estimatedBytes: estimatedBytes, reason: reason, risk: risk, proposedAction: proposedAction)
    }
}

public struct StorageCategorySummary: Codable, Sendable, Identifiable {
    public var id: String { category }
    public let category: String
    public let bytes: Int64
    public let candidates: Int
}

public struct StorageScanReport: Codable, Sendable {
    public let categories: [StorageCategorySummary]
    public let estimatedReclaimableBytes: Int64
    public let candidateCount: Int
}

public struct ProcessSnapshot: Codable, Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let residentBytes: Int64
    public let uptimeSeconds: Int64?
}

public struct BatterySnapshot: Codable, Sendable {
    public let cycleCount: Int?
    public let healthPercent: Double?
    public let chargePercent: Double?
}

public struct HealthSnapshot: Codable, Sendable {
    public let diskTotalBytes: Int64
    public let diskFreeBytes: Int64
    public let physicalMemoryBytes: UInt64
    public let memoryUsedBytes: Int64?
    public let memoryPressure: String
    public let swapUsedBytes: Int64?
    public let cpuUsedPercent: Double?
    public let uptimeSeconds: TimeInterval
    public let battery: BatterySnapshot?
}

public struct ApplicationSnapshot: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let path: String
    public let approximateBytes: Int64
    public let lastUsedAt: Date?
    public let usageSignal: String
}

public struct BrewSnapshot: Codable, Sendable {
    public let available: Bool
    public let version: String?
    public let outdatedFormulae: [String]
    public let outdatedCasks: [String]
    public let cleanupPreview: [String]
    public let unusedDependencies: [String]
    public let cacheBytes: Int64?
}

public struct PrivacyCheck: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let passed: Bool
}

public struct PrivacySelfTestReport: Codable, Sendable {
    public let passed: Bool
    public let checks: [PrivacyCheck]
}

public enum MCPToolCatalog {
    public static let names = ["health_check", "storage_scan", "process_scan", "app_scan", "brew_scan", "cleanup_plan", "cleanup_execute", "privacy_self_test"]
}
