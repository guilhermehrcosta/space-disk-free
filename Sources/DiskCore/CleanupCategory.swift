import Foundation

public enum CleanupStrategy: Sendable, Equatable {
    case deleteContents
    case trashContents
    case deleteItems([URL])
    case emptyTrash
    case command(String)
    case review
}

public struct CleanupAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
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

    public var strategy: CleanupStrategy { actions[0].strategy }

    public var countsTowardReclaimable: Bool {
        switch strategy {
        case .deleteContents, .trashContents, .emptyTrash: true
        case .deleteItems, .command, .review: false
        }
    }

    public var existingPaths: [URL] {
        paths.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    public var isAvailable: Bool { !existingPaths.isEmpty }
}

extension CleanupCategory {
    public static func defaults(
        home: URL,
        isAppInstalled: (String) -> Bool = { isInstalledInApplications($0) }
    ) -> [CleanupCategory] {
        func h(_ relative: String) -> URL { home.appending(path: relative, directoryHint: .isDirectory) }

        let dockerDesktopData = h("Library/Containers/com.docker.docker/Data")
        let dockerDesktopInstalled = isAppInstalled("Docker.app")
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

        if let android = androidSystemImagesCategory(home: home) { categories.append(android) }

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

    private static func androidSystemImagesCategory(home: URL) -> CleanupCategory? {
        let sdk = AndroidSDK(home: home)
        let installed = sdk.installedSystemImages()
        guard !installed.isEmpty else { return nil }

        let unused = sdk.unusedSystemImages()
        var actions: [CleanupAction] = []
        if !unused.isEmpty {
            actions.append(
                CleanupAction(
                    id: "android-unused-images",
                    title: unused.count == installed.count
                        ? "Apagar imagens sem emulador (todas)" : "Apagar imagens sem emulador (\(unused.count) de \(installed.count))",
                    detail: "Nenhum emulador (AVD) usa:\n" + unused.map { "• " + AndroidSDK.displayName(of: $0) }.joined(separator: "\n"),
                    strategy: .deleteItems(unused)
                )
            )
        }
        if unused.count < installed.count {
            actions.append(
                CleanupAction(
                    id: "android-all-images",
                    title: "Apagar todas as imagens",
                    detail: "Emuladores existentes param de abrir até a imagem ser baixada de novo pelo SDK Manager do Android Studio.",
                    strategy: .deleteContents
                )
            )
        }
        actions.append(CleanupAction(id: "android-review-images", title: "Escolher no Explorar…", strategy: .review))

        return CleanupCategory(
            id: "android-system-images",
            title: "Android: imagens de sistema",
            detail: "Imagens dos emuladores Android (\(installed.count) instaladas). Podem ser baixadas de novo pelo SDK Manager.",
            symbol: "smartphone",
            paths: [sdk.systemImagesRoot],
            actions: actions
        )
    }

    public static func isInstalledInApplications(_ bundleName: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(filePath: "/Applications"), home.appending(path: "Applications")].contains {
            FileManager.default.fileExists(atPath: $0.appending(path: bundleName).path(percentEncoded: false))
        }
    }
}
