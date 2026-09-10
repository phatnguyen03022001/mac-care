import XCTest
@testable import MacCareCore

final class CleanupSecurityTests: XCTestCase {
    func testTamperedCandidateIDFailsClosed() async throws {
        let store = CleanupPlanStore(ttl: 600)
        let plan = await store.issue(candidates: [])
        let executor = CleanupExecutor(store: store, privacyPolicy: PrivacyPolicy())
        await XCTAssertThrowsErrorAsync { _ = try await executor.execute(planID: plan.planID, candidateIDs: ["forged"], allowReview: false) }
    }

    func testStalePlanFailsClosed() async throws {
        let store = CleanupPlanStore(ttl: -1)
        let plan = await store.issue(candidates: [])
        await XCTAssertThrowsErrorAsync { _ = try await store.resolve(planID: plan.planID, candidateIDs: []) }
    }

    func testProtectedCandidateCannotExecute() async throws {
        let store = CleanupPlanStore(ttl: 600)
        let candidate = PlannedCleanupCandidate(category: "test", displayPath: "synthetic.photoslibrary", estimatedBytes: 1, reason: "test", risk: .protected, proposedAction: "none", target: .file(URL(fileURLWithPath: "/tmp/synthetic.photoslibrary")))
        let plan = await store.issue(candidates: [candidate])
        let executor = CleanupExecutor(store: store, privacyPolicy: PrivacyPolicy(homeDirectory: URL(fileURLWithPath: "/tmp/home")))
        await XCTAssertThrowsErrorAsync { _ = try await executor.execute(planID: plan.planID, candidateIDs: [plan.candidates[0].candidateID], allowReview: true) }
    }


    func testPhotosRelatedSafeCandidateIsRevalidatedAndRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-photos-log-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let photosLog = home.appendingPathComponent("Library/Logs/PhotosSearch.aapbz")
        let fixture = photosLog.appendingPathComponent("synthetic.log")
        try FileManager.default.createDirectory(at: photosLog, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CleanupPlanStore(ttl: 600)
        let candidate = PlannedCleanupCandidate(category: "User logs", displayPath: photosLog.path, estimatedBytes: 9, reason: "synthetic", risk: .safe, proposedAction: "delete", target: .file(photosLog))
        let plan = await store.issue(candidates: [candidate])
        let executor = CleanupExecutor(store: store, privacyPolicy: PrivacyPolicy(homeDirectory: home))

        await XCTAssertThrowsErrorAsync {
            _ = try await executor.execute(planID: plan.planID, candidateIDs: [candidate.candidateID], allowReview: false)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    func testSafeCandidateExecutesOnlyIssuedSyntheticFixture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-safe-\(UUID().uuidString)")
        let fixture = root.appendingPathComponent("cache.bin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CleanupPlanStore(ttl: 600)
        let candidate = PlannedCleanupCandidate(category: "test-cache", displayPath: fixture.path, estimatedBytes: 9, reason: "synthetic fixture", risk: .safe, proposedAction: "delete", target: .file(fixture))
        let plan = await store.issue(candidates: [candidate])
        let executor = CleanupExecutor(store: store, privacyPolicy: PrivacyPolicy(homeDirectory: root.appendingPathComponent("home")))
        let results = try await executor.execute(planID: plan.planID, candidateIDs: [candidate.candidateID], allowReview: false)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.path))
    }

    func testReviewCandidateRequiresExplicitApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-review-\(UUID().uuidString)")
        let fixture = root.appendingPathComponent("review.bin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CleanupPlanStore(ttl: 600)
        let candidate = PlannedCleanupCandidate(category: "review", displayPath: fixture.path, estimatedBytes: 9, reason: "synthetic fixture", risk: .review, proposedAction: "trash", target: .file(fixture))
        let plan = await store.issue(candidates: [candidate])
        let executor = CleanupExecutor(store: store, privacyPolicy: PrivacyPolicy(homeDirectory: root.appendingPathComponent("home")))

        await XCTAssertThrowsErrorAsync { _ = try await executor.execute(planID: plan.planID, candidateIDs: [candidate.candidateID], allowReview: false) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }
}

private func XCTAssertThrowsErrorAsync(_ expression: @escaping () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { }
}
