import Foundation

public struct ApplicationScanner: Sendable {
    private let privacyPolicy: PrivacyPolicy
    public init(privacyPolicy: PrivacyPolicy = PrivacyPolicy()) { self.privacyPolicy = privacyPolicy }

    public func scan(limit: Int = 250) -> [ApplicationSnapshot] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        var apps: [ApplicationSnapshot] = []
        let sizer = FileTreeSizer(privacyPolicy: privacyPolicy)
        for root in roots where privacyPolicy.decision(for: root) == .allowed {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for url in children where url.pathExtension.lowercased() == "app" && apps.count < limit {
                guard privacyPolicy.decision(for: url) == .allowed else { continue }
                let bundle = Bundle(url: url)
                let info = bundle?.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
                let bytes = (try? sizer.size(of: url, maximumEntries: 500_000)) ?? 0
                let lastUsed = spotlightLastUsed(url)
                apps.append(.init(name: name, bundleIdentifier: bundle?.bundleIdentifier, version: version, path: url.path, approximateBytes: bytes, lastUsedAt: lastUsed, usageSignal: lastUsed == nil ? "No reliable Spotlight last-used signal" : "Spotlight kMDItemLastUsedDate"))
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
