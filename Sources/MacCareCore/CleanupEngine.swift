import Foundation

actor CleanupPlanStore {
    private struct StoredPlan: Sendable { let createdAt: Date; let expiresAt: Date; let candidates: [String: PlannedCleanupCandidate] }
    private let ttl: TimeInterval
    private var plans: [String: StoredPlan] = [:]

    init(ttl: TimeInterval = 1800) { self.ttl = ttl }

    func issue(candidates: [PlannedCleanupCandidate]) -> CleanupPlan {
        let planID = UUID().uuidString
        let now = Date(); let expires = now.addingTimeInterval(ttl)
        plans[planID] = StoredPlan(createdAt: now, expiresAt: expires, candidates: Dictionary(uniqueKeysWithValues: candidates.map { ($0.candidateID, $0) }))
        return CleanupPlan(planID: planID, createdAt: now, expiresAt: expires, candidates: candidates.map(\.summary))
    }

    func resolve(planID: String, candidateIDs: [String]) throws -> [PlannedCleanupCandidate] {
        guard let plan = plans[planID] else { throw MacCareError.invalidPlan }
        guard Date() <= plan.expiresAt else { plans.removeValue(forKey: planID); throw MacCareError.stalePlan }
        var resolved: [PlannedCleanupCandidate] = []
        for id in candidateIDs {
            guard let candidate = plan.candidates[id] else { throw MacCareError.unknownCandidate }
            resolved.append(candidate)
        }
        return resolved
    }
}

struct CleanupExecutor: Sendable {
    let store: CleanupPlanStore
    let privacyPolicy: PrivacyPolicy
    func execute(planID: String, candidateIDs: [String], allowReview: Bool) async throws -> [CleanupExecutionResult] {
        let fileManager = FileManager.default
        let candidates = try await store.resolve(planID: planID, candidateIDs: candidateIDs)
        var results: [CleanupExecutionResult] = []
        for candidate in candidates {
            guard candidate.risk != .protected else { throw MacCareError.protectedPath }
            if candidate.risk == .review && !allowReview { throw MacCareError.reviewRequiresHumanApproval }
            switch candidate.target {
            case .file(let url):
                try privacyPolicy.requireAllowed(url)
                if candidate.risk == .review {
                    guard fileManager.fileExists(atPath: url.path) else { results.append(.init(candidateID: candidate.candidateID, success: true, message: "Already absent")); continue }
                    _ = try fileManager.trashItem(at: url, resultingItemURL: nil)
                } else if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                let gone = !fileManager.fileExists(atPath: url.path)
                results.append(.init(candidateID: candidate.candidateID, success: gone, message: gone ? "Verified removed" : "Verification failed"))
            case .brewCleanup:
                guard let brew = BrewCommandRunner() else { throw MacCareError.commandFailed("Homebrew not found") }
                _ = try brew.run(.cleanup)
                results.append(.init(candidateID: candidate.candidateID, success: true, message: "Homebrew cleanup completed"))
            case .brewAutoremove:
                guard allowReview else { throw MacCareError.reviewRequiresHumanApproval }
                guard let brew = BrewCommandRunner() else { throw MacCareError.commandFailed("Homebrew not found") }
                _ = try brew.run(.autoremove)
                results.append(.init(candidateID: candidate.candidateID, success: true, message: "Homebrew autoremove completed"))
            }
        }
        return results
    }
}
