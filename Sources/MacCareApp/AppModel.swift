import Foundation
import MacCareCore

@MainActor
final class AppModel: ObservableObject {
    @Published var health: HealthSnapshot?
    @Published var storage: StorageScanReport?
    @Published var processes: [ProcessSnapshot] = []
    @Published var applications: [ApplicationSnapshot] = []
    @Published var brew: BrewSnapshot?
    @Published var cleanupPlan: CleanupPlan?
    @Published var privacyReport: PrivacySelfTestReport?
    @Published var executionResults: [CleanupExecutionResult] = []
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let service = MacCareService()

    func refreshAll() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            health = try await service.healthCheck()
            storage = try await service.storageScan()
            processes = try await service.processScan(limit: 50)
            applications = await service.applications(limit: 250)
            brew = await service.brewScan()
            cleanupPlan = try await service.cleanupPlan(maxCandidates: 200)
            privacyReport = await service.privacySelfTest()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func refreshHealth() async {
        do { health = try await service.healthCheck() }
        catch { errorMessage = safeMessage(for: error) }
    }

    func refreshCleanup() async {
        do {
            storage = try await service.storageScan()
            cleanupPlan = try await service.cleanupPlan(maxCandidates: 200)
        } catch { errorMessage = safeMessage(for: error) }
    }

    func refreshProcesses() async {
        do { processes = try await service.processScan(limit: 100) }
        catch { errorMessage = safeMessage(for: error) }
    }

    func refreshApplications() async {
        applications = await service.applications(limit: 250)
    }

    func refreshBrew() async {
        brew = await service.brewScan()
    }

    func refreshPrivacy() async {
        privacyReport = await service.privacySelfTest()
    }

    func execute(candidateIDs: Set<String>, allowReview: Bool) async {
        guard let plan = cleanupPlan else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            executionResults = try await service.cleanupExecute(
                planID: plan.planID,
                candidateIDs: Array(candidateIDs),
                allowReview: allowReview
            )
            await refreshCleanup()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    private func safeMessage(for error: Error) -> String {
        if let error = error as? MacCareError {
            return error.localizedDescription
        }
        return "Mac Care could not complete this operation."
    }
}
