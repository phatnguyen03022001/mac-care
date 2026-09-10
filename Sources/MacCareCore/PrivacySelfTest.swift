import Foundation

public struct PrivacySelfTester: Sendable {
    public init() {}

    public func run() -> PrivacySelfTestReport {
        let syntheticHome = URL(fileURLWithPath: "/Users/mac-care-synthetic")
        let policy = PrivacyPolicy(homeDirectory: syntheticHome)
        let matrix: [(String, URL)] = [
            ("Pictures denied", syntheticHome.appendingPathComponent("Pictures/a.jpg")),
            ("Moved photoslibrary denied", URL(fileURLWithPath: "/Volumes/Test/Private.photoslibrary/original")),
            ("Keychain denied", syntheticHome.appendingPathComponent("Library/Keychains/login.keychain-db")),
            ("SSH denied", syntheticHome.appendingPathComponent(".ssh/id_ed25519")),
            ("Cloud credentials denied", syntheticHome.appendingPathComponent(".aws/credentials")),
            ("Browser auth denied", syntheticHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Login Data")),
        ]
        var checks = matrix.map { PrivacyCheck(name: $0.0, passed: policy.decision(for: $0.1) == .protected) }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("mac-care-selftest-\(UUID().uuidString)")
        let target = base.appendingPathComponent("Synthetic.photoslibrary", isDirectory: true)
        let link = base.appendingPathComponent("alias", isDirectory: true)
        var symlinkPassed = false
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
            symlinkPassed = policy.decision(for: link) == .protected
        } catch { symlinkPassed = false }
        try? fm.removeItem(at: base)
        checks.append(.init(name: "Symlink into photoslibrary denied", passed: symlinkPassed))
        return .init(passed: checks.allSatisfy(\.passed), checks: checks)
    }
}
