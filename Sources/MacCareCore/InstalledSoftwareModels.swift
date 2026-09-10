import Foundation

public enum InstalledSoftwareComponentKind: String, Codable, Sendable, CaseIterable {
    case application = "APPLICATION"
    case nestedApplication = "NESTED_APPLICATION"
    case helper = "HELPER"
    case launchAgent = "LAUNCH_AGENT"
    case launchDaemon = "LAUNCH_DAEMON"
    case loginOrBackgroundItem = "LOGIN_OR_BACKGROUND_ITEM"
    case systemExtension = "SYSTEM_EXTENSION"
    case homebrewFormula = "HOMEBREW_FORMULA"
    case homebrewCask = "HOMEBREW_CASK"
    case homebrewService = "HOMEBREW_SERVICE"
}

public enum InstalledSoftwareInventorySource: String, Codable, Sendable, CaseIterable {
    case applications = "applications"
    case applicationSupport = "application_support"
    case userLaunchAgents = "user_launch_agents"
    case systemLaunchAgents = "system_launch_agents"
    case launchDaemons = "launch_daemons"
    case loginBackgroundItems = "login_background_items"
    case systemExtensions = "system_extensions"
    case homebrewFormulae = "homebrew_formulae"
    case homebrewCasks = "homebrew_casks"
    case homebrewServices = "homebrew_services"
}

public enum SoftwareAssociationConfidence: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

public enum InventorySourceAvailability: String, Codable, Sendable {
    case available = "AVAILABLE"
    case partial = "PARTIAL"
    case unavailable = "UNAVAILABLE"
}

public struct InstalledSoftwareComponent: Codable, Sendable {
    public let displayName: String
    public let identifier: String?
    public let vendorIdentifier: String?
    public let kind: InstalledSoftwareComponentKind
    public let path: String?
    public let version: String?
    public let source: InstalledSoftwareInventorySource
    public let associatedProduct: String?
    public let associationConfidence: SoftwareAssociationConfidence?
    public let executionStatus: String?
    public let cleanupDisposition: CleanupRisk
}

public struct InstalledSoftwareSourceStatus: Codable, Sendable {
    public let source: InstalledSoftwareInventorySource
    public let status: InventorySourceAvailability
    public let itemCount: Int
    public let detail: String?
}

public struct InstalledSoftwareInventorySummary: Codable, Sendable {
    public let applicationCount: Int
    public let componentCount: Int
    public let totalCount: Int
    public let countsByKind: [String: Int]
}

public struct InstalledSoftwareInventoryReport: Codable, Sendable {
    public let applications: [ApplicationSnapshot]
    public let components: [InstalledSoftwareComponent]
    public let summary: InstalledSoftwareInventorySummary
    public let sources: [InstalledSoftwareSourceStatus]
    public let truncated: Bool
}

struct InventoryParseResult: Sendable {
    let components: [InstalledSoftwareComponent]
    let partial: Bool
    let truncated: Bool
}
