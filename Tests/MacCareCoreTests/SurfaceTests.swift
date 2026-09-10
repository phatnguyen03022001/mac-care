import XCTest
@testable import MacCareCore

final class SurfaceTests: XCTestCase {
    func testMCPToolCatalogContainsOnlySemanticTools() {
        XCTAssertEqual(Set(MCPToolCatalog.names), Set(["health_check", "storage_scan", "process_scan", "app_scan", "brew_scan", "cleanup_plan", "cleanup_execute", "privacy_self_test"]))
        let forbidden = ["shell", "exec", "read_file", "delete", "rm", "find", "run_script"]
        XCTAssertTrue(forbidden.allSatisfy { !MCPToolCatalog.names.contains($0) })
    }

    func testProcessOutputHasNoEnvironmentOrArguments() throws {
        let rows = try ProcessScanner().scan(limit: 5)
        let json = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("environment"))
        XCTAssertFalse(json.contains("commandline"))
        XCTAssertFalse(json.contains("arguments"))
    }

    func testFixedCommandRunnerUsesIsolatedNullStandardInput() throws {
        let type = try FixedCommandRunner().run(
            executable: "/usr/bin/stat",
            arguments: ["-f", "%HT", "/dev/fd/0"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(type, "Character Device")
    }

    func testDirectoryDiskUsageMeasuresSyntheticFixture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-du-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: root.appendingPathComponent("cache.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = try DirectoryDiskUsage().size(of: root)
        XCTAssertGreaterThan(bytes, 0)
    }
}
