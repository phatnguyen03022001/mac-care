import Foundation

enum SecurityRecommendationPolicy {
    static func securityControl(_ control: SecurityControlKind, state: SecurityControlState) -> SecurityControlAuditItem {
        switch state {
        case .unknown, .unsupported:
            return .init(item: displayName(control), category: control, currentState: state, recommendation: .unknown, reason: "The public status source did not provide a reliable state.", confidence: .low, operatorActionRequired: false)
        case .enabled:
            return enabledControl(control)
        case .disabled:
            return disabledControl(control)
        }
    }

    static func background(_ component: InstalledSoftwareComponent, executableExists: Bool?) -> BackgroundSecurityRecommendationItem {
        let state = normalizedState(component.executionStatus)
        if component.cleanupDisposition == .protected {
            return item(component, recommendation: .review, reason: "Protected software metadata cannot receive an automatic lifecycle recommendation.", confidence: .high)
        }
        if isSharedInfrastructure(component) {
            return item(component, recommendation: .review, reason: "Shared execution infrastructure should not be disabled through maintenance heuristics; review only if its ownership or use changes.", confidence: .high)
        }
        if executableExists == false, component.associatedProduct == nil {
            return item(component, recommendation: .review, reason: "Executable is missing and no parent product is identified; this may be a stale or orphaned startup item.", confidence: .high)
        }
        if component.kind == .homebrewService {
            if isInactive(state) { return item(component, recommendation: .noAction, reason: "Homebrew service is not currently running.", confidence: .high) }
            return item(component, recommendation: .disableIfUnused, reason: "Running Homebrew service consumes background resources; disable only if the associated software is unused.", confidence: .medium)
        }
        if isInactive(state) {
            return item(component, recommendation: .noAction, reason: "Background item is already inactive or disabled; no automatic change is recommended.", confidence: .high)
        }
        if isUpdaterOrUninstaller(component), component.associatedProduct != nil {
            return item(component, recommendation: .disableIfUnused, reason: "Updater/uninstaller background item is tied to an installed product; disable only if that background function is unused.", confidence: .medium)
        }
        if component.associatedProduct != nil {
            return item(component, recommendation: .review, reason: "Background component belongs to an installed product; keep it when the product is in use and review before changing startup behavior.", confidence: .medium)
        }
        return item(component, recommendation: .review, reason: "Background component ownership or necessity is not sufficiently clear for an automatic recommendation.", confidence: .low)
    }

    static func extensions(_ components: [InstalledSoftwareComponent]) -> [BackgroundSecurityRecommendationItem] {
        let activeNetwork = components.filter { $0.componentSubtype == "network_extension" && isActive(normalizedState($0.executionStatus)) }
        let networkProducts = Set(activeNetwork.compactMap { $0.associatedProduct ?? $0.vendorIdentifier ?? $0.identifier })
        let multipleNetworkStacks = networkProducts.count > 1

        return components.map { component in
            if component.cleanupDisposition == .protected {
                return item(component, recommendation: .review, reason: "Protected extension metadata cannot receive an automatic lifecycle recommendation.", confidence: .high)
            }
            let subtype = component.componentSubtype ?? "system_extension"
            let state = normalizedState(component.executionStatus)
            if subtype == "endpoint_security" {
                if component.associatedProduct != nil, component.associationConfidence == .high, isActive(state) {
                    return item(component, recommendation: .keepEnabled, reason: "Active endpoint-security component is strongly associated with an installed security product; disabling it may reduce protection.", confidence: .high)
                }
                return item(component, recommendation: .review, reason: "Endpoint-security extension affects host protection and requires operator review before any lifecycle change.", confidence: .high)
            }
            if subtype == "network_extension" {
                let reason = multipleNetworkStacks ? "Multiple active network extensions coexist. Coexistence is not proof of conflict; review which network/VPN products are actually used." : "Network extension can affect VPN, filtering, or firewall behavior; review before changing it."
                return item(component, recommendation: .review, reason: reason, confidence: .high)
            }
            if component.associatedProduct != nil, component.associationConfidence == .high, isActive(state) {
                return item(component, recommendation: .keepEnabled, reason: "Active system extension is strongly associated with an installed product; keep enabled while that product is in use.", confidence: .medium)
            }
            return item(component, recommendation: .review, reason: "Third-party system extension requires operator review before any lifecycle change.", confidence: .medium)
        }
    }
    private static func enabledControl(_ control: SecurityControlKind) -> SecurityControlAuditItem {
        switch control {
        case .gatekeeper, .fileVault, .sip, .firewall:
            return .init(item: displayName(control), category: control, currentState: .enabled, recommendation: .keepEnabled, reason: "This macOS security control is enabled and should normally remain enabled.", confidence: .high, operatorActionRequired: false)
        case .firewallStealthMode:
            return .init(item: displayName(control), category: control, currentState: .enabled, recommendation: .keepEnabled, reason: "Stealth mode is optional hardening and is already enabled.", confidence: .medium, operatorActionRequired: false)
        case .firewallBlockAll:
            return .init(item: displayName(control), category: control, currentState: .enabled, recommendation: .review, reason: "Block-all mode is intentionally restrictive; keep it only when that behavior is desired.", confidence: .medium, operatorActionRequired: true)
        }
    }

