import Foundation

public actor MacCareService {
    private let privacyPolicy: PrivacyPolicy
    private let planStore: CleanupPlanStore

    public init() {
        let policy = PrivacyPolicy()
        self.privacyPolicy = policy
        self.planStore = CleanupPlanStore(ttl: 1800)
    }

    public func healthCheck() throws -> HealthSnapshot { try HealthScanner().scan() }
    public func storageScan() throws -> StorageScanReport { try StorageScanner(privacyPolicy: privacyPolicy).report() }
    public func processScan(limit: Int = 50) throws -> [ProcessSnapshot] { try ProcessScanner().scan(limit: limit) }
    public func applications(limit: Int = 250) -> [ApplicationSnapshot] { ApplicationScanner(privacyPolicy: privacyPolicy).scan(limit: limit) }
    public func appScan(limit: Int = 250) -> InstalledSoftwareInventoryReport {
        InstalledSoftwareInventoryScanner(privacyPolicy: privacyPolicy).scan(limit: limit)
    }
    public func brewScan() -> BrewSnapshot { HomebrewScanner(privacyPolicy: privacyPolicy).scan() }
    public func securityAudit() -> BackgroundSecurityAuditReport {
        BackgroundSecurityAuditor(privacyPolicy: privacyPolicy).audit()
    }

    public func cleanupPlan(maxCandidates: Int = 200) async throws -> CleanupPlan {
        var candidates = try StorageScanner(privacyPolicy: privacyPolicy).candidates(maxCandidates: maxCandidates)
        candidates.append(contentsOf: HomebrewScanner(privacyPolicy: privacyPolicy).cleanupCandidates())
        return await planStore.issue(candidates: Array(candidates.prefix(maxCandidates)))
    }

    public func cleanupExecute(planID: String, candidateIDs: [String], allowReview: Bool = false) async throws -> [CleanupExecutionResult] {
        try await CleanupExecutor(store: planStore, privacyPolicy: privacyPolicy).execute(planID: planID, candidateIDs: candidateIDs, allowReview: allowReview)
    }

    public func privacySelfTest() -> PrivacySelfTestReport { PrivacySelfTester().run() }
}
