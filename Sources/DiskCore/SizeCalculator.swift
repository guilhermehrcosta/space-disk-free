import Darwin
import Foundation

public struct SizeResult: Sendable, Equatable {
    public var bytes: UInt64
    /// Algum subdiretório não pôde ser lido (normalmente falta de Acesso Total ao Disco).
    public var permissionDenied: Bool

    public init(bytes: UInt64 = 0, permissionDenied: Bool = false) {
        self.bytes = bytes
        self.permissionDenied = permissionDenied
    }

    public static func + (lhs: SizeResult, rhs: SizeResult) -> SizeResult {
        SizeResult(bytes: lhs.bytes + rhs.bytes, permissionDenied: lhs.permissionDenied || rhs.permissionDenied)
    }
}

public enum SizeCalculator {
    /// Espaço realmente alocado em disco por um arquivo ou diretório (recursivo).
    ///
    /// Usa `fts(3)` em vez de `FileManager.enumerator` por ser bem mais rápido em árvores
    /// grandes. Não segue symlinks, não atravessa para outros volumes e conta hard links
    /// uma única vez. Respeita cancelamento da `Task` corrente.
    public static func measure(_ url: URL) -> SizeResult {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return SizeResult() }

        let stream: UnsafeMutablePointer<FTS>? = path.withCString { cPath in
            let copy = strdup(cPath)
            defer { free(copy) }
            var argv: [UnsafeMutablePointer<CChar>?] = [copy, nil]
            return fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)
        }
        guard let stream else { return SizeResult() }
        defer { fts_close(stream) }

        var result = SizeResult()
        var seenHardLinks = Set<HardLinkKey>()
        var visited = 0

        while let entry = fts_read(stream) {
            visited += 1
            if visited & 0xFFF == 0, Task.isCancelled { break }

            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_F, FTS_D, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                if info == FTS_F, stat.st_nlink > 1 {
                    let key = HardLinkKey(device: stat.st_dev, inode: stat.st_ino)
                    guard seenHardLinks.insert(key).inserted else { continue }
                }
                result.bytes += UInt64(max(stat.st_blocks, 0)) * 512
            case FTS_DNR, FTS_ERR, FTS_NS:
                let code = entry.pointee.fts_errno
                if code == EACCES || code == EPERM { result.permissionDenied = true }
            default:
                continue
            }
        }
        return result
    }

    public static func measure(_ urls: [URL]) -> SizeResult {
        urls.reduce(SizeResult()) { $0 + measure($1) }
    }
}

private struct HardLinkKey: Hashable {
    let device: dev_t
    let inode: ino_t
}

extension UInt64 {
    public var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: self), countStyle: .file)
    }
}
