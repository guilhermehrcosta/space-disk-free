import Foundation

public struct VolumeStatus: Sendable, Equatable {
    public let name: String
    public let totalBytes: UInt64
    /// Espaço disponível como o Finder mostra (inclui espaço "purgeable" que o sistema libera sozinho).
    public let availableBytes: UInt64

    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    public static func current(for url: URL = URL(filePath: "/")) -> VolumeStatus? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }

        return VolumeStatus(
            name: values.volumeLocalizedName ?? "Disco",
            totalBytes: UInt64(max(total, 0)),
            availableBytes: UInt64(max(available, 0))
        )
    }
}
