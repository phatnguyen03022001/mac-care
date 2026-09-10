import Foundation

struct FileTreeSizer: Sendable {
    let privacyPolicy: PrivacyPolicy
    func size(of root: URL, maximumEntries: Int = 200_000) throws -> Int64 {
        try privacyPolicy.requireAllowed(root)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return 0 }
        var total: Int64 = 0
        var stack = [root]
        var visited = 0
        while let current = stack.popLast() {
            if visited >= maximumEntries { break }
            visited += 1
            try privacyPolicy.requireAllowed(current)
            let values = try? current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                let children = try fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey], options: [.skipsSubdirectoryDescendants])
                for child in children where privacyPolicy.decision(for: child) == .allowed { stack.append(child) }
            } else {
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
