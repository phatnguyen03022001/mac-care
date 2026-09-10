import Foundation

struct InstalledSoftwareInventoryRoots: Sendable {
    let applicationRoots: [URL]
    let applicationSupportRoots: [URL]
    let userLaunchAgentRoots: [URL]
    let systemLaunchAgentRoots: [URL]
    let launchDaemonRoots: [URL]

    static func standard(homeDirectory: URL) -> Self {
        .init(
            applicationRoots: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            ],
            applicationSupportRoots: [
                homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true),
                URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
            ],
            userLaunchAgentRoots: [homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true)],
            systemLaunchAgentRoots: [URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)],
            launchDaemonRoots: [URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)]
        )
    }
}

struct InstalledSoftwareTraversalLimits: Sendable {
    let applicationDepth: Int
    let applicationSupportDepth: Int
    let entriesPerRoot: Int

    static let standard = InstalledSoftwareTraversalLimits(applicationDepth: 6, applicationSupportDepth: 4, entriesPerRoot: 4_000)
}

struct InstalledSoftwareInventoryScanner: Sendable {
    let privacyPolicy: PrivacyPolicy
    let homeDirectory: URL
    let roots: InstalledSoftwareInventoryRoots
    let commandRunner: any InventoryCommandRunning
    let includePlatformSources: Bool
    let includeHomebrew: Bool
    let traversalLimits: InstalledSoftwareTraversalLimits

    init(
        privacyPolicy: PrivacyPolicy = PrivacyPolicy(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: InstalledSoftwareInventoryRoots? = nil,
        commandRunner: any InventoryCommandRunning = FixedCommandRunner(),
        includePlatformSources: Bool = true,
        includeHomebrew: Bool = true,
        traversalLimits: InstalledSoftwareTraversalLimits = .standard
    ) {
        self.privacyPolicy = privacyPolicy
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.roots = roots ?? .standard(homeDirectory: homeDirectory.standardizedFileURL)
        self.commandRunner = commandRunner
        self.includePlatformSources = includePlatformSources
        self.includeHomebrew = includeHomebrew
        self.traversalLimits = traversalLimits
    }

    func scan(limit: Int = 250) -> InstalledSoftwareInventoryReport {
        let boundedLimit = max(1, min(limit, 250))
        let applications = ApplicationScanner(privacyPolicy: privacyPolicy, roots: roots.applicationRoots).scan(limit: boundedLimit)
        let appDescriptors = applications.map(ApplicationDescriptor.init)
        var components: [InstalledSoftwareComponent] = []
        var statuses: [InstalledSoftwareSourceStatus] = []
        var truncated = applications.count >= boundedLimit

        func remaining() -> Int { max(0, boundedLimit - applications.count - components.count) }
        func append(_ result: SourceScanResult) {
            let room = remaining()
            let accepted = Array(result.components.prefix(room))
            components.append(contentsOf: accepted)
            let wasTruncated = result.truncated || accepted.count < result.components.count
            if wasTruncated { truncated = true }
            statuses.append(.init(
                source: result.source,
                status: result.partial || wasTruncated ? .partial : .available,
                itemCount: accepted.count,
                detail: result.detail ?? (wasTruncated ? "Result limit reached for this source." : nil)
            ))
        }
        func appendSkipped(_ source: InstalledSoftwareInventorySource) {
            truncated = true
            statuses.append(.init(source: source, status: .partial, itemCount: 0, detail: "Global inventory result limit reached before this source."))
        }

        let nested = scanApplicationRoots(applications: appDescriptors, limit: remaining())
        append(.init(source: .applications, components: nested.components, partial: nested.partial, truncated: nested.truncated, detail: nested.detail))
        if let index = statuses.indices.last {
            let status = statuses[index]
            statuses[index] = .init(source: status.source, status: status.status, itemCount: status.itemCount + applications.count, detail: status.detail)
        }

        if remaining() > 0 { append(scanApplicationSupport(applications: appDescriptors, limit: remaining())) }
        else { appendSkipped(.applicationSupport) }

        scanLaunchSource(roots.userLaunchAgentRoots, source: .userLaunchAgents, kind: .launchAgent, applications: appDescriptors, remaining: remaining, append: append, appendSkipped: appendSkipped)
        scanLaunchSource(roots.systemLaunchAgentRoots, source: .systemLaunchAgents, kind: .launchAgent, applications: appDescriptors, remaining: remaining, append: append, appendSkipped: appendSkipped)
        scanLaunchSource(roots.launchDaemonRoots, source: .launchDaemons, kind: .launchDaemon, applications: appDescriptors, remaining: remaining, append: append, appendSkipped: appendSkipped)

        if includePlatformSources {
            if remaining() > 0 { append(scanLoginBackgroundItems(applications: appDescriptors, limit: remaining())) }
            else { appendSkipped(.loginBackgroundItems) }
            if remaining() > 0 { append(scanSystemExtensions(applications: appDescriptors, limit: remaining())) }
            else { appendSkipped(.systemExtensions) }
        } else {
            statuses.append(.init(source: .loginBackgroundItems, status: .unavailable, itemCount: 0, detail: "Platform source disabled for this scan."))
            statuses.append(.init(source: .systemExtensions, status: .unavailable, itemCount: 0, detail: "Platform source disabled for this scan."))
        }

        if includeHomebrew {
            for result in scanHomebrewSources(limit: remaining()) {
                if remaining() > 0 { append(result) } else { appendSkipped(result.source) }
            }
        } else {
            for source in [InstalledSoftwareInventorySource.homebrewFormulae, .homebrewCasks, .homebrewServices] {
                statuses.append(.init(source: source, status: .unavailable, itemCount: 0, detail: "Homebrew inventory disabled for this scan."))
            }
        }

        components = Array(components.prefix(max(0, boundedLimit - applications.count)))
        let counts = Dictionary(grouping: components, by: { $0.kind.rawValue }).mapValues(\.count)
        var countsByKind = counts
        countsByKind[InstalledSoftwareComponentKind.application.rawValue] = applications.count
        let summary = InstalledSoftwareInventorySummary(
            applicationCount: applications.count,
            componentCount: components.count,
            totalCount: applications.count + components.count,
            countsByKind: countsByKind
        )
        return .init(
            applications: applications,
            components: components,
            summary: summary,
            sources: statuses,
            truncated: truncated
        )
    }
}

private extension InstalledSoftwareInventoryScanner {
    struct ApplicationDescriptor: Sendable {
        let name: String
        let path: String
        let bundleIdentifier: String?
        init(_ snapshot: ApplicationSnapshot) {
            name = snapshot.name
            path = URL(fileURLWithPath: snapshot.path).standardizedFileURL.path
            bundleIdentifier = snapshot.bundleIdentifier
        }
    }

