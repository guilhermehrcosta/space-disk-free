import Foundation

public struct DirectorySizeCache: Sendable {
    public struct Entry: Sendable, Equatable {
        public var result: SizeResult
        public var measuredAt: Date
    }

    public let maxAge: TimeInterval
    private var entries: [String: Entry] = [:]

    public init(maxAge: TimeInterval = 15 * 60) {
        self.maxAge = maxAge
    }

    public var count: Int { entries.count }

    public func entry(for url: URL, now: Date = .now) -> Entry? {
        guard let entry = entries[url.normalizedPath], now.timeIntervalSince(entry.measuredAt) <= maxAge else { return nil }
        return entry
    }

    public mutating func record(_ url: URL, _ result: SizeResult, at date: Date = .now) {
        entries[url.normalizedPath] = Entry(result: result, measuredAt: date)
    }

    public mutating func record(_ url: URL, _ measurement: TreeMeasurement, at date: Date = .now) {
        record(url, measurement.total, at: date)
        for (path, result) in measurement.children {
            entries[path] = Entry(result: result, measuredAt: date)
        }
    }

    public mutating func update(_ url: URL, _ result: SizeResult, at date: Date = .now) {
        removeDescendants(of: url)
        settle(url, result, at: date)
    }

    public mutating func settle(_ url: URL, _ result: SizeResult, at date: Date = .now) {
        let key = url.normalizedPath
        if let old = entries[key] {
            adjustAncestors(of: key, by: Int64(clamping: result.bytes) - Int64(clamping: old.result.bytes))
        } else {
            removeAncestors(of: key)
        }
        entries[key] = Entry(result: result, measuredAt: date)
    }

    public mutating func remove(_ url: URL, knownBytes: UInt64?) {
        let key = url.normalizedPath
        let bytes = entries[key]?.result.bytes ?? knownBytes
        removeDescendants(of: url)
        entries[key] = nil
        if let bytes {
            adjustAncestors(of: key, by: -Int64(clamping: bytes))
        } else {
            removeAncestors(of: key)
        }
    }

    public mutating func removeDescendants(of url: URL) {
        let key = url.normalizedPath
        entries = entries.filter { !Self.isDescendant($0.key, of: key) }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func adjustAncestors(of key: String, by delta: Int64) {
        for ancestor in entries.keys where Self.isDescendant(key, of: ancestor) {
            let bytes = Int64(clamping: entries[ancestor]!.result.bytes) + delta
            entries[ancestor]!.result.bytes = UInt64(max(bytes, 0))
        }
    }

    private mutating func removeAncestors(of key: String) {
        entries = entries.filter { !Self.isDescendant(key, of: $0.key) }
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path != ancestor && path.hasPrefix(ancestor == "/" ? "/" : ancestor + "/")
    }
}
