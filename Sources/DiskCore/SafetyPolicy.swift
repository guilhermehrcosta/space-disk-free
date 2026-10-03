import Foundation

/// Regras que impedem o app de apagar algo que não deveria, independente do que a UI pedir.
public struct SafetyPolicy: Sendable {
    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    private var homePath: String { Self.normalized(home) }

    /// Pastas que nunca podem ir para a Lixeira nem ter o conteúdo apagado em bloco.
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

    /// Pode mover um item para a Lixeira a partir da aba Explorar?
    public func canTrash(_ url: URL) -> Bool {
        let path = Self.normalized(url)
        guard Self.isInside(path, homePath) || Self.isInside(path, "/Applications") else { return false }
        guard !protectedPaths.contains(path) else { return false }
        return !Self.isInside(path, homePath + "/Library/Mobile Documents")
    }

    /// Pode apagar em bloco o conteúdo desta pasta? (a pasta em si continua existindo)
    public func canClearContents(of url: URL) -> Bool {
        // Resolve symlinks: um link apontando para fora da home não pode virar alvo.
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
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// `true` se `path` está estritamente dentro de `base`.
    static func isInside(_ path: String, _ base: String) -> Bool {
        path.hasPrefix(base + "/")
    }
}
