import Foundation

struct SecurityControlCommandSpecification: Sendable {
    let control: SecurityControlKind
    let executable: String
    let arguments: [String]
}

enum SecurityControlParser {
    static func gatekeeper(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["assessments enabled"], disabled: ["assessments disabled"])
    }

    static func fileVault(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["filevault is on"], disabled: ["filevault is off"])
    }

    static func sip(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["status: enabled"], disabled: ["status: disabled"])
    }

    static func firewall(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["firewall is enabled", "state = 1"], disabled: ["firewall is disabled", "state = 0"])
    }

    static func firewallStealth(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["stealth mode is on", "stealth mode enabled"], disabled: ["stealth mode is off", "stealth mode disabled"])
    }
    static func firewallBlockAll(_ text: String) -> SecurityControlState {
        parse(text, enabled: ["block all state set to enabled", "block all is enabled"], disabled: ["block all state set to disabled", "block all is disabled"])
    }

    private static func parse(_ text: String, enabled: [String], disabled: [String]) -> SecurityControlState {
        let normalized = text.lowercased()
        if disabled.contains(where: normalized.contains) { return .disabled }
        if enabled.contains(where: normalized.contains) { return .enabled }
        return .unknown
    }
}

struct SecurityControlScanner: Sendable {
    let commandRunner: any InventoryCommandRunning

    init(commandRunner: any InventoryCommandRunning = FixedCommandRunner()) {
        self.commandRunner = commandRunner
    }

    static let commandSpecifications: [SecurityControlCommandSpecification] = [
        .init(control: .gatekeeper, executable: "/usr/sbin/spctl", arguments: ["--status"]),
        .init(control: .fileVault, executable: "/usr/bin/fdesetup", arguments: ["status"]),
        .init(control: .sip, executable: "/usr/bin/csrutil", arguments: ["status"]),
        .init(control: .firewall, executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"]),
        .init(control: .firewallStealthMode, executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getstealthmode"]),
        .init(control: .firewallBlockAll, executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getblockall"]),
    ]
    func scan() -> SecurityControlScanResult {
        var items: [SecurityControlAuditItem] = []
        var sources: [SecurityAuditSourceStatus] = []

        for specification in Self.commandSpecifications {
            do {
                let output = try commandRunner.run(executable: specification.executable, arguments: specification.arguments)
                let state = parse(output, for: specification.control)
                items.append(SecurityRecommendationPolicy.securityControl(specification.control, state: state))
                sources.append(.init(
                    source: specification.control.rawValue,
                    status: state == .unknown ? .partial : .available,
                    detail: state == .unknown ? "Public command output was not recognized." : "Read from a fixed public macOS status command."
                ))
            } catch {
                items.append(SecurityRecommendationPolicy.securityControl(specification.control, state: .unknown))
                sources.append(.init(
                    source: specification.control.rawValue,
                    status: .unavailable,
                    detail: "Public macOS status command was unavailable or failed."
                ))
            }
        }
        return .init(items: items, sources: sources)
    }

    private func parse(_ output: String, for control: SecurityControlKind) -> SecurityControlState {
        switch control {
        case .gatekeeper:
            return SecurityControlParser.gatekeeper(output)
        case .fileVault:
            return SecurityControlParser.fileVault(output)
        case .sip:
            return SecurityControlParser.sip(output)
        case .firewall:
            return SecurityControlParser.firewall(output)
        case .firewallStealthMode:
            return SecurityControlParser.firewallStealth(output)
        case .firewallBlockAll:
            return SecurityControlParser.firewallBlockAll(output)
        }
    }
}
