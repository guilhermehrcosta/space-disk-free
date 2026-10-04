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
        precondition(!actions.isEmpty, "Category \(id) has no actions")
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
                title: String(localized: "Trash"),
                detail: String(localized: "Items already deleted that still take up space."),
                symbol: "trash",
                paths: [h(".Trash")],
                strategy: .emptyTrash
            ),
            CleanupCategory(
                id: "user-caches",
                title: String(localized: "App caches"),
                detail: String(localized: "Temporary files that apps recreate automatically. Quit the apps before cleaning."),
                symbol: "shippingbox",
                paths: [h("Library/Caches")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "logs",
                title: "Logs",
                detail: String(localized: "Diagnostic logs written by apps."),
                symbol: "doc.text.magnifyingglass",
                paths: [h("Library/Logs")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-derived-data",
                title: "Xcode DerivedData",
                detail: String(localized: "Intermediate build files. Xcode rebuilds them when needed."),
                symbol: "hammer",
                paths: [h("Library/Developer/Xcode/DerivedData")],
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-device-support",
                title: "Xcode Device Support",
                detail: String(localized: "Symbols for iOS/watchOS versions of connected devices. Downloaded again when needed."),
                symbol: "iphone",
                paths: ["iOS", "watchOS", "tvOS", "visionOS"].map { h("Library/Developer/Xcode/\($0) DeviceSupport") },
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "xcode-archives",
                title: "Xcode Archives",
                detail: String(localized: "Archived builds, including dSYMs. They go to the Trash, so review them before emptying it."),
                symbol: "archivebox",
                paths: [h("Library/Developer/Xcode/Archives")],
                strategy: .trashContents
            ),
            CleanupCategory(
                id: "simulators",
                title: String(localized: "Simulators"),
                detail: String(
                    localized: "Removes simulators for runtimes that are no longer installed (xcrun simctl delete unavailable)."),
                symbol: "ipad.and.iphone",
                paths: [h("Library/Developer/CoreSimulator/Devices")],
                strategy: .command("xcrun simctl delete unavailable")
            ),
            CleanupCategory(
                id: "dev-caches",
                title: String(localized: "Developer caches"),
                detail: String(localized: "npm, pnpm, Gradle, Cargo and Maven. Downloaded again on demand."),
                symbol: "chevron.left.forwardslash.chevron.right",
                paths: [".npm/_cacache", "Library/pnpm/store", ".pnpm-store", ".gradle/caches", ".cargo/registry/cache", ".m2/repository"]
                    .map(h),
                strategy: .deleteContents
            ),
            CleanupCategory(
                id: "go",
                title: "Go",
                detail: String(localized: "Downloaded modules (~/go/pkg/mod) and the build cache. Downloaded again on demand."),
                symbol: "g.circle",
                paths: [h("go/pkg/mod"), h("Library/Caches/go-build")],
                strategy: .command("go clean -modcache -cache")
            ),
            CleanupCategory(
                id: "homebrew",
                title: "Homebrew",
                detail: String(localized: "Old downloads and outdated versions (brew cleanup --prune=all)."),
                symbol: "mug",
                paths: [h("Library/Caches/Homebrew")],
                strategy: .command("brew cleanup --prune=all")
            ),
            CleanupCategory(
                id: "docker",
                title: "Docker",
                detail:
                    String(
                        localized:
                            "Virtual machine disks for Docker Desktop, Rancher Desktop or Colima. Cleaned by the docker CLI in the current context, so the engine must be running."
                    ),
                symbol: "cube.box",
                paths: dockerEngineDisks,
                actions: [
                    CleanupAction(
                        id: "docker-prune",
                        title: String(localized: "Quick cleanup"),
                        detail: String(localized: "Removes stopped containers, unused networks, dangling images and the build cache."),
                        strategy: .command("docker system prune -f")
                    ),
                    CleanupAction(
                        id: "docker-prune-all",
                        title: String(localized: "Full cleanup"),
                        detail:
                            String(
                                localized:
                                    "Also removes every image no container uses (downloaded again when needed) and the whole build cache. Volumes are kept."
                            ),
                        strategy: .command("docker system prune --all --force")
                    ),
                    CleanupAction(
                        id: "docker-volumes",
                        title: String(localized: "Remove unused volumes…"),
                        detail:
                            String(
                                localized:
                                    "Deletes the data in volumes no container uses, such as databases from stopped projects. This can't be undone."
                            ),
                        strategy: .command("docker volume prune --all --force")
                    ),
                ]
            ),
            CleanupCategory(
                id: "ios-backups",
                title: String(localized: "iPhone/iPad backups"),
                detail: String(localized: "Local device backups. Review them and delete the old ones."),
                symbol: "externaldrive.badge.timemachine",
                paths: [h("Library/Application Support/MobileSync/Backup")],
                strategy: .review
            ),
            CleanupCategory(
                id: "downloads",
                title: "Downloads",
                detail: String(localized: "Downloaded files. Review the largest items."),
                symbol: "arrow.down.circle",
                paths: [h("Downloads")],
                strategy: .review
            ),
        ]

        if let android = androidSystemImagesCategory(home: home) { categories.append(android) }
        if let lmStudio = lmStudioModelsCategory(home: home) { categories.append(lmStudio) }

        if !dockerDesktopInstalled {
            categories.append(
                CleanupCategory(
                    id: "docker-desktop-leftover",
                    title: String(localized: "Docker Desktop (uninstalled)"),
                    detail: String(
                        localized:
                            "Virtual disk (Docker.raw) from a Docker Desktop that is no longer installed, with old images and volumes."),
                    symbol: "shippingbox.and.arrow.backward",
                    paths: [dockerDesktopData],
                    strategy: .trashContents
                )
            )
        }
        return categories
    }

    private static func lmStudioModelsCategory(home: URL) -> CleanupCategory? {
        let lmStudio = LMStudio(home: home)
        let models = lmStudio.installedModels()
        guard !models.isEmpty, lmStudio.modelsDirectory.normalizedPath.hasPrefix(home.normalizedPath + "/") else { return nil }

        var actions = models.map { model in
            let size = SizeCalculator.measure(model).bytes.formattedBytes
            return CleanupAction(
                id: "lmstudio-delete-" + LMStudio.displayName(of: model),
                title: String(localized: "Delete \(model.lastPathComponent) (\(size))"),
                detail: LMStudio.displayName(of: model) + "\n" + String(localized: "It can be downloaded again in LM Studio."),
                strategy: .deleteItems([model])
            )
        }
        if models.count > 1 {
            actions.append(
                CleanupAction(
                    id: "lmstudio-delete-all",
                    title: String(localized: "Delete all models"),
                    detail: models.map { "• " + LMStudio.displayName(of: $0) }.joined(separator: "\n"),
                    strategy: .deleteItems(models)
                )
            )
        }
        actions.append(CleanupAction(id: "lmstudio-review", title: String(localized: "Choose in Explore…"), strategy: .review))

        return CleanupCategory(
            id: "lmstudio-models",
            title: String(localized: "LM Studio models"),
            detail: String(
                localized: "Downloaded language models (\(models.count) installed). Eject a model in LM Studio before deleting it."),
            symbol: "brain",
            paths: [lmStudio.modelsDirectory],
            actions: actions
        )
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
                        ? String(localized: "Delete images without an emulator (all)")
                        : String(localized: "Delete images without an emulator (\(unused.count) of \(installed.count))"),
                    detail: String(localized: "No emulator (AVD) uses:") + "\n"
                        + unused.map { "• " + AndroidSDK.displayName(of: $0) }.joined(separator: "\n"),
                    strategy: .deleteItems(unused)
                )
            )
        }
        if unused.count < installed.count {
            actions.append(
                CleanupAction(
                    id: "android-all-images",
                    title: String(localized: "Delete all images"),
                    detail: String(
                        localized: "Existing emulators won't start until the image is downloaded again from the Android Studio SDK Manager."
                    ),
                    strategy: .deleteContents
                )
            )
        }
        actions.append(CleanupAction(id: "android-review-images", title: String(localized: "Choose in Explore…"), strategy: .review))

        return CleanupCategory(
            id: "android-system-images",
            title: String(localized: "Android: system images"),
            detail: String(
                localized: "Android emulator images (\(installed.count) installed). They can be downloaded again from the SDK Manager."),
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
