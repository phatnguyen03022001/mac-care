import XCTest
@testable import MacCareCore

final class BackgroundSecurityAuditTests: XCTestCase {
    func testGatekeeperEnabledRecommendsKeepEnabled() {
        let state = SecurityControlParser.gatekeeper("assessments enabled")
        let item = SecurityRecommendationPolicy.securityControl(.gatekeeper, state: state)
        XCTAssertEqual(item.currentState, .enabled)
        XCTAssertEqual(item.recommendation, .keepEnabled)
        XCTAssertEqual(item.confidence, .high)
    }

    func testFileVaultEnabledRecommendsKeepEnabled() {
        let state = SecurityControlParser.fileVault("FileVault is On.")
        let item = SecurityRecommendationPolicy.securityControl(.fileVault, state: state)
        XCTAssertEqual(item.currentState, .enabled)
        XCTAssertEqual(item.recommendation, .keepEnabled)
        XCTAssertEqual(item.confidence, .high)
    }

    func testSIPEnabledRecommendsKeepEnabled() {
        let state = SecurityControlParser.sip("System Integrity Protection status: enabled.")
        let item = SecurityRecommendationPolicy.securityControl(.sip, state: state)
        XCTAssertEqual(item.currentState, .enabled)
        XCTAssertEqual(item.recommendation, .keepEnabled)
    }
    func testFirewallEnabledRecommendsKeepEnabled() {
        let state = SecurityControlParser.firewall("Firewall is enabled. (State = 1)")
        let item = SecurityRecommendationPolicy.securityControl(.firewall, state: state)
        XCTAssertEqual(item.currentState, .enabled)
        XCTAssertEqual(item.recommendation, .keepEnabled)
    }

    func testDisabledMandatoryControlRecommendsEnable() {
        let state = SecurityControlParser.sip("System Integrity Protection status: disabled.")
        let item = SecurityRecommendationPolicy.securityControl(.sip, state: state)
        XCTAssertEqual(item.currentState, .disabled)
        XCTAssertEqual(item.recommendation, .enableRecommended)
        XCTAssertTrue(item.operatorActionRequired)
    }

    func testUnknownSecurityOutputNeverInventsState() {
        let state = SecurityControlParser.fileVault("unexpected future output")
        let item = SecurityRecommendationPolicy.securityControl(.fileVault, state: state)
        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(item.recommendation, .unknown)
        XCTAssertEqual(item.confidence, .low)
    }

    func testFirewallOptionalModesRemainConservative() {
        let stealth = SecurityRecommendationPolicy.securityControl(.firewallStealthMode, state: .disabled)
        let blockAll = SecurityRecommendationPolicy.securityControl(.firewallBlockAll, state: .disabled)
        XCTAssertEqual(stealth.recommendation, .noAction)
        XCTAssertEqual(blockAll.recommendation, .noAction)
    }

    func testStaleLaunchItemIsReview() {
        let component = makeComponent(
            name: "Stale Agent",
            identifier: "com.example.stale",
            kind: .launchAgent,
            path: "/definitely/missing/example-agent",
            associatedProduct: nil,
            confidence: nil,
            status: "enabled"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: false)
        XCTAssertEqual(item.recommendation, .review)
        XCTAssertTrue(item.reason.lowercased().contains("stale") || item.reason.lowercased().contains("orphan"))
    }

    func testUpdaterRecommendationIsConditional() {
        let component = makeComponent(
            name: "Example Updater",
            identifier: "com.example.updater",
            kind: .loginOrBackgroundItem,
            path: nil,
            associatedProduct: "Example",
            confidence: .high,
            status: "enabled"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: nil)
        XCTAssertEqual(item.recommendation, .disableIfUnused)
        XCTAssertTrue(item.reason.lowercased().contains("unused"))
        XCTAssertTrue(item.operatorActionRequired)
    }

