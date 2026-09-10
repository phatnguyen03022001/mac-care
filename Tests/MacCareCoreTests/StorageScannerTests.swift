import XCTest
@testable import MacCareCore

final class StorageScannerTests: XCTestCase {
    func testProtectedPhotosLogIsNeverEmittedAsCleanupCandidate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-storage-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let photosLog = home.appendingPathComponent("Library/Logs/PhotosSearch.aapbz")
        let ordinaryLog = home.appendingPathComponent("Library/Logs/CompilerLogs")
        try FileManager.default.createDirectory(at: photosLog, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ordinaryLog, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: photosLog.appendingPathComponent("synthetic.log"))
        try Data(repeating: 0x42, count: 4096).write(to: ordinaryLog.appendingPathComponent("synthetic.log"))
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = PrivacyPolicy(homeDirectory: home)
        let candidates = try StorageScanner(privacyPolicy: policy, homeDirectory: home).candidates()
        let names = Set(candidates.map { URL(fileURLWithPath: $0.displayPath).lastPathComponent })

        XCTAssertFalse(names.contains("PhotosSearch.aapbz"))
        XCTAssertTrue(names.contains("CompilerLogs"))
    }

    func testExactNpmCacheUsesDirectoryDiskUsageSemantics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-npm-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let cache = home.appendingPathComponent(".npm/_cacache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let source = cache.appendingPathComponent("content.bin")
        let hardLink = cache.appendingPathComponent("content-link.bin")
        try Data(repeating: 0x45, count: 8192).write(to: source)
        try FileManager.default.linkItem(at: source, to: hardLink)
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = PrivacyPolicy(homeDirectory: home)
        let candidates = try StorageScanner(privacyPolicy: policy, homeDirectory: home).candidates()
        let candidate = try XCTUnwrap(candidates.first(where: { $0.category == "npm cache" }))
        let expected = try DirectoryDiskUsage().size(of: cache)

        XCTAssertEqual(candidate.estimatedBytes, expected)
    }

    func testExactPnpmStoreUsesDirectoryDiskUsageSemantics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-pnpm-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let store = home.appendingPathComponent("Library/pnpm/store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let source = store.appendingPathComponent("content.bin")
        let hardLink = store.appendingPathComponent("content-link.bin")
        try Data(repeating: 0x43, count: 8192).write(to: source)
        try FileManager.default.linkItem(at: source, to: hardLink)
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = PrivacyPolicy(homeDirectory: home)
        let candidates = try StorageScanner(privacyPolicy: policy, homeDirectory: home).candidates()
        let candidate = try XCTUnwrap(candidates.first(where: { $0.category == "pnpm store" }))
        let expected = try DirectoryDiskUsage().size(of: store)

        XCTAssertEqual(candidate.estimatedBytes, expected)
    }

    func testTrustedDirectoryUsageDoesNotFollowProtectedChildSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-npm-child-link-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let cache = home.appendingPathComponent(".npm/_cacache")
        let protected = root.appendingPathComponent("Vault.photoslibrary")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try Data(repeating: 0x46, count: 4096).write(to: cache.appendingPathComponent("local.bin"))
        try Data(repeating: 0x47, count: 1_048_576).write(to: protected.appendingPathComponent("protected.bin"))
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("protected-link"), withDestinationURL: protected)
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = PrivacyPolicy(homeDirectory: home)
        let candidates = try StorageScanner(privacyPolicy: policy, homeDirectory: home).candidates()
        let candidate = try XCTUnwrap(candidates.first(where: { $0.category == "npm cache" }))
        let protectedBytes = try DirectoryDiskUsage().size(of: protected)

        XCTAssertLessThan(candidate.estimatedBytes, protectedBytes)
    }

    func testExactTrustedRootSymlinkIntoPhotosLibraryIsNotCandidate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-pnpm-link-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let protected = root.appendingPathComponent("Vault.photoslibrary")
        let store = home.appendingPathComponent("Library/pnpm/store")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x44, count: 4096).write(to: protected.appendingPathComponent("synthetic.bin"))
        try FileManager.default.createSymbolicLink(at: store, withDestinationURL: protected)
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = PrivacyPolicy(homeDirectory: home)
        let candidates = try StorageScanner(privacyPolicy: policy, homeDirectory: home).candidates()
        XCTAssertFalse(candidates.contains(where: { $0.category == "pnpm store" }))
    }
}
