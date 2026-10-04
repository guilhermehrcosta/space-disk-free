import Foundation

public struct FileNode: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let isPackage: Bool
    public var size: UInt64?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var canEnter: Bool { isDirectory && !isPackage }
}

public enum DirectoryLister {
    private static let skippedAtRoot: Set<String> = ["/Volumes", "/dev", "/System/Volumes", "/cores"]

    public static func children(of directory: URL) throws -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)

        return urls.compactMap { url in
            if skippedAtRoot.contains(url.path(percentEncoded: false)) { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isLink = values?.isSymbolicLink ?? false
            let isDirectory = !isLink && (values?.isDirectory ?? false)
            return FileNode(
                url: url,
                isDirectory: isDirectory,
                isPackage: values?.isPackage ?? false,
                size: isDirectory ? nil : UInt64(max(values?.totalFileAllocatedSize ?? 0, 0))
            )
        }
    }
}
