import XCTest
@testable import MacCareCore

final class InstalledSoftwareInventoryTests: XCTestCase {
    private let fm = FileManager.default

    func testTopLevelAndNestedHiddenApplicationsAreDiscovered() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let main = fixture.applications.appendingPathComponent("Main.app")
        try fixture.makeBundle(at: main, name: "Main", identifier: "com.example.main", version: "1.2")
        let nested = main.appendingPathComponent("Contents/Library/LoginItems/.HiddenHelper.app")
        try fixture.makeBundle(at: nested, name: "Hidden Helper", identifier: "com.example.main.helper", version: "1")

        let report = fixture.scanner().scan(limit: 20)
        XCTAssertTrue(report.applications.contains { $0.name == "Main" && $0.bundleIdentifier == "com.example.main" })
        let helper = try XCTUnwrap(report.components.first { $0.identifier == "com.example.main.helper" })
        XCTAssertEqual(helper.kind, .nestedApplication)
        XCTAssertEqual(helper.associatedProduct, "Main")
        XCTAssertEqual(helper.associationConfidence, .high)
        XCTAssertNotEqual(helper.cleanupDisposition, .safe)
    }

    func testApplicationSupportHiddenBundleDiscoveredButOrdinaryDataIgnored() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let helper = fixture.userApplicationSupport.appendingPathComponent("Vendor/.HiddenSupport.bundle")
        try fixture.makeBundle(at: helper, name: "Hidden Support", identifier: "com.vendor.hidden", version: "2")
        try Data("ordinary data".utf8).write(to: fixture.userApplicationSupport.appendingPathComponent("notes.json"))

        let report = fixture.scanner().scan(limit: 20)
        XCTAssertTrue(report.components.contains { $0.identifier == "com.vendor.hidden" && $0.kind == .helper })
        XCTAssertFalse(report.components.contains { $0.path?.hasSuffix("notes.json") == true })
    }

    func testLaunchAgentAndDaemonExposeOnlyBoundedMetadata() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        try fixture.makeLaunchPlist(at: fixture.userLaunchAgents.appendingPathComponent("com.example.agent.plist"), label: "com.example.agent", programArguments: ["/tmp/example-agent", "--token", "DO_NOT_LEAK_SECRET"])
        try fixture.makeLaunchPlist(at: fixture.launchDaemons.appendingPathComponent("com.example.daemon.plist"), label: "com.example.daemon", program: "/tmp/example-daemon")

        let report = fixture.scanner().scan(limit: 20)
        XCTAssertTrue(report.components.contains { $0.identifier == "com.example.agent" && $0.kind == .launchAgent && $0.path == "/tmp/example-agent" })
        XCTAssertTrue(report.components.contains { $0.identifier == "com.example.daemon" && $0.kind == .launchDaemon && $0.path == "/tmp/example-daemon" })
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertFalse(json.contains("DO_NOT_LEAK_SECRET"))
        XCTAssertFalse(json.contains("--token"))
    }

    func testProtectedApplicationSupportSubtreeAndProtectedSymlinkArePruned() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let protectedChrome = fixture.userApplicationSupport.appendingPathComponent("Google/Chrome/SecretHelper.app")
        try fixture.makeBundle(at: protectedChrome, name: "Secret", identifier: "com.secret.should-not-appear", version: "1")
        let vault = fixture.root.appendingPathComponent("Vault.photoslibrary")
        try fixture.makeBundle(at: vault.appendingPathComponent("PhotosHelper.app"), name: "Photos Helper", identifier: "com.secret.photos", version: "1")
        let link = fixture.userApplicationSupport.appendingPathComponent("LinkedSupport")
        try fm.createSymbolicLink(at: link, withDestinationURL: vault)

        let report = fixture.scanner().scan(limit: 50)
        XCTAssertFalse(report.components.contains { $0.identifier == "com.secret.should-not-appear" })
        XCTAssertFalse(report.components.contains { $0.identifier == "com.secret.photos" })
    }

    func testInventoryNeverCreatesSafeCleanupCandidatesOrFeedsStoragePlan() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        let helper = fixture.userApplicationSupport.appendingPathComponent("Tool/ToolHelper.app")
        try fixture.makeBundle(at: helper, name: "Tool Helper", identifier: "com.example.tool.helper", version: "1")
        let report = fixture.scanner().scan(limit: 20)
        XCTAssertTrue(report.applications.allSatisfy { $0.cleanupDisposition != .safe })
        XCTAssertTrue(report.components.allSatisfy { $0.cleanupDisposition != .safe })
        let cleanup = try StorageScanner(privacyPolicy: fixture.policy, homeDirectory: fixture.home).candidates()
        XCTAssertFalse(cleanup.contains { $0.displayPath == helper.path })
    }

    func testGlobalLimitIsHonored() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        for index in 0..<5 {
            try fixture.makeBundle(at: fixture.applications.appendingPathComponent("App\(index).app"), name: "App\(index)", identifier: "com.example.app\(index)", version: "1")
        }
        let report = fixture.scanner().scan(limit: 2)
        XCTAssertLessThanOrEqual(report.applications.count + report.components.count, 2)
        XCTAssertTrue(report.truncated)
    }

    func testAmbiguousApplicationSupportHelperRemainsUnassociated() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        try fixture.makeBundle(at: fixture.applications.appendingPathComponent("Alpha.app"), name: "Alpha", identifier: "com.example.alpha", version: "1")
        try fixture.makeBundle(at: fixture.userApplicationSupport.appendingPathComponent("UnrelatedVendor/Helper.bundle"), name: "Helper", identifier: "org.other.helper", version: "1")
        let report = fixture.scanner().scan(limit: 20)
        let helper = try XCTUnwrap(report.components.first { $0.identifier == "org.other.helper" })
        XCTAssertNil(helper.associatedProduct)
        XCTAssertNil(helper.associationConfidence)
    }

    func testHomebrewPackageParserIsBoundedAndReviewOnly() {
        let parsed = HomebrewInventoryParser.parsePackages("alpha 1.0\nbeta 2.0\ngamma 3.0\n", kind: .homebrewFormula, source: .homebrewFormulae, limit: 2)
        XCTAssertEqual(parsed.components.count, 2)
        XCTAssertTrue(parsed.truncated)
        XCTAssertTrue(parsed.components.allSatisfy { $0.cleanupDisposition == .review })
        XCTAssertEqual(parsed.components.map(\.displayName), ["alpha", "beta"])
    }

    func testLoginBackgroundParserReturnsMetadataWithoutArgumentsAndMarksMalformedPartial() throws {
        let input = """
         #1:
                         Name: Example Helper
                  Disposition: [enabled, allowed, notified] (0xb)
                   Identifier: 2.com.example.helper
                          URL: file:///Applications/Example.app/Contents/Library/LoginItems/Helper.app/
              Executable Path: /Applications/Example.app/Contents/MacOS/Helper
        MALFORMED RECORD LINE
        """
        let parsed = LoginBackgroundInventoryParser.parse(input, limit: 10)
        let item = try XCTUnwrap(parsed.components.first)
        XCTAssertEqual(item.kind, .loginOrBackgroundItem)
        XCTAssertEqual(item.identifier, "2.com.example.helper")
        XCTAssertTrue(parsed.partial)
    }

    func testSystemExtensionParserReturnsBoundedMetadataAndMarksMalformedPartial() throws {
        let input = """
        2 extension(s)
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        *\t*\tTEAM123\tcom.example.extension (1.2/45)\tExample Extension\t[activated enabled]
        malformed extension row
        """
        let parsed = SystemExtensionInventoryParser.parse(input, limit: 10)
        let item = try XCTUnwrap(parsed.components.first)
        XCTAssertEqual(item.kind, .systemExtension)
        XCTAssertEqual(item.identifier, "com.example.extension")
        XCTAssertEqual(item.version, "1.2")
        XCTAssertEqual(item.executionStatus, "activated enabled")
        XCTAssertTrue(parsed.partial)
    }

    func testUnavailablePlatformSourcesDoNotFailWholeInventory() throws {
        let fixture = try InventoryFixture()
        defer { fixture.cleanup() }
        try fixture.makeBundle(at: fixture.applications.appendingPathComponent("Main.app"), name: "Main", identifier: "com.example.main", version: "1")
        let scanner = InstalledSoftwareInventoryScanner(
            privacyPolicy: fixture.policy,
            homeDirectory: fixture.home,
            roots: fixture.roots,
            commandRunner: AlwaysFailInventoryCommandRunner(),
            includePlatformSources: true,
            includeHomebrew: false
        )
        let report = scanner.scan(limit: 20)
        XCTAssertEqual(report.applications.count, 1)
        XCTAssertTrue(report.sources.contains { $0.source == .loginBackgroundItems && $0.status != .available })
        XCTAssertTrue(report.sources.contains { $0.source == .systemExtensions && $0.status != .available })
    }
}

