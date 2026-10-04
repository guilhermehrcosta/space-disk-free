import Darwin
import Foundation

public struct SizeResult: Sendable, Equatable {
    public var bytes: UInt64
    public var permissionDenied: Bool

    public init(bytes: UInt64 = 0, permissionDenied: Bool = false) {
        self.bytes = bytes
        self.permissionDenied = permissionDenied
    }

    public static func + (lhs: SizeResult, rhs: SizeResult) -> SizeResult {
        SizeResult(bytes: lhs.bytes + rhs.bytes, permissionDenied: lhs.permissionDenied || rhs.permissionDenied)
    }
}

public struct TreeMeasurement: Sendable, Equatable {
    public var total: SizeResult
    public var children: [String: SizeResult]

    public init(total: SizeResult = SizeResult(), children: [String: SizeResult] = [:]) {
        self.total = total
        self.children = children
    }
}

public enum SizeCalculator {
    public static func measure(_ url: URL) -> SizeResult {
        walk(url, collectChildren: false).total
    }

    public static func measure(_ urls: [URL]) -> SizeResult {
        urls.reduce(SizeResult()) { $0 + measure($1) }
    }

    public static func measureTree(_ url: URL) -> TreeMeasurement {
        walk(url, collectChildren: true)
    }

    private static func walk(_ url: URL, collectChildren: Bool) -> TreeMeasurement {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return TreeMeasurement() }

        let stream: UnsafeMutablePointer<FTS>? = path.withCString { cPath in
            let copy = strdup(cPath)
            defer { free(copy) }
            var argv: [UnsafeMutablePointer<CChar>?] = [copy, nil]
            return fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)
        }
        guard let stream else { return TreeMeasurement() }
        defer { fts_close(stream) }

        var measurement = TreeMeasurement()
        var seenHardLinks = Set<HardLinkKey>()
        var visited = 0
        var currentChild: String?
        var childResult = SizeResult()

        while let entry = fts_read(stream) {
            visited += 1
            if visited & 0xFFF == 0, Task.isCancelled { break }

            let info = Int32(entry.pointee.fts_info)
            let level = Int(entry.pointee.fts_level)

            if collectChildren, level == 1 {
                if info == FTS_D {
                    currentChild = URL(filePath: String(cString: entry.pointee.fts_path)).normalizedPath
                    childResult = SizeResult()
                } else if info == FTS_DP, let child = currentChild {
                    measurement.children[child] = childResult
                    currentChild = nil
                    continue
                }
            }

            var entryResult = SizeResult()
            switch info {
            case FTS_F, FTS_D, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                if info == FTS_F, stat.st_nlink > 1 {
                    let key = HardLinkKey(device: stat.st_dev, inode: stat.st_ino)
                    guard seenHardLinks.insert(key).inserted else { continue }
                }
                entryResult.bytes = UInt64(max(stat.st_blocks, 0)) * 512
            case FTS_DNR, FTS_ERR, FTS_NS:
                let code = entry.pointee.fts_errno
                entryResult.permissionDenied = code == EACCES || code == EPERM
            default:
                continue
            }

            measurement.total = measurement.total + entryResult
            if currentChild != nil, level >= 1 { childResult = childResult + entryResult }
        }
        return measurement
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

extension URL {
    public var normalizedPath: String {
        var path = standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
