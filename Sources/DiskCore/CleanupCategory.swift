import Foundation

public enum CleanupStrategy: Sendable, Equatable {
    /// Apaga permanentemente o conteúdo das pastas (mantém as pastas). Só para dados regeneráveis.
    case deleteContents
    /// Move o conteúdo das pastas para a Lixeira (reversível).
    case trashContents
    /// Esvazia a Lixeira do usuário.
    case emptyTrash
    /// Executa uma ferramenta oficial de limpeza (ex.: `brew cleanup`) num shell de login.
    case command(String)
    /// Não limpa automaticamente: o usuário revisa os itens na aba Explorar.
    case review
}

public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let paths: [URL]
    public let strategy: CleanupStrategy

    public init(id: String, title: String, detail: String, symbol: String, paths: [URL], strategy: CleanupStrategy) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.paths = paths
        self.strategy = strategy
    }

    /// Entra no total "recuperável" apenas o que a própria categoria consegue liberar por inteiro.
    public var countsTowardReclaimable: Bool {
        switch strategy {
        case .deleteContents, .trashContents, .emptyTrash: true
        case .command, .review: false
        }
    }

    public var existingPaths: [URL] {
        paths.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    public var isAvailable: Bool { !existingPaths.isEmpty }
}

extension CleanupCategory {
    public static func defaults(home: URL) -> [CleanupCategory] {
        func h(_ relative: String) -> URL { home.appending(path: relative, directoryHint: .isDirectory) }

        return [
            CleanupCategory(
                id: "trash",
                title: "Lixeira",
                detail: "Itens já apagados que continuam ocupando espaço.",
                symbol: "trash",
                paths: [h(".Trash")],
                strategy: .emptyTrash
            ),
            CleanupCategory(
                id: "user-caches",
                title: "Caches de apps",
                detail: "Arquivos temporários recriados automaticamente. Feche os apps antes de limpar.",
                symbol: "shippingbox",
                paths: [h("Library/Caches")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "logs",
                title: "Logs",
                detail: "Registros de diagnóstico gerados por apps.",
                symbol: "doc.text.magnifyingglass",
                paths: [h("Library/Logs")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-derived-data",
                title: "Xcode DerivedData",
                detail: "Builds intermediários. O Xcode recompila quando precisar.",
                symbol: "hammer",
                paths: [h("Library/Developer/Xcode/DerivedData")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-device-support",
                title: "Xcode Device Support",
                detail: "Símbolos de versões de iOS/watchOS de aparelhos conectados. Baixados de novo quando preciso.",
                symbol: "iphone",
                paths: ["iOS", "watchOS", "tvOS", "visionOS"].map { h("Library/Developer/Xcode/\($0) DeviceSupport") },
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-archives",
                title: "Xcode Archives",
                detail: "Builds arquivados (incluem dSYMs). Vão para a Lixeira — revise antes de esvaziar.",
                symbol: "archivebox",
                paths: [h("Library/Developer/Xcode/Archives")],
                strategy: .trashContents
            ),
            CleanupCategory(
                id: "simulators",
                title: "Simuladores",
                detail: "Remove simuladores de runtimes que não estão mais instalados (xcrun simctl delete unavailable).",
                symbol: "ipad.and.iphone",
                paths: [h("Library/Developer/CoreSimulator/Devices")],
                strategy: .command("xcrun simctl delete unavailable")
            ),
            CleanupCategory(
                id: "dev-caches",
                title: "Caches de desenvolvimento",
                detail: "npm, pnpm, Gradle, Cargo e Maven. Baixados de novo sob demanda.",
                symbol: "chevron.left.forwardslash.chevron.right",
                paths: [".npm/_cacache", "Library/pnpm/store", ".pnpm-store", ".gradle/caches", ".cargo/registry/cache", ".m2/repository"]
                    .map(h),
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "homebrew",
                title: "Homebrew",
                detail: "Downloads antigos e versões desatualizadas (brew cleanup --prune=all).",
                symbol: "mug",
                paths: [h("Library/Caches/Homebrew")],
                strategy: .command("brew cleanup --prune=all")
            ),
            CleanupCategory(
                id: "docker",
                title: "Docker",
                detail: "Disco do Docker Desktop. Remove containers parados, imagens sem uso e cache de build (docker system prune -f).",
                symbol: "cube.box",
                paths: [h("Library/Containers/com.docker.docker/Data")],
                strategy: .command("docker system prune -f")
            ),
            CleanupCategory(
                id: "ios-backups",
                title: "Backups de iPhone/iPad",
                detail: "Backups locais de aparelhos. Revise e apague os antigos.",
                symbol: "externaldrive.badge.timemachine",
                paths: [h("Library/Application Support/MobileSync/Backup")],
                strategy: .review
            ),
            CleanupCategory(
                id: "downloads",
                title: "Downloads",
                detail: "Arquivos baixados. Revise os maiores itens.",
                symbol: "arrow.down.circle",
                paths: [h("Downloads")],
                strategy: .review
            ),
        ]
    }
}