private struct AlwaysFailInventoryCommandRunner: InventoryCommandRunning {
    func run(executable: String, arguments: [String]) throws -> String {
        throw MacCareError.commandFailed("synthetic failure")
    }
}

private final class InventoryFixture {
    let fm = FileManager.default
    let root: URL
    let home: URL
    let applications: URL
    let userApplicationSupport: URL
    let userLaunchAgents: URL
    let systemLaunchAgents: URL
    let launchDaemons: URL
    let policy: PrivacyPolicy

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("mac-care-inventory-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        applications = root.appendingPathComponent("Applications")
        userApplicationSupport = home.appendingPathComponent("Library/Application Support")
        userLaunchAgents = home.appendingPathComponent("Library/LaunchAgents")
        systemLaunchAgents = root.appendingPathComponent("Library/LaunchAgents")
        launchDaemons = root.appendingPathComponent("Library/LaunchDaemons")
        policy = PrivacyPolicy(homeDirectory: home)
        for directory in [applications, userApplicationSupport, userLaunchAgents, systemLaunchAgents, launchDaemons] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    var roots: InstalledSoftwareInventoryRoots {
        .init(
            applicationRoots: [applications],
            applicationSupportRoots: [userApplicationSupport],
            userLaunchAgentRoots: [userLaunchAgents],
            systemLaunchAgentRoots: [systemLaunchAgents],
            launchDaemonRoots: [launchDaemons]
        )
    }

    func scanner() -> InstalledSoftwareInventoryScanner {
        .init(
            privacyPolicy: policy,
            homeDirectory: home,
            roots: roots,
            includePlatformSources: false,
            includeHomebrew: false
        )
    }

    func makeBundle(at url: URL, name: String, identifier: String, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func makeLaunchPlist(at url: URL, label: String, program: String? = nil, programArguments: [String]? = nil) throws {
        var plist: [String: Any] = ["Label": label]
        if let program { plist["Program"] = program }
        if let programArguments { plist["ProgramArguments"] = programArguments }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }

    func cleanup() { try? fm.removeItem(at: root) }
}
