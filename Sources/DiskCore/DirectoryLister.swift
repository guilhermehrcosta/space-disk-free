import Foundation

public struct FileNode: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let isPackage: Bool
    /// `nil` enquanto o tamanho de um diretório ainda está sendo calculado.
    public var size: UInt64?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    /// Pastas comuns podem ser abertas; pacotes (.app, .photoslibrary…) são tratados como arquivos.
    public var canEnter: Bool { isDirectory && !isPackage }
}

public enum DirectoryLister {
    /// Pastas da raiz que não devem ser medidas: outros volumes, devfs e aliases do volume de dados.
    private static let skippedAtRoot: Set<String> = ["/Volumes", "/dev", "/System/Volumes", "/cores"]

    /// Lista os filhos diretos (inclusive ocultos). Arquivos já vêm com tamanho; diretórios vêm com `size == nil`.
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
