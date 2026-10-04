import Foundation

public struct SafetyPolicy: Sendable {
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    private var homePath: String { Self.normalized(home) }

    private var protectedPaths: Set<String> {
        let relative = [
            "", "Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
            "Public", "Applications", ".Trash",
            "Library/Application Support", "Library/Containers", "Library/Group Containers",
            "Library/Preferences", "Library/Caches", "Library/Logs", "Library/Developer",
            "Library/Mobile Documents", "Library/Keychains", "Library/Mail", "Library/Messages",
        ]
        var paths = Set(relative.map { $0.isEmpty ? homePath : homePath + "/" + $0 })
        paths.insert("/Applications")
        return paths
    }

    public func canTrash(_ url: URL) -> Bool {
        let path = Self.normalized(url)
        guard Self.isInside(path, homePath) || Self.isInside(path, "/Applications") else { return false }
        guard !protectedPaths.contains(path) else { return false }
        return !Self.isInside(path, homePath + "/Library/Mobile Documents")
    }

    public func canClearContents(of url: URL) -> Bool {
        let path = Self.normalized(url.resolvingSymlinksInPath())
        guard Self.isInside(path, homePath) else { return false }
        guard !Self.isInside(path, homePath + "/Library/Mobile Documents") else { return false }

        let neverClear: Set<String> = [
            homePath, homePath + "/Library", homePath + "/Desktop", homePath + "/Documents",
            homePath + "/Downloads", homePath + "/Pictures", homePath + "/Movies", homePath + "/Music",
            homePath + "/Library/Application Support", homePath + "/Library/Containers",
            homePath + "/Library/Group Containers", homePath + "/Library/Preferences",
        ]
        return !neverClear.contains(path)
    }

    static func normalized(_ url: URL) -> String {
        url.normalizedPath
    }

    static func isInside(_ path: String, _ base: String) -> Bool {
        path.hasPrefix(base + "/")
    }
}
