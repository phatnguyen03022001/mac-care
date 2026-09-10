import Foundation

public enum BackgroundSecurityRecommendation: String, Codable, Sendable, CaseIterable {
    case keepEnabled = "KEEP_ENABLED"
    case disableIfUnused = "DISABLE_IF_UNUSED"
    case enableRecommended = "ENABLE_RECOMMENDED"
    case review = "REVIEW"
    case noAction = "NO_ACTION"
    case unknown = "UNKNOWN"
}

public enum RecommendationConfidence: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

public enum SecurityControlState: String, Codable, Sendable {
    case enabled = "ENABLED"
    case disabled = "DISABLED"
    case unknown = "UNKNOWN"
    case unsupported = "UNSUPPORTED"
}

public enum SecurityControlKind: String, Codable, Sendable, CaseIterable {
    case gatekeeper = "GATEKEEPER"
    case fileVault = "FILEVAULT"
    case sip = "SIP"
    case firewall = "FIREWALL"
    case firewallStealthMode = "FIREWALL_STEALTH_MODE"
    case firewallBlockAll = "FIREWALL_BLOCK_ALL"
}

public enum SecurityAuditSourceAvailability: String, Codable, Sendable {
    case available = "AVAILABLE"
    case partial = "PARTIAL"
    case unavailable = "UNAVAILABLE"
    case unsupported = "UNSUPPORTED"
}

public struct SecurityControlAuditItem: Codable, Sendable {
    public let item: String
    public let category: SecurityControlKind
    public let currentState: SecurityControlState
    public let recommendation: BackgroundSecurityRecommendation
    public let reason: String
    public let confidence: RecommendationConfidence
    public let operatorActionRequired: Bool
}

public struct BackgroundSecurityRecommendationItem: Codable, Sendable {
    public let item: String
    public let category: String
    public let currentState: String
    public let recommendation: BackgroundSecurityRecommendation
    public let reason: String
    public let confidence: RecommendationConfidence
    public let operatorActionRequired: Bool
    public let associatedProduct: String?
    public let identifier: String?
    public let source: InstalledSoftwareInventorySource
    public let componentSubtype: String?
}

public struct SecurityAuditSourceStatus: Codable, Sendable {
    public let source: String
    public let status: SecurityAuditSourceAvailability
    public let detail: String
}

public struct BackgroundSecurityAuditSummary: Codable, Sendable {
    public let keepEnabledCount: Int
    public let disableIfUnusedCount: Int
    public let enableRecommendedCount: Int
    public let reviewCount: Int
    public let noActionCount: Int
    public let unknownCount: Int

    init(items: [SecurityControlAuditItem]) {
        self.init(recommendations: items.map(\.recommendation))
    }

    init(
        securityControls: [SecurityControlAuditItem],
        backgroundRecommendations: [BackgroundSecurityRecommendationItem],
        extensionRecommendations: [BackgroundSecurityRecommendationItem]
    ) {
        let recommendations = securityControls.map(\.recommendation)
            + backgroundRecommendations.map(\.recommendation)
            + extensionRecommendations.map(\.recommendation)
        self.init(recommendations: recommendations)
    }

    private init(recommendations: [BackgroundSecurityRecommendation]) {
        keepEnabledCount = recommendations.filter { $0 == .keepEnabled }.count
        disableIfUnusedCount = recommendations.filter { $0 == .disableIfUnused }.count
        enableRecommendedCount = recommendations.filter { $0 == .enableRecommended }.count
        reviewCount = recommendations.filter { $0 == .review }.count
        noActionCount = recommendations.filter { $0 == .noAction }.count
        unknownCount = recommendations.filter { $0 == .unknown }.count
    }
}

public struct BackgroundSecurityAuditReport: Codable, Sendable {
    public let securityControls: [SecurityControlAuditItem]
    public let backgroundRecommendations: [BackgroundSecurityRecommendationItem]
    public let extensionRecommendations: [BackgroundSecurityRecommendationItem]
    public let summary: BackgroundSecurityAuditSummary
    public let sources: [SecurityAuditSourceStatus]
}

struct SecurityControlScanResult: Sendable {
    let items: [SecurityControlAuditItem]
    let sources: [SecurityAuditSourceStatus]
}
