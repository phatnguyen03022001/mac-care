import Foundation

public struct PrivacyPolicy: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func decision(for candidate: URL) -> PrivacyDecision {
        let lexical = standardized(candidate)
        if isProtectedPath(lexical.path) { return .protected }
        let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL
        if isProtectedPath(resolved.path) { return .protected }
        return .allowed
    }

    public func requireAllowed(_ candidate: URL) throws {
        guard decision(for: candidate) == .allowed else { throw MacCareError.protectedPath }
    }

    private func standardized(_ url: URL) -> URL {
        let expanded = (url.path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private func isProtectedPath(_ rawPath: String) -> Bool {
        let path = (rawPath as NSString).standardizingPath
        let lower = path.lowercased()
        let home = homeDirectory.path.lowercased()
        let components = lower.split(separator: "/").map(String.init)

        if components.contains(where: { $0.hasSuffix(".photoslibrary") }) { return true }

        let protectedRoots = [
            "pictures", "documents", "desktop", "downloads", "movies", "music",
            "library/keychains", "library/photos", ".ssh", ".gnupg", ".aws", ".kube", ".config/gcloud",
            "library/safari",
            "library/application support/google/chrome",
            "library/application support/chromium",
            "library/application support/bravesoftware",
            "library/application support/microsoft edge",
            "library/application support/firefox",
            "library/application support/bitwarden",
            "library/application support/1password",
            "library/group containers/2bua8c4s2c.com.1password"
        ].map { home + "/" + $0 }
        if protectedRoots.contains(where: { hasPathPrefix(lower, $0) }) { return true }
        if hasPathPrefix(lower, "/library/keychains") { return true }

        let exactFiles = ["/.docker/config.json", "/.npmrc", "/.pypirc", "/.netrc"]
        if exactFiles.contains(where: { lower == home + $0 }) { return true }

        if hasPathPrefix(lower, home + "/library/containers/com.apple.photos") { return true }
        if hasPathPrefix(lower, home + "/library/group containers") {
            let tail = String(lower.dropFirst((home + "/library/group containers/").count))
            if tail.split(separator: "/").first.map({ $0.contains("photos") }) == true { return true }
        }
        if let entry = firstLevelEntry(in: lower, under: home + "/library/caches"), entry.contains("photos") {
            return true
        }
        if let entry = firstLevelEntry(in: lower, under: home + "/library/logs"), isApplePhotosLogEntry(entry) {
            return true
        }

        let secretNames: Set<String> = ["cookies", "login data", "web data", "sessions", "sessionstore.jsonlz4", "logins.json", "key4.db"]
        if components.contains(where: { secretNames.contains($0) }) { return true }
        return false
    }

    private func firstLevelEntry(in path: String, under root: String) -> String? {
        guard hasPathPrefix(path, root), path != root else { return nil }
        let tail = String(path.dropFirst((root + "/").count))
        return tail.split(separator: "/").first.map(String.init)
    }

    private func isApplePhotosLogEntry(_ entry: String) -> Bool {
        entry == "photos" ||
            entry.hasPrefix("photossearch") ||
            entry.hasPrefix("photolibrary") ||
            entry.hasPrefix("photoanalysis") ||
            entry.hasPrefix("com.apple.photos")
    }

    private func hasPathPrefix(_ path: String, _ prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }
}

public enum MacCareError: LocalizedError, Sendable {
    case protectedPath
    case unsupportedTarget
    case invalidPlan
    case stalePlan
    case unknownCandidate
    case reviewRequiresHumanApproval
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .protectedPath: "Protected path rejected by Mac Care privacy policy."
        case .unsupportedTarget: "Cleanup target is not supported."
        case .invalidPlan: "Cleanup plan is invalid."
        case .stalePlan: "Cleanup plan is stale or expired."
        case .unknownCandidate: "Cleanup candidate is unknown or was not issued by this plan."
        case .reviewRequiresHumanApproval: "REVIEW candidate requires explicit human approval in the native app."
        case .commandFailed(let message): "Fixed command failed: \(message)"
        }
    }
}
