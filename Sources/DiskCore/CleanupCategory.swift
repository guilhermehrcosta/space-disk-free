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

/// Uma forma de limpar uma categoria. Categorias com mais de uma ação mostram um menu.
public struct CleanupAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// Explicação extra mostrada na confirmação.
    public let detail: String?
    public let strategy: CleanupStrategy

    public init(id: String, title: String, detail: String? = nil, strategy: CleanupStrategy) {
        self.id = id
        self.title = title
        self.detail = detail
        self.strategy = strategy
    }
}

public struct CleanupCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let paths: [URL]
    /// A primeira é a ação principal. Nunca vazio.
    public let actions: [CleanupAction]

    public init(id: String, title: String, detail: String, symbol: String, paths: [URL], actions: [CleanupAction]) {
        precondition(!actions.isEmpty, "Categoria \(id) sem ações")
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.paths = paths
        self.actions = actions
    }

    public init(id: String, title: String, detail: String, symbol: String, paths: [URL], strategy: CleanupStrategy) {
        self.init(
            id: id, title: title, detail: detail, symbol: symbol, paths: paths,
            actions: [CleanupAction(id: id, title: title, strategy: strategy)]
        )
    }

    /// Estratégia da ação principal.
    public var strategy: CleanupStrategy { actions[0].strategy }

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
    /// - Parameter isAppInstalled: recebe o nome do bundle (ex.: "Docker.app"); injetável para testes.
    public static func defaults(
        home: URL,
        isAppInstalled: (String) -> Bool = { isInstalledInApplications($0) }
    ) -> [CleanupCategory] {
        func h(_ relative: String) -> URL { home.appending(path: relative, directoryHint: .isDirectory) }

        let dockerDesktopData = h("Library/Containers/com.docker.docker/Data")
        let dockerDesktopInstalled = isAppInstalled("Docker.app")
        // Discos das VMs que rodam o engine Docker. O `docker` CLI limpa o engine do contexto atual.
        let dockerEngineDisks =
            (dockerDesktopInstalled ? [dockerDesktopData] : [])
            + [h("Library/Application Support/rancher-desktop/lima"), h(".colima")]

        var categories: [CleanupCategory] = [
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
                id: "go",
                title: "Go",
                detail: "Módulos baixados (~/go/pkg/mod) e cache de build. Baixados de novo sob demanda.",
                symbol: "g.circle",
                paths: [h("go/pkg/mod"), h("Library/Caches/go-build")],
                // Os módulos são somente leitura; só o próprio `go` consegue apagá-los.
                strategy: .command("go clean -modcache -cache")
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
                detail:
                    "Discos das VMs do Docker Desktop, Rancher Desktop ou Colima. Limpo pelo docker CLI no contexto atual; o engine precisa estar rodando.",
                symbol: "cube.box",
                paths: dockerEngineDisks,
                actions: [
                    CleanupAction(
                        id: "docker-prune",
                        title: "Limpeza rápida",
                        detail: "Remove containers parados, redes sem uso, imagens órfãs e cache de build.",
                        strategy: .command("docker system prune -f")
                    ),
                    CleanupAction(
                        id: "docker-prune-all",
                        title: "Limpeza completa",
                        detail:
                            "Também remove todas as imagens que nenhum container usa (serão baixadas de novo) e todo o cache de build. Volumes são mantidos.",
                        strategy: .command("docker system prune --all --force")
                    ),
                    CleanupAction(
                        id: "docker-volumes",
                        title: "Remover volumes sem uso…",
                        detail:
                            "Apaga os dados de volumes que nenhum container usa, como bancos de dados de projetos parados. Não dá para desfazer.",
                        strategy: .command("docker volume prune --all --force")
                    ),
                ]
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

        // Dados de um Docker Desktop que já foi desinstalado: o Docker.raw fica para trás e
        // nenhum `docker prune` alcança, pois o CLI aponta para outro engine (ou para nenhum).
        if !dockerDesktopInstalled {
            categories.append(
                CleanupCategory(
                    id: "docker-desktop-leftover",
                    title: "Docker Desktop (desinstalado)",
                    detail: "Disco virtual (Docker.raw) de um Docker Desktop que não está mais instalado, com imagens e volumes antigos.",
                    symbol: "shippingbox.and.arrow.backward",
                    paths: [dockerDesktopData],
                    strategy: .trashContents
                )
            )
        }
        return categories
    }

    /// Procura o app em /Applications e ~/Applications.
    public static func isInstalledInApplications(_ bundleName: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(filePath: "/Applications"), home.appending(path: "Applications")].contains {
            FileManager.default.fileExists(atPath: $0.appending(path: bundleName).path(percentEncoded: false))
        }
    }
}
