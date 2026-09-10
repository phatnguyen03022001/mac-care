import XCTest
@testable import MacCareCore

final class ApplicationScannerSizingTests: XCTestCase {
    func testAuthorizedApplicationReceivesMeasuredApproximateSize() throws {
        let fixture = try ApplicationSizingFixture()
        defer { fixture.cleanup() }
        try fixture.makeApp(named: "Measured.app")

        let apps = ApplicationScanner(
            privacyPolicy: fixture.policy,
            roots: [fixture.applications],
            diskUsage: FixedApplicationDiskUsage(result: .success(12_288))
        ).scan(limit: 10)

        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(app.approximateBytes, 12_288)
    }

    func testRootApplicationSymlinkIsSkipped() throws {
        let fixture = try ApplicationSizingFixture()
        defer { fixture.cleanup() }
        let target = fixture.root.appendingPathComponent("Real.app")
        try fixture.makeBundle(at: target)
        try FileManager.default.createSymbolicLink(
            at: fixture.applications.appendingPathComponent("Linked.app"),
            withDestinationURL: target
        )

        let apps = ApplicationScanner(
            privacyPolicy: fixture.policy,
            roots: [fixture.applications],
            diskUsage: FixedApplicationDiskUsage(result: .success(99_999))
        ).scan(limit: 10)
        XCTAssertTrue(apps.isEmpty)
    }

    func testProtectedApplicationRootIsNeverInventoriedOrSized() throws {
        let fixture = try ApplicationSizingFixture()
        defer { fixture.cleanup() }
        let protectedRoot = fixture.home.appendingPathComponent("Library/Caches/com.apple.Photos")
        try FileManager.default.createDirectory(at: protectedRoot, withIntermediateDirectories: true)
        try fixture.makeBundle(at: protectedRoot.appendingPathComponent("ShouldNotAppear.app"))

        let apps = ApplicationScanner(
            privacyPolicy: fixture.policy,
            roots: [protectedRoot],
            diskUsage: FixedApplicationDiskUsage(result: .success(88_888))
        ).scan(limit: 10)
        XCTAssertTrue(apps.isEmpty)
    }

    func testSizingFailureKeepsApplicationWithZeroApproximateSize() throws {
        let fixture = try ApplicationSizingFixture()
        defer { fixture.cleanup() }
        try fixture.makeApp(named: "StillVisible.app")

        let apps = ApplicationScanner(
            privacyPolicy: fixture.policy,
            roots: [fixture.applications],
            diskUsage: FixedApplicationDiskUsage(result: .failure(MacCareError.commandFailed("synthetic")))
        ).scan(limit: 10)

        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(app.name, "StillVisible")
        XCTAssertEqual(app.approximateBytes, 0)
    }

    func testMalformedDirectoryDiskUsageOutputIsRejected() {
        XCTAssertThrowsError(
            try DirectoryDiskUsage.parseKiB(Data("not-a-size\t/tmp/Fake.app\n".utf8))
        )
    }
}

private struct FixedApplicationDiskUsage: ApplicationDiskUsageMeasuring {
    let result: Result<Int64, Error>
    func size(of directory: URL) throws -> Int64 { try result.get() }
}

private final class ApplicationSizingFixture {
    let root: URL
    let home: URL
    let applications: URL
    let policy: PrivacyPolicy

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-care-app-size-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        applications = root.appendingPathComponent("Applications")
        policy = PrivacyPolicy(homeDirectory: home)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    func makeApp(named name: String) throws {
        try makeBundle(at: applications.appendingPathComponent(name))
    }

    func makeBundle(at url: URL) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundleIdentifier": "com.example.\(UUID().uuidString.lowercased())",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
