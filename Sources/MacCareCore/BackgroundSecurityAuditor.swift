import Foundation

struct BackgroundSecurityAuditor: Sendable {
    private let privacyPolicy: PrivacyPolicy
    private let commandRunner: any InventoryCommandRunning

    init(
        privacyPolicy: PrivacyPolicy = PrivacyPolicy(),
        commandRunner: any InventoryCommandRunning = FixedCommandRunner()
    ) {
        self.privacyPolicy = privacyPolicy
        self.commandRunner = commandRunner
    }

    func audit() -> BackgroundSecurityAuditReport {
        let controls = SecurityControlScanner(commandRunner: commandRunner).scan()
        let inventory = InstalledSoftwareInventoryScanner(
            privacyPolicy: privacyPolicy,
            commandRunner: commandRunner
        ).scanForSecurityAudit(limit: 500)

        let backgroundKinds: Set<InstalledSoftwareComponentKind> = [
            .launchAgent, .launchDaemon, .loginOrBackgroundItem, .homebrewService,
        ]
        let backgroundComponents = inventory.components.filter { backgroundKinds.contains($0.kind) }
        let extensionComponents = inventory.components.filter { $0.kind == .systemExtension }

        let background = backgroundComponents.prefix(160).map { component in
            SecurityRecommendationPolicy.background(component, executableExists: executableExists(component))
        }
        let extensions = SecurityRecommendationPolicy.extensions(Array(extensionComponents.prefix(64)))
        let summary = BackgroundSecurityAuditSummary(
            securityControls: controls.items,
            backgroundRecommendations: Array(background),
            extensionRecommendations: extensions
        )

        var sources = controls.sources
        sources.append(Self.makeTCCUnsupportedSource())
        sources.append(contentsOf: inventory.sources.map(Self.mapInventorySource))
        if backgroundComponents.count > 160 {
            sources.append(.init(source: "BACKGROUND_RECOMMENDATIONS", status: .partial, detail: "Recommendation output capped at 160 background items."))
        }
        if extensionComponents.count > 64 {
            sources.append(.init(source: "EXTENSION_RECOMMENDATIONS", status: .partial, detail: "Recommendation output capped at 64 system extensions."))
        }

        return .init(
            securityControls: controls.items,
            backgroundRecommendations: Array(background),
            extensionRecommendations: extensions,
            summary: summary,
            sources: sources
        )
    }

    static func makeTCCUnsupportedSource() -> SecurityAuditSourceStatus {
        .init(
            source: "TCC_PRIVACY_PERMISSIONS",
            status: .unsupported,
            detail: "No stable public aggregate read-only interface is used; private TCC databases are intentionally not inspected."
        )
    }
    private func executableExists(_ component: InstalledSoftwareComponent) -> Bool? {
        guard let path = component.path, path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard privacyPolicy.decision(for: url) == .allowed else { return nil }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func mapInventorySource(_ source: InstalledSoftwareSourceStatus) -> SecurityAuditSourceStatus {
        let status: SecurityAuditSourceAvailability
        switch source.status {
        case .available:
            status = .available
        case .partial:
            status = .partial
        case .unavailable:
            status = .unavailable
        }
        return .init(
            source: "INVENTORY_\(source.source.rawValue.uppercased())",
            status: status,
            detail: source.detail ?? "Reused Installed Software Inventory source."
        )
    }
}
