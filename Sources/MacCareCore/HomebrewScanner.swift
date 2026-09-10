import Foundation

public struct HomebrewScanner: Sendable {
    private let privacyPolicy: PrivacyPolicy
    public init(privacyPolicy: PrivacyPolicy = PrivacyPolicy()) { self.privacyPolicy = privacyPolicy }

    public func scan() -> BrewSnapshot {
        guard let brew = BrewCommandRunner() else { return .init(available: false, version: nil, outdatedFormulae: [], outdatedCasks: [], cleanupPreview: [], unusedDependencies: [], cacheBytes: nil) }
        let version = (try? brew.run(.version).split(separator: "\n").first.map(String.init)) ?? nil
        let outdated = parseOutdated((try? brew.run(.outdated)) ?? "")
        let cleanup = lines((try? brew.run(.cleanupDryRun)) ?? "", limit: 200)
        let unused = lines((try? brew.run(.autoremoveDryRun)) ?? "", limit: 200)
        var cacheBytes: Int64? = nil
        if let cachePath = try? brew.run(.cachePath).trimmingCharacters(in: .whitespacesAndNewlines), !cachePath.isEmpty {
            let url = URL(fileURLWithPath: cachePath)
            if privacyPolicy.decision(for: url) == .allowed { cacheBytes = try? DirectoryDiskUsage().size(of: url) }
        }
        return .init(available: true, version: version, outdatedFormulae: outdated.formulae, outdatedCasks: outdated.casks, cleanupPreview: cleanup, unusedDependencies: unused, cacheBytes: cacheBytes)
    }

    func cleanupCandidates() -> [PlannedCleanupCandidate] {
        guard let brew = BrewCommandRunner() else { return [] }
        var result: [PlannedCleanupCandidate] = []
        let cleanupPreview = lines((try? brew.run(.cleanupDryRun)) ?? "", limit: 200)
        if !cleanupPreview.isEmpty {
            result.append(.init(category: "Homebrew cleanup", displayPath: "Homebrew managed cache/old versions", estimatedBytes: 0, reason: "Homebrew reports cleanup candidates via --dry-run", risk: .safe, proposedAction: "Run trusted `brew cleanup`", target: .brewCleanup))
        }
        let unused = lines((try? brew.run(.autoremoveDryRun)) ?? "", limit: 200)
        if !unused.isEmpty {
            result.append(.init(category: "Homebrew unused dependencies", displayPath: "Homebrew managed formulae", estimatedBytes: 0, reason: "Homebrew reports dependencies no longer required", risk: .review, proposedAction: "Run trusted `brew autoremove` after explicit human review", target: .brewAutoremove))
        }
        return result
    }

    private func lines(_ text: String, limit: Int) -> [String] {
        text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(limit).map { $0 }
    }

    private func parseOutdated(_ text: String) -> (formulae: [String], casks: [String]) {
        struct Entry: Decodable { let name: String }
        struct Payload: Decodable { let formulae: [Entry]; let casks: [Entry] }
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return ([], []) }
        return (payload.formulae.map(\.name), payload.casks.map(\.name))
    }
}