    struct TraversalResult: Sendable {
        let components: [InstalledSoftwareComponent]
        let partial: Bool
        let truncated: Bool
        let detail: String?
    }

    struct SourceScanResult: Sendable {
        let source: InstalledSoftwareInventorySource
        let components: [InstalledSoftwareComponent]
        let partial: Bool
        let truncated: Bool
        let detail: String?
        init(source: InstalledSoftwareInventorySource, components: [InstalledSoftwareComponent], partial: Bool = false, truncated: Bool = false, detail: String? = nil) {
            self.source = source
            self.components = components
            self.partial = partial
            self.truncated = truncated
            self.detail = detail
        }
    }

    func scanApplicationRoots(applications: [ApplicationDescriptor], limit: Int) -> TraversalResult {
        traverse(
            roots: roots.applicationRoots,
            source: .applications,
            applications: applications,
            maximumDepth: traversalLimits.applicationDepth,
            limit: limit,
            mode: .applicationBundles
        )
    }

    func scanApplicationSupport(applications: [ApplicationDescriptor], limit: Int) -> SourceScanResult {
        let result = traverse(
            roots: roots.applicationSupportRoots,
            source: .applicationSupport,
            applications: applications,
            maximumDepth: traversalLimits.applicationSupportDepth,
            limit: limit,
            mode: .applicationSupport
        )
        return .init(source: .applicationSupport, components: result.components, partial: result.partial, truncated: result.truncated, detail: result.detail)
    }

    enum TraversalMode { case applicationBundles, applicationSupport }
    struct QueueItem { let url: URL; let depth: Int; let parentApplication: String? }

