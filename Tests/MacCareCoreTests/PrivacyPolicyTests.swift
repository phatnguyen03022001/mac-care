import XCTest
@testable import MacCareCore

final class PrivacyPolicyTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/synthetic")

    func testProtectedPathMatrix() throws {
        let policy = PrivacyPolicy(homeDirectory: home)
        let blocked = [
            "/Users/synthetic/Pictures/x.jpg",
            "/Volumes/Data/Family.photoslibrary/originals/a.jpg",
            "/Users/synthetic/Library/Containers/com.apple.Photos/Data/x",
            "/Users/synthetic/Library/Group Containers/group.com.apple.Photos/x",
            "/Users/synthetic/Library/Photos/x",
            "/Users/synthetic/Library/Keychains/login.keychain-db",
            "/Library/Keychains/System.keychain",
            "/Users/synthetic/.ssh/id_ed25519",
            "/Users/synthetic/.aws/credentials",
            "/Users/synthetic/.config/gcloud/application_default_credentials.json",
            "/Users/synthetic/.docker/config.json",
            "/Users/synthetic/.npmrc",
            "/Users/synthetic/.pypirc",
            "/Users/synthetic/.netrc",
            "/Users/synthetic/Library/Application Support/Google/Chrome/Default/Cookies",
            "/Users/synthetic/Library/Safari/History.db",
            "/Users/synthetic/Library/Application Support/Bitwarden/data.json",
        ]
        for path in blocked {
            XCTAssertEqual(policy.decision(for: URL(fileURLWithPath: path)), .protected, path)
        }
    }

    func testSymlinkCannotBypassPhotosLibraryProtection() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = base.appendingPathComponent("Vault.photoslibrary", isDirectory: true)
        let link = base.appendingPathComponent("innocent", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: base) }
        let policy = PrivacyPolicy(homeDirectory: base.appendingPathComponent("home"))
        XCTAssertEqual(policy.decision(for: link), .protected)
    }
}