    private static func disabledControl(_ control: SecurityControlKind) -> SecurityControlAuditItem {
        switch control {
        case .gatekeeper, .fileVault, .sip, .firewall:
            return .init(item: displayName(control), category: control, currentState: .disabled, recommendation: .enableRecommended, reason: "This important macOS security control is disabled; enabling it is recommended unless the operator has a deliberate exception.", confidence: .high, operatorActionRequired: true)
        case .firewallStealthMode:
            return .init(item: displayName(control), category: control, currentState: .disabled, recommendation: .noAction, reason: "Stealth mode is optional hardening; disabled state alone is not treated as a defect.", confidence: .medium, operatorActionRequired: false)
        case .firewallBlockAll:
            return .init(item: displayName(control), category: control, currentState: .disabled, recommendation: .noAction, reason: "Block-all mode is optional and normally remains disabled unless a deliberately restrictive firewall policy is required.", confidence: .high, operatorActionRequired: false)
        }
    }

    private static func displayName(_ control: SecurityControlKind) -> String {
        switch control {
        case .gatekeeper: return "Gatekeeper"
        case .fileVault: return "FileVault"
        case .sip: return "System Integrity Protection"
        case .firewall: return "Application Firewall"
        case .firewallStealthMode: return "Firewall Stealth Mode"
        case .firewallBlockAll: return "Firewall Block-All Mode"
        }
    }
    private static func item(_ component: InstalledSoftwareComponent, recommendation: BackgroundSecurityRecommendation, reason: String, confidence: RecommendationConfidence) -> BackgroundSecurityRecommendationItem {
        .init(
            item: component.displayName,
            category: component.kind.rawValue,
            currentState: normalizedState(component.executionStatus),
            recommendation: recommendation,
            reason: reason,
            confidence: confidence,
            operatorActionRequired: recommendation == .disableIfUnused || recommendation == .enableRecommended || recommendation == .review,
            associatedProduct: component.associatedProduct,
            identifier: component.identifier,
            source: component.source,
            componentSubtype: component.componentSubtype
        )
    }

    private static func normalizedState(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "UNKNOWN" : String(trimmed.prefix(160))
    }

    private static func isActive(_ state: String) -> Bool {
        let value = state.lowercased()
        return value.contains("enabled") || value.contains("active") || value.contains("started") || value.contains("running")
    }

    private static func isInactive(_ state: String) -> Bool {
        let value = state.lowercased()
        return value.contains("disabled") || value == "none" || value.contains("stopped") || value.contains("inactive")
    }
    private static func isUpdaterOrUninstaller(_ component: InstalledSoftwareComponent) -> Bool {
        let value = [component.displayName, component.identifier ?? "", component.path ?? ""].joined(separator: " ").lowercased()
        return value.contains("updater") || value.contains("update helper") || value.contains("uninstall")
    }

    private static func isSharedInfrastructure(_ component: InstalledSoftwareComponent) -> Bool {
        let value = [component.displayName, component.associatedProduct ?? "", component.identifier ?? ""].joined(separator: " ").lowercased()
        let protectedNames = ["agent runtime", "remote desktop commander", "desktop commander", "secure tunnel", "cloudflared", "orbstack", "docker", "containerd", "kubernetes"]
        return protectedNames.contains(where: value.contains)
    }
}