    func testDisabledUpdaterNeedsNoFurtherDisableRecommendation() {
        let component = makeComponent(
            name: "Example Updater", identifier: "com.example.updater",
            kind: .loginOrBackgroundItem, path: nil, associatedProduct: "Example",
            confidence: .high, status: "disabled"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: nil)
        XCTAssertEqual(item.recommendation, .noAction)
    }

    func testSystemExtensionRecommendationIsConservative() {
        let component = makeComponent(
            name: "Example Driver",
            identifier: "com.example.driver",
            kind: .systemExtension,
            path: nil,
            associatedProduct: nil,
            confidence: nil,
            status: "activated enabled",
            subtype: "driver_extension"
        )
        let item = SecurityRecommendationPolicy.extensions([component]).first
        XCTAssertEqual(item?.recommendation, .review)
    }

    func testVPNCoexistenceRecommendsReviewNotDisable() {
        let first = makeComponent(
            name: "VPN A",
            identifier: "com.example.vpna",
            kind: .systemExtension,
            path: nil,
            associatedProduct: "VPN A",
            confidence: .high,
            status: "activated enabled",
            subtype: "network_extension"
        )
        let second = makeComponent(
            name: "VPN B",
            identifier: "com.example.vpnb",
            kind: .systemExtension,
            path: nil,
            associatedProduct: "VPN B",
            confidence: .high,
            status: "activated enabled",
            subtype: "network_extension"
        )
        let items = SecurityRecommendationPolicy.extensions([first, second])
        XCTAssertEqual(items.map(\.recommendation), [.review, .review])
        XCTAssertTrue(items.allSatisfy { $0.reason.lowercased().contains("coexist") || $0.reason.lowercased().contains("network") })
    }

    func testEndpointSecurityExtensionIsNeverRecommendedOffForPerformance() {
        let component = makeComponent(
            name: "Endpoint Security",
            identifier: "com.example.endpoint",
            kind: .systemExtension,
            path: nil,
            associatedProduct: "Security Product",
            confidence: .high,
            status: "activated enabled",
            subtype: "endpoint_security"
        )
        let item = SecurityRecommendationPolicy.extensions([component]).first
        XCTAssertNotEqual(item?.recommendation, .disableIfUnused)
        XCTAssertTrue(item?.recommendation == .keepEnabled || item?.recommendation == .review)
    }

    func testSharedTunnelServiceNeverGetsAutomaticDisableRecommendation() {
        let component = makeComponent(
            name: "cloudflared", identifier: "cloudflared", kind: .homebrewService,
            path: nil, associatedProduct: "Secure Tunnel", confidence: .high, status: "started"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: nil)
        XCTAssertEqual(item.recommendation, .review)
        XCTAssertTrue(item.operatorActionRequired)
    }

    func testSharedInfrastructureNeverGetsAutomaticDisableRecommendation() {
        let component = makeComponent(
            name: "Agent Runtime",
            identifier: "com.example.agent-runtime",
            kind: .launchDaemon,
            path: nil,
            associatedProduct: "Agent Runtime",
            confidence: .high,
            status: "enabled"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: nil)
        XCTAssertNotEqual(item.recommendation, .disableIfUnused)
        XCTAssertTrue(item.recommendation == .review || item.recommendation == .keepEnabled)
    }

    func testNoTCCDatabaseCommandIsPartOfSecurityAuditSources() {
        let commands = SecurityControlScanner.commandSpecifications
        let flattened = commands.map { $0.executable + " " + $0.arguments.joined(separator: " ") }.joined(separator: "\n").lowercased()
        XCTAssertFalse(flattened.contains("tcc.db"))
        XCTAssertFalse(flattened.contains("sqlite"))
        XCTAssertFalse(flattened.contains("tccutil"))
        XCTAssertEqual(commands.count, 6)
    }

