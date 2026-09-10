import Foundation

private enum StorageSizingStrategy {
    case policyAwareTree
    case trustedDirectoryUsage
}

struct StorageScanner: Sendable {
    let privacyPolicy: PrivacyPolicy
    let homeDirectory: URL

    init(privacyPolicy: PrivacyPolicy = PrivacyPolicy(), homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.privacyPolicy = privacyPolicy; self.homeDirectory = homeDirectory
    }

    func candidates(maxCandidates: Int = 200) throws -> [PlannedCleanupCandidate] {
        let fm = FileManager.default
        let treeSizer = FileTreeSizer(privacyPolicy: privacyPolicy)
        let directorySizer = DirectoryDiskUsage()
        var result: [PlannedCleanupCandidate] = []

        func size(_ item: URL, using strategy: StorageSizingStrategy) -> Int64 {
            switch strategy {
            case .policyAwareTree:
                return (try? treeSizer.size(of: item)) ?? 0
            case .trustedDirectoryUsage:
                guard privacyPolicy.decision(for: item) == .allowed else { return 0 }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { return 0 }
                return (try? directorySizer.size(of: item)) ?? 0
            }
        }

        func appendRoot(_ url: URL, category: String, risk: CleanupRisk, reason: String, splitChildren: Bool, sizing: StorageSizingStrategy = .policyAwareTree) {
            guard result.count < maxCandidates, fm.fileExists(atPath: url.path), privacyPolicy.decision(for: url) == .allowed else { return }
            let urls: [URL]
            if splitChildren {
                urls = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])) ?? []
            } else { urls = [url] }
            for item in urls where result.count < maxCandidates {
                guard privacyPolicy.decision(for: item) == .allowed else { continue }
                let bytes = size(item, using: sizing)
                guard bytes > 0 else { continue }
                result.append(.init(category: category, displayPath: item.path, estimatedBytes: bytes, reason: reason, risk: risk, proposedAction: risk == .review ? "Move to Trash after explicit review" : "Delete regenerable data", target: .file(item)))
            }
        }

        appendRoot(homeDirectory.appendingPathComponent("Library/Caches"), category: "User caches", risk: .safe, reason: "Regenerable per-user cache data", splitChildren: true)
        appendRoot(homeDirectory.appendingPathComponent("Library/Logs"), category: "User logs", risk: .safe, reason: "Diagnostic logs that applications can recreate", splitChildren: true)
        appendRoot(homeDirectory.appendingPathComponent(".Trash"), category: "Trash", risk: .review, reason: "User-deleted items may still be intentionally recoverable", splitChildren: true)
        appendRoot(homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData"), category: "Xcode DerivedData", risk: .safe, reason: "Regenerable Xcode build artifacts", splitChildren: true)
        appendRoot(homeDirectory.appendingPathComponent(".npm/_cacache"), category: "npm cache", risk: .safe, reason: "Regenerable npm package cache", splitChildren: false, sizing: .trustedDirectoryUsage)
        appendRoot(homeDirectory.appendingPathComponent("Library/pnpm/store"), category: "pnpm store", risk: .safe, reason: "Regenerable pnpm content-addressed store", splitChildren: false, sizing: .trustedDirectoryUsage)
        appendRoot(homeDirectory.appendingPathComponent("Library/Caches/Yarn"), category: "Yarn cache", risk: .safe, reason: "Regenerable Yarn package cache", splitChildren: false, sizing: .trustedDirectoryUsage)
        return result
    }

    func report(maxCandidates: Int = 200) throws -> StorageScanReport {
        let rows = try candidates(maxCandidates: maxCandidates)
        let grouped = Dictionary(grouping: rows, by: \.category)
        let categories = grouped.keys.sorted().map { key in
            StorageCategorySummary(category: key, bytes: grouped[key]!.reduce(0) { $0 + $1.estimatedBytes }, candidates: grouped[key]!.count)
        }
        return .init(categories: categories, estimatedReclaimableBytes: rows.filter { $0.risk == .safe }.reduce(0) { $0 + $1.estimatedBytes }, candidateCount: rows.count)
    }
}
