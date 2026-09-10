import Foundation

protocol InventoryCommandRunning: Sendable {
    func run(executable: String, arguments: [String]) throws -> String
}

extension FixedCommandRunner: InventoryCommandRunning {}

enum HomebrewInventoryParser {
    static func parsePackages(
        _ text: String,
        kind: InstalledSoftwareComponentKind,
        source: InstalledSoftwareInventorySource,
        limit: Int
    ) -> InventoryParseResult {
        let rows = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let capped = rows.prefix(max(0, limit))
        let components = capped.compactMap { row -> InstalledSoftwareComponent? in
            let fields = row.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let version = fields.count > 1 ? fields.dropFirst().joined(separator: ", ") : nil
            return .init(
                displayName: name,
                identifier: name,
                vendorIdentifier: nil,
                kind: kind,
                path: nil,
                version: version,
                source: source,
                associatedProduct: name,
                associationConfidence: .high,
                executionStatus: nil,
                cleanupDisposition: .review
            )
        }
        return .init(components: components, partial: false, truncated: rows.count > capped.count)
    }

    static func parseServices(_ text: String, limit: Int) -> InventoryParseResult {
        struct Entry: Decodable {
            let name: String
            let status: String?
            let file: String?
        }
        guard let data = text.data(using: .utf8), let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return .init(components: [], partial: true, truncated: false)
        }
        let capped = entries.prefix(max(0, limit))
        let components = capped.map { entry in
            InstalledSoftwareComponent(
                displayName: entry.name,
                identifier: entry.name,
                vendorIdentifier: nil,
                kind: .homebrewService,
                path: entry.file,
                version: nil,
                source: .homebrewServices,
                associatedProduct: entry.name,
                associationConfidence: .high,
                executionStatus: entry.status,
                cleanupDisposition: .review
            )
        }
        return .init(components: components, partial: false, truncated: entries.count > capped.count)
    }
}

enum LoginBackgroundInventoryParser {
    static func parse(_ text: String, limit: Int) -> InventoryParseResult {
        var records: [[String: String]] = []
        var current: [String: String]? = nil
        var partial = false

        func isRecordStart(_ line: String) -> Bool {
            guard line.first == "#", line.last == ":" else { return false }
            return line.dropFirst().dropLast().allSatisfy(\.isNumber)
        }

        let acceptedKeys = ["Name", "Developer Name", "Team Identifier", "Disposition", "Identifier", "URL", "Executable Path", "Bundle Identifier", "Parent Identifier"]
        let ignoredPrefixes = ["UUID:", "Type:", "Flags:", "Generation:", "Embedded Item Identifiers:", "ServiceManagement migrated:", "LaunchServices registered:", "Records for UID", "========================", "Items:"]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if isRecordStart(line) {
                if let current { records.append(current) }
                current = [:]
                continue
            }
            guard current != nil else { continue }
            if line.first == "#" { continue }
            var handled = false
            for key in acceptedKeys {
                let prefix = key + ":"
                if line.hasPrefix(prefix) {
                    current?[key] = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    handled = true
                    break
                }
            }
            if !handled && !ignoredPrefixes.contains(where: { line.hasPrefix($0) }) {
                partial = true
            }
        }
        if let current { records.append(current) }

        var components: [InstalledSoftwareComponent] = []
        let cappedRecords = records.prefix(max(0, limit))
        for record in cappedRecords {
            let name = nonNull(record["Name"])
            let identifier = nonNull(record["Bundle Identifier"]) ?? nonNull(record["Identifier"])
            guard name != nil || identifier != nil else { partial = true; continue }
            let path = filePath(nonNull(record["Executable Path"]) ?? nonNull(record["URL"]))
            components.append(.init(
                displayName: name ?? identifier ?? "Background item",
                identifier: identifier,
                vendorIdentifier: nonNull(record["Team Identifier"]),
                kind: .loginOrBackgroundItem,
                path: path,
                version: nil,
                source: .loginBackgroundItems,
                associatedProduct: nil,
                associationConfidence: nil,
                executionStatus: bracketValue(record["Disposition"]),
                cleanupDisposition: .review
            ))
        }
        return .init(components: components, partial: partial, truncated: records.count > cappedRecords.count)
    }

    private static func nonNull(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value != "(null)" else { return nil }
        return value
    }

    private static func filePath(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.hasPrefix("file://"), let url = URL(string: value) { return url.path }
        return value.hasPrefix("/") ? value : nil
    }

    private static func bracketValue(_ value: String?) -> String? {
        guard let value, let open = value.firstIndex(of: "["), let close = value[open...].firstIndex(of: "]") else { return nil }
        return String(value[value.index(after: open)..<close])
    }
}

enum SystemExtensionInventoryParser {
    static func parse(_ text: String, limit: Int) -> InventoryParseResult {
        var components: [InstalledSoftwareComponent] = []
        var partial = false
        var observedDataRows = 0

        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasSuffix("extension(s)") || line.hasPrefix("--- ") || line.hasPrefix("enabled\tactive\tteamID") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else { partial = true; continue }
            observedDataRows += 1
            guard components.count < max(0, limit) else { continue }
            let parsed = parseBundleAndVersion(fields[3])
            guard !parsed.identifier.isEmpty else { partial = true; continue }
            components.append(.init(
                displayName: fields[4].isEmpty ? parsed.identifier : fields[4],
                identifier: parsed.identifier,
                vendorIdentifier: fields[2].isEmpty ? nil : fields[2],
                kind: .systemExtension,
                path: nil,
                version: parsed.version,
                source: .systemExtensions,
                associatedProduct: nil,
                associationConfidence: nil,
                executionStatus: stripBrackets(fields[5]),
                cleanupDisposition: .review
            ))
        }
        return .init(components: components, partial: partial, truncated: observedDataRows > components.count)
    }

    private static func parseBundleAndVersion(_ field: String) -> (identifier: String, version: String?) {
        guard let range = field.range(of: " (", options: .backwards), field.hasSuffix(")") else {
            return (field.trimmingCharacters(in: .whitespaces), nil)
        }
        let identifier = String(field[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let versionField = String(field[range.upperBound..<field.index(before: field.endIndex)])
        let version = versionField.split(separator: "/", maxSplits: 1).first.map(String.init)
        return (identifier, version)
    }

    private static func stripBrackets(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "[", trimmed.last == "]", trimmed.count >= 2 else { return trimmed.isEmpty ? nil : trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}