    func testCommandFailureDegradesToUnavailableInsteadOfFailingAudit() {
        let controls = SecurityControlScanner(commandRunner: FailingSecurityRunner()).scan()
        XCTAssertEqual(controls.items.count, 6)
        XCTAssertTrue(controls.items.allSatisfy { $0.currentState == .unknown })
        XCTAssertTrue(controls.sources.allSatisfy { $0.status == .unavailable })
    }

    func testTCCVisibilityIsExplicitlyUnsupported() {
        let report = BackgroundSecurityAuditor.makeTCCUnsupportedSource()
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertTrue(report.detail.lowercased().contains("public"))
    }

    func testHomebrewRunningServiceIsOnlyDisableIfUnused() {
        let component = makeComponent(
            name: "database",
            identifier: "database",
            kind: .homebrewService,
            path: nil,
            associatedProduct: "database",
            confidence: .high,
            status: "started"
        )
        let item = SecurityRecommendationPolicy.background(component, executableExists: nil)
        XCTAssertEqual(item.recommendation, .disableIfUnused)
        XCTAssertTrue(item.operatorActionRequired)
    }

    func testRecommendationNeverEntersStorageCleanupCandidates() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-care-security-cleanup-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let launchRoot = home.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at: launchRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let launchPath = launchRoot.appendingPathComponent("com.example.audit.plist")
        try Data("synthetic".utf8).write(to: launchPath)
        let component = makeComponent(name: "Audit Agent", identifier: "com.example.audit", kind: .launchAgent, path: launchPath.path, associatedProduct: nil, confidence: nil, status: "enabled")
        _ = SecurityRecommendationPolicy.background(component, executableExists: true)
        let cleanup = try StorageScanner(privacyPolicy: PrivacyPolicy(homeDirectory: home), homeDirectory: home).candidates()
        XCTAssertFalse(cleanup.contains { $0.displayPath == launchPath.path })
    }

    func testAuditSummaryCountsRecommendationKinds() {
        let items = [
            SecurityRecommendationPolicy.securityControl(.gatekeeper, state: .enabled),
            SecurityRecommendationPolicy.securityControl(.sip, state: .disabled),
            SecurityRecommendationPolicy.securityControl(.firewallStealthMode, state: .disabled),
        ]
        let summary = BackgroundSecurityAuditSummary(items: items)
        XCTAssertEqual(summary.keepEnabledCount, 1)
        XCTAssertEqual(summary.enableRecommendedCount, 1)
        XCTAssertEqual(summary.noActionCount, 1)
    }
}

private struct FailingSecurityRunner: InventoryCommandRunning {
    func run(executable: String, arguments: [String]) throws -> String {
        throw MacCareError.commandFailed("synthetic failure")
    }
}
private func makeComponent(
    name: String,
    identifier: String,
    kind: InstalledSoftwareComponentKind,
    path: String?,
    associatedProduct: String?,
    confidence: SoftwareAssociationConfidence?,
    status: String?,
    subtype: String? = nil
) -> InstalledSoftwareComponent {
    InstalledSoftwareComponent(
        displayName: name,
        identifier: identifier,
        vendorIdentifier: nil,
        kind: kind,
        path: path,
        version: nil,
        source: source(for: kind),
        associatedProduct: associatedProduct,
        associationConfidence: confidence,
        executionStatus: status,
        cleanupDisposition: .review,
        componentSubtype: subtype
    )
}

private func source(for kind: InstalledSoftwareComponentKind) -> InstalledSoftwareInventorySource {
    switch kind {
    case .launchAgent:
        return .userLaunchAgents
    case .launchDaemon:
        return .launchDaemons
    case .loginOrBackgroundItem:
        return .loginBackgroundItems
    case .systemExtension:
        return .systemExtensions
    case .homebrewService:
        return .homebrewServices
    case .application, .nestedApplication:
        return .applications
    case .helper:
        return .applicationSupport
    case .homebrewFormula:
        return .homebrewFormulae
    case .homebrewCask:
        return .homebrewCasks
    }
}