    func traverse(
        roots scanRoots: [URL],
        source: InstalledSoftwareInventorySource,
        applications: [ApplicationDescriptor],
        maximumDepth: Int,
        limit: Int,
        mode: TraversalMode
    ) -> TraversalResult {
        let fm = FileManager.default
        let topLevelApps = Dictionary(uniqueKeysWithValues: applications.map { ($0.path, $0.name) })
        var components: [InstalledSoftwareComponent] = []
        var visited = 0
        var truncated = false
        var partial = false

        for root in scanRoots.sorted(by: { $0.path < $1.path }) {
            guard components.count < limit else { truncated = true; break }
            guard privacyPolicy.decision(for: root) == .allowed else { continue }
            guard fm.fileExists(atPath: root.path) else { continue }
            guard var children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey], options: []) else {
                partial = true
                continue
            }
            children.sort { $0.path < $1.path }
            var queue = children.map { QueueItem(url: $0, depth: 1, parentApplication: nil) }
            var cursor = 0
            var visitedForRoot = 0

            while cursor < queue.count && components.count < limit {
                if visitedForRoot >= traversalLimits.entriesPerRoot {
                    truncated = true
                    break
                }
                let item = queue[cursor]; cursor += 1
                visited += 1; visitedForRoot += 1
                guard privacyPolicy.decision(for: item.url) == .allowed else { continue }
                guard let values = try? item.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]) else {
                    partial = true
                    continue
                }
                if values.isSymbolicLink == true { continue }

