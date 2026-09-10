import Foundation

protocol ApplicationDiskUsageMeasuring: Sendable {
    func size(of directory: URL) throws -> Int64
}

extension DirectoryDiskUsage: ApplicationDiskUsageMeasuring {}

public struct ApplicationScanner: Sendable {
    private let privacyPolicy: PrivacyPolicy
    private let roots: [URL]
    private let diskUsage: any ApplicationDiskUsageMeasuring

    public init(privacyPolicy: PrivacyPolicy = PrivacyPolicy(), roots: [URL]? = nil) {
        self.privacyPolicy = privacyPolicy
        self.roots = roots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        self.diskUsage = DirectoryDiskUsage()
    }

    init(privacyPolicy: PrivacyPolicy, roots: [URL], diskUsage: any ApplicationDiskUsageMeasuring) {
        self.privacyPolicy = privacyPolicy
        self.roots = roots
        self.diskUsage = diskUsage
    }

    public func scan(limit: Int = 250) -> [ApplicationSnapshot] {
        let fm = FileManager.default
        var apps: [ApplicationSnapshot] = []
        for root in roots where privacyPolicy.decision(for: root) == .allowed {
            let children = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []).sorted { $0.path < $1.path }
            for child in children where child.pathExtension.lowercased() == "app" && apps.count < limit {
                let url = child.standardizedFileURL
                guard privacyPolicy.decision(for: url) == .allowed else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let bundle = Bundle(url: url)
                let info = bundle?.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
                let bytes = (try? diskUsage.size(of: url)) ?? 0
                let lastUsed = spotlightLastUsed(url)
                apps.append(.init(name: name, bundleIdentifier: bundle?.bundleIdentifier, version: version, path: url.path, approximateBytes: bytes, lastUsedAt: lastUsed, usageSignal: lastUsed == nil ? "No reliable Spotlight last-used signal" : "Spotlight kMDItemLastUsedDate", cleanupDisposition: .review))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func spotlightLastUsed(_ url: URL) -> Date? {
        guard let raw = try? FixedCommandRunner().run(executable: "/usr/bin/mdls", arguments: ["-raw", "-name", "kMDItemLastUsedDate", url.path]) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != "(null)" else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: value)
    }
}