                var parentApplication = item.parentApplication
                if values.isDirectory == true {
                    let standardizedPath = item.url.standardizedFileURL.path
                    let ext = item.url.pathExtension.lowercased()
                    var descend = item.depth < maximumDepth

                    if mode == .applicationBundles, ext == "app" {
                        if let topName = topLevelApps[standardizedPath] {
                            parentApplication = topName
                        } else {
                            let metadata = bundleMetadata(item.url)
                            let association = parentApplication.map { ($0, SoftwareAssociationConfidence.high) } ?? association(for: item.url.path, identifier: metadata.identifier, applications: applications)
                            components.append(component(
                                url: item.url,
                                metadata: metadata,
                                kind: .nestedApplication,
                                source: source,
                                association: association
                            ))
                        }
                    } else if ["app", "xpc", "appex", "bundle"].contains(ext) {
                        let metadata = bundleMetadata(item.url)
                        let directAssociation = parentApplication.map { ($0, SoftwareAssociationConfidence.high) }
                        let association = directAssociation ?? association(for: item.url.path, identifier: metadata.identifier, applications: applications)
                        components.append(component(url: item.url, metadata: metadata, kind: .helper, source: source, association: association))
                        if mode == .applicationSupport { descend = false }
                    }

                    if descend, let next = try? fm.contentsOfDirectory(at: item.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey], options: []) {
                        let sorted = next.sorted { $0.path < $1.path }
                        queue.append(contentsOf: sorted.map { QueueItem(url: $0, depth: item.depth + 1, parentApplication: parentApplication) })
                    }
                } else if mode == .applicationSupport, values.isRegularFile == true, isRecognizableHelperExecutable(item.url, fileManager: fm) {
                    let association = association(for: item.url.path, identifier: nil, applications: applications)
                    components.append(.init(
                        displayName: item.url.lastPathComponent,
                        identifier: nil,
                        vendorIdentifier: nil,
                        kind: .helper,
                        path: item.url.path,
                        version: nil,
                        source: source,
                        associatedProduct: association?.0,
                        associationConfidence: association?.1,
                        executionStatus: nil,
                        cleanupDisposition: .review
                    ))
                }
            }
            if cursor < queue.count { truncated = true }
        }
        if components.count >= limit && limit > 0 { truncated = true }
        let detail = truncated ? "Bounded traversal stopped at the configured entry or result limit." : nil
        _ = visited
        return .init(components: components, partial: partial, truncated: truncated, detail: detail)
    }

    func bundleMetadata(_ url: URL) -> (name: String, identifier: String?, version: String?) {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
        return (name, bundle?.bundleIdentifier ?? (info?["CFBundleIdentifier"] as? String), version)
    }

    func component(
        url: URL,
        metadata: (name: String, identifier: String?, version: String?),
        kind: InstalledSoftwareComponentKind,
        source: InstalledSoftwareInventorySource,
        association: (String, SoftwareAssociationConfidence)?
    ) -> InstalledSoftwareComponent {
        .init(
            displayName: metadata.name,
            identifier: metadata.identifier,
            vendorIdentifier: nil,
            kind: kind,
            path: url.path,
            version: metadata.version,
            source: source,
            associatedProduct: association?.0,
            associationConfidence: association?.1,
            executionStatus: nil,
            cleanupDisposition: .review
        )
    }

    func isRecognizableHelperExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.isExecutableFile(atPath: url.path) else { return false }
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        if ["bin", "sbin", "helpers", "helper", "agents", "daemons", "services"].contains(parent) { return true }
        let name = url.lastPathComponent.lowercased()
        return ["helper", "agent", "daemon", "service", "updater"].contains(where: { name.contains($0) })
    }

    func association(for path: String?, identifier: String?, applications: [ApplicationDescriptor]) -> (String, SoftwareAssociationConfidence)? {
        if let path {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            for app in applications where standardized == app.path || standardized.hasPrefix(app.path + "/") {
                return (app.name, .high)
            }
        }
        if let identifier {
            let lower = identifier.lowercased()
            for app in applications {
                if let bundle = app.bundleIdentifier?.lowercased(), lower.hasPrefix(bundle + ".") {
                    return (app.name, .high)
                }
            }
        }
        if let path {
            let normalizedComponents = URL(fileURLWithPath: path).pathComponents.map(normalizedAssociationToken)
            for app in applications {
                let appToken = normalizedAssociationToken(app.name)
                if appToken.count >= 5, normalizedComponents.contains(appToken) {
                    return (app.name, .medium)
                }
            }
        }
        return nil
    }

    func normalizedAssociationToken(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func scanLaunchSource(
        _ launchRoots: [URL],
        source: InstalledSoftwareInventorySource,
        kind: InstalledSoftwareComponentKind,
        applications: [ApplicationDescriptor],
        remaining: () -> Int,
        append: (SourceScanResult) -> Void,
        appendSkipped: (InstalledSoftwareInventorySource) -> Void
    ) {
        guard remaining() > 0 else { appendSkipped(source); return }
        append(scanLaunchItems(roots: launchRoots, source: source, kind: kind, applications: applications, limit: remaining()))
    }

    func scanLaunchItems(
        roots launchRoots: [URL],
        source: InstalledSoftwareInventorySource,
        kind: InstalledSoftwareComponentKind,
        applications: [ApplicationDescriptor],
        limit: Int
    ) -> SourceScanResult {
        let fm = FileManager.default
        var components: [InstalledSoftwareComponent] = []
        var partial = false
        var sawMore = false

        guard fm.isExecutableFile(atPath: "/usr/bin/plutil") else {
            return .init(source: source, components: [], partial: true, detail: "plist metadata reader is unavailable.")
        }
        for root in launchRoots.sorted(by: { $0.path < $1.path }) {
            guard privacyPolicy.decision(for: root) == .allowed, fm.fileExists(atPath: root.path) else { continue }
            guard let rows = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else {
                partial = true; continue
            }
            for plist in rows.filter({ $0.pathExtension.lowercased() == "plist" }).sorted(by: { $0.path < $1.path }) {
                guard components.count < limit else { sawMore = true; break }
                guard privacyPolicy.decision(for: plist) == .allowed else { continue }
                if (try? plist.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                let label = plistValue("Label", at: plist)
                let program = plistValue("Program", at: plist) ?? plistValue("ProgramArguments.0", at: plist)
                let targetDecision = program.flatMap { absolutePath($0) }.map { privacyPolicy.decision(for: URL(fileURLWithPath: $0)) }
                let protectedTarget = targetDecision == .protected
                let safeProgram = protectedTarget ? nil : program.flatMap(absolutePath)
                let associationResult: (String, SoftwareAssociationConfidence)?
                if let safeProgram {
                    associationResult = association(for: safeProgram, identifier: label, applications: applications)
                } else {
                    associationResult = nil
                }
                components.append(.init(
                    displayName: label ?? plist.deletingPathExtension().lastPathComponent,
                    identifier: label,
                    vendorIdentifier: nil,
                    kind: kind,
                    path: safeProgram,
                    version: nil,
                    source: source,
                    associatedProduct: associationResult?.0,
                    associationConfidence: associationResult?.1,
                    executionStatus: nil,
                    cleanupDisposition: protectedTarget ? .protected : .review
                ))
            }
        }
        return .init(source: source, components: components, partial: partial, truncated: sawMore)
    }

    func plistValue(_ key: String, at url: URL) -> String? {
        guard let raw = try? commandRunner.run(executable: "/usr/bin/plutil", arguments: ["-extract", key, "raw", "-o", "-", url.path]) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func absolutePath(_ value: String) -> String? {
        if value.hasPrefix("file://"), let url = URL(string: value) { return url.path }
        return value.hasPrefix("/") ? value : nil
    }

    func scanLoginBackgroundItems(applications: [ApplicationDescriptor], limit: Int) -> SourceScanResult {
        let executable = "/usr/bin/sfltool"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .init(source: .loginBackgroundItems, components: [], partial: true, detail: "Login/background item metadata source is unavailable.")
        }
        do {
            let output = try commandRunner.run(executable: executable, arguments: ["dumpbtm"])
            let parsed = LoginBackgroundInventoryParser.parse(output, limit: limit)
            let enriched = parsed.components.map { secureAndAssociate($0, applications: applications) }
            return .init(source: .loginBackgroundItems, components: enriched, partial: parsed.partial, truncated: parsed.truncated, detail: parsed.partial ? "Some platform background-item rows were not understood." : nil)
        } catch {
            return .init(source: .loginBackgroundItems, components: [], partial: true, detail: "Login/background item metadata could not be read.")
        }
    }

    func scanSystemExtensions(applications: [ApplicationDescriptor], limit: Int) -> SourceScanResult {
        let executable = "/usr/bin/systemextensionsctl"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .init(source: .systemExtensions, components: [], partial: true, detail: "System extension metadata source is unavailable.")
        }
        do {
            let output = try commandRunner.run(executable: executable, arguments: ["list"])
            let parsed = SystemExtensionInventoryParser.parse(output, limit: limit)
            let enriched = parsed.components.map { secureAndAssociate($0, applications: applications) }
            return .init(source: .systemExtensions, components: enriched, partial: parsed.partial, truncated: parsed.truncated, detail: parsed.partial ? "Some system-extension rows were not understood." : nil)
        } catch {
            return .init(source: .systemExtensions, components: [], partial: true, detail: "System extension metadata could not be read.")
        }
    }

    func secureAndAssociate(_ component: InstalledSoftwareComponent, applications: [ApplicationDescriptor]) -> InstalledSoftwareComponent {
        var path = component.path
        var disposition = component.cleanupDisposition
        if let currentPath = path, currentPath.hasPrefix("/"), privacyPolicy.decision(for: URL(fileURLWithPath: currentPath)) == .protected {
            path = nil
            disposition = .protected
        }
        let existingAssociation = component.associatedProduct.flatMap { product in component.associationConfidence.map { (product, $0) } }
        let inferred = existingAssociation ?? association(for: path, identifier: component.identifier, applications: applications)
        return .init(
            displayName: component.displayName,
            identifier: component.identifier,
            vendorIdentifier: component.vendorIdentifier,
            kind: component.kind,
            path: path,
            version: component.version,
            source: component.source,
            associatedProduct: inferred?.0,
            associationConfidence: inferred?.1,
            executionStatus: component.executionStatus,
            cleanupDisposition: disposition
        )
    }

    func scanHomebrewSources(limit: Int) -> [SourceScanResult] {
        guard let brew = BrewCommandRunner() else {
            return [
                .init(source: .homebrewFormulae, components: [], partial: true, detail: "Homebrew is unavailable."),
                .init(source: .homebrewCasks, components: [], partial: true, detail: "Homebrew is unavailable."),
                .init(source: .homebrewServices, components: [], partial: true, detail: "Homebrew is unavailable."),
            ]
        }
        let specs: [(InstalledSoftwareInventorySource, [String], (String, Int) -> InventoryParseResult)] = [
            (.homebrewFormulae, ["list", "--formula", "--versions"], { HomebrewInventoryParser.parsePackages($0, kind: .homebrewFormula, source: .homebrewFormulae, limit: $1) }),
            (.homebrewCasks, ["list", "--cask", "--versions"], { HomebrewInventoryParser.parsePackages($0, kind: .homebrewCask, source: .homebrewCasks, limit: $1) }),
            (.homebrewServices, ["services", "list", "--json"], { HomebrewInventoryParser.parseServices($0, limit: $1) }),
        ]
        var remaining = limit
        return specs.map { source, arguments, parser in
            guard remaining > 0 else { return .init(source: source, components: [], partial: false, truncated: true) }
            do {
                let output = try commandRunner.run(executable: brew.executable, arguments: arguments)
                let parsed = parser(output, remaining)
                remaining -= parsed.components.count
                return .init(source: source, components: parsed.components, partial: parsed.partial, truncated: parsed.truncated, detail: parsed.partial ? "Homebrew inventory output could not be fully parsed." : nil)
            } catch {
                return .init(source: source, components: [], partial: true, detail: "Homebrew inventory source could not be read.")
            }
        }
    }
}
