import Foundation
import Testing

@testable import DiskCore

struct SizeCalculatorTests {
    @Test func measuresNestedFilesAndCountsHardLinksOnce() throws {
        let root = try TemporaryDirectory()
        let nested = root.url.appending(path: "a/b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appending(path: "data.bin")
        try Data(repeating: 1, count: 1_000_000).write(to: file)

        let single = SizeCalculator.measure(root.url).bytes
        #expect(single >= 1_000_000)

        try FileManager.default.linkItem(at: file, to: root.url.appending(path: "hardlink.bin"))
        #expect(SizeCalculator.measure(root.url).bytes == single)
    }

    @Test func missingPathMeasuresZero() {
        let result = SizeCalculator.measure(URL(filePath: "/nao/existe/\(UUID())"))
        #expect(result == SizeResult())
    }
}

struct SafetyPolicyTests {
    let policy = SafetyPolicy(home: URL(filePath: "/Users/teste"))

    @Test(arguments: [
        "/Users/teste", "/Users/teste/Library", "/Users/teste/Documents", "/Users/teste/Library/Application Support",
        "/Users/teste/Library/Caches/../Containers",
    ])
    func neverClearsCriticalFolders(path: String) {
        #expect(!policy.canClearContents(of: URL(filePath: path)))
    }

    @Test(arguments: ["/Users/teste/Library/Caches", "/Users/teste/.Trash", "/Users/teste/Library/Developer/Xcode/DerivedData"])
    func clearsRegenerableFolders(path: String) {
        #expect(policy.canClearContents(of: URL(filePath: path)))
    }

    @Test(arguments: ["/System/Library", "/usr", "/Users/outro/Library/Caches", "/Users/teste-falso/Library/Caches"])
    func neverTouchesOutsideHome(path: String) {
        #expect(!policy.canClearContents(of: URL(filePath: path)))
        #expect(!policy.canTrash(URL(filePath: path)))
    }

    @Test func trashRules() {
        #expect(policy.canTrash(URL(filePath: "/Users/teste/Downloads/video.mov")))
        #expect(policy.canTrash(URL(filePath: "/Applications/Antigo.app")))
        #expect(!policy.canTrash(URL(filePath: "/Users/teste/Downloads")))
        #expect(!policy.canTrash(URL(filePath: "/Applications")))
        #expect(!policy.canTrash(URL(filePath: "/Users/teste/Library/Mobile Documents/com~apple~CloudDocs/a.txt")))
    }
}

struct CleanerTests {
    @Test func deleteContentsKeepsFolderAndFreesSpace() async throws {
        let home = try TemporaryDirectory()
        let cache = home.url.appending(path: "Library/Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache.appending(path: "app"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 500_000).write(to: cache.appending(path: "app/blob"))

        let category = CleanupCategory(id: "c", title: "C", detail: "", symbol: "x", paths: [cache], strategy: .deleteContents)
        let report = try await Cleaner(policy: SafetyPolicy(home: home.url)).run(category)

        #expect(report.reclaimedBytes >= 500_000)
        #expect(report.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path(percentEncoded: false)).isEmpty)
    }

    @Test func refusesCategoryPointingAtProtectedFolder() async throws {
        let home = try TemporaryDirectory()
        let documents = home.url.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data([1]).write(to: documents.appending(path: "importante.txt"))

        let category = CleanupCategory(id: "x", title: "X", detail: "", symbol: "x", paths: [documents], strategy: .deleteContents)
        await #expect(throws: CleanerError.self) {
            try await Cleaner(policy: SafetyPolicy(home: home.url)).run(category)
        }
        #expect(FileManager.default.fileExists(atPath: documents.appending(path: "importante.txt").path(percentEncoded: false)))
    }

    @Test func commandActionReportsLastOutputLine() async throws {
        let home = try TemporaryDirectory()
        let folder = home.url.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let category = CleanupCategory(
            id: "cmd", title: "Cmd", detail: "", symbol: "x", paths: [folder],
            actions: [
                CleanupAction(id: "ok", title: "Ok", strategy: .command("echo inicio; echo 'Total reclaimed space: 1GB'; echo")),
                CleanupAction(id: "fail", title: "Falha", strategy: .command("echo 'daemon parado' >&2; exit 3")),
            ]
        )
        let cleaner = Cleaner(policy: SafetyPolicy(home: home.url))

        let ok = try await cleaner.run(category)
        #expect(ok.commandOutput == "Total reclaimed space: 1GB")
        #expect(ok.commandError == nil)

        let failed = try await cleaner.run(category, action: category.actions[1])
        #expect(failed.commandError == "daemon parado")
    }

    @Test func refusesActionFromAnotherCategory() async throws {
        let home = try TemporaryDirectory()
        let category = CleanupCategory(id: "a", title: "A", detail: "", symbol: "x", paths: [], strategy: .deleteContents)
        let foreign = CleanupAction(id: "rm", title: "rm", strategy: .command("rm -rf ~"))
        await #expect(throws: CleanerError.self) {
            try await Cleaner(policy: SafetyPolicy(home: home.url)).run(category, action: foreign)
        }
    }

    @Test func dockerDesktopDataIsLeftoverOnlyWhenTheAppIsGone() {
        let home = URL(filePath: "/Users/teste")
        let data = home.appending(path: "Library/Containers/com.docker.docker/Data", directoryHint: .isDirectory)

        let uninstalled = CleanupCategory.defaults(home: home, isAppInstalled: { _ in false })
        #expect(uninstalled.first { $0.id == "docker-desktop-leftover" }?.paths == [data])
        #expect(uninstalled.first { $0.id == "docker-desktop-leftover" }?.strategy == .trashContents)
        #expect(uninstalled.first { $0.id == "docker" }?.paths.contains(data) == false)

        let installed = CleanupCategory.defaults(home: home, isAppInstalled: { $0 == "Docker.app" })
        #expect(installed.contains { $0.id == "docker-desktop-leftover" } == false)
        #expect(installed.first { $0.id == "docker" }?.paths.contains(data) == true)
    }

    @Test func defaultCategoriesAreAllAllowedByPolicy() {
        let home = URL(filePath: "/Users/teste")
        let policy = SafetyPolicy(home: home)
        let categories =
            CleanupCategory.defaults(home: home, isAppInstalled: { _ in true })
            + CleanupCategory.defaults(home: home, isAppInstalled: { _ in false })
        for installed in [true, false] {
            let ids = CleanupCategory.defaults(home: home, isAppInstalled: { _ in installed }).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
        for category in categories where category.strategy != .review {
            for path in category.paths {
                #expect(policy.canClearContents(of: path), "\(path)")
            }
        }
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        url = base.appending(path: "DiskCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct TreeMeasurementTests {
    @Test func recordsImmediateSubfoldersInTheSamePass() throws {
        let root = try TemporaryDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: root.url.appending(path: "a/inner"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.url.appending(path: "b"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 300_000).write(to: root.url.appending(path: "a/inner/x.bin"))
        try Data(repeating: 1, count: 100_000).write(to: root.url.appending(path: "b/y.bin"))
        try Data(repeating: 1, count: 50_000).write(to: root.url.appending(path: "top.bin"))

        let tree = SizeCalculator.measureTree(root.url)

        #expect(Set(tree.children.keys) == [root.url.appending(path: "a").normalizedPath, root.url.appending(path: "b").normalizedPath])
        #expect(tree.children[root.url.appending(path: "a").normalizedPath] == SizeCalculator.measure(root.url.appending(path: "a")))
        #expect(tree.children[root.url.appending(path: "b").normalizedPath] == SizeCalculator.measure(root.url.appending(path: "b")))
        #expect(tree.total == SizeCalculator.measure(root.url))
    }
}

struct DirectorySizeCacheTests {
    let home = URL(filePath: "/Users/teste")
    var library: URL { home.appending(path: "Library") }
    var caches: URL { home.appending(path: "Library/Caches") }
    var app: URL { home.appending(path: "Library/Caches/app") }

    func filled() -> DirectorySizeCache {
        var cache = DirectorySizeCache()
        cache.record(home, SizeResult(bytes: 1000))
        cache.record(library, SizeResult(bytes: 600))
        cache.record(caches, SizeResult(bytes: 400))
        cache.record(app, SizeResult(bytes: 300))
        return cache
    }

    @Test func trailingSlashAndDotsHitTheSameEntry() {
        let cache = filled()
        #expect(cache.entry(for: URL(filePath: "/Users/teste/Library/", directoryHint: .isDirectory))?.result.bytes == 600)
        #expect(cache.entry(for: URL(filePath: "/Users/teste/Library/Caches/../"))?.result.bytes == 600)
    }

    @Test func expiresOldEntries() {
        var cache = DirectorySizeCache(maxAge: 60)
        cache.record(library, SizeResult(bytes: 1), at: .now.addingTimeInterval(-120))
        #expect(cache.entry(for: library) == nil)
    }

    @Test func removingAnItemDiscountsAncestorsAndDropsItsSubtree() {
        var cache = filled()
        cache.remove(caches, knownBytes: nil)

        #expect(cache.entry(for: caches) == nil)
        #expect(cache.entry(for: app) == nil)
        #expect(cache.entry(for: library)?.result.bytes == 200)
        #expect(cache.entry(for: home)?.result.bytes == 600)
    }

    @Test func removingAnUncachedFileUsesItsKnownSize() {
        var cache = filled()
        cache.remove(app.appending(path: "blob.bin"), knownBytes: 50)
        #expect(cache.entry(for: app)?.result.bytes == 250)
        #expect(cache.entry(for: home)?.result.bytes == 950)
    }

    @Test func removingWithUnknownSizeForgetsAncestors() {
        var cache = filled()
        cache.remove(app.appending(path: "folder"), knownBytes: nil)
        #expect(cache.entry(for: app) == nil)
        #expect(cache.entry(for: home) == nil)
    }

    @Test func updateReplacesContentsAndAdjustsAncestorsByTheDifference() {
        var cache = filled()
        cache.update(caches, SizeResult(bytes: 100))

        #expect(cache.entry(for: caches)?.result.bytes == 100)
        #expect(cache.entry(for: app) == nil)
        #expect(cache.entry(for: library)?.result.bytes == 300)
        #expect(cache.entry(for: home)?.result.bytes == 700)
    }

    @Test func rootFolderIsNotItsOwnAncestor() {
        var cache = DirectorySizeCache()
        cache.record(URL(filePath: "/"), SizeResult(bytes: 500))
        cache.record(URL(filePath: "/Users"), SizeResult(bytes: 200))
        cache.removeDescendants(of: URL(filePath: "/"))

        #expect(cache.entry(for: URL(filePath: "/"))?.result.bytes == 500)
        #expect(cache.entry(for: URL(filePath: "/Users")) == nil)
    }
}

struct AndroidSDKTests {
    func makeHome() throws -> TemporaryDirectory {
        let home = try TemporaryDirectory()
        let fm = FileManager.default
        for image in ["android-31/google_apis/arm64-v8a", "android-30/google_apis_playstore/x86_64", "android-33/google_apis/arm64-v8a"] {
            let dir = home.url.appending(path: "Library/Android/sdk/system-images/\(image)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 10_000).write(to: dir.appending(path: "system.img"))
        }
        let avd = home.url.appending(path: ".android/avd/Pixel.avd")
        try fm.createDirectory(at: avd, withIntermediateDirectories: true)
        try "hw.ram=2048\nimage.sysdir.1=system-images/android-33/google_apis/arm64-v8a/\n"
            .write(to: avd.appending(path: "config.ini"), atomically: true, encoding: .utf8)
        return home
    }

    @Test func findsImagesNotUsedByAnyEmulator() throws {
        let home = try makeHome()
        let sdk = AndroidSDK(home: home.url)

        #expect(sdk.installedSystemImages().count == 3)
        #expect(
            sdk.unusedSystemImages().map(AndroidSDK.displayName) == [
                "API 30 · google_apis_playstore · x86_64", "API 31 · google_apis · arm64-v8a",
            ])
    }

    @Test func deletesOnlyUnusedImagesAndPrunesEmptyFolders() async throws {
        let home = try makeHome()
        let sdk = AndroidSDK(home: home.url)
        let category = try #require(CleanupCategory.defaults(home: home.url).first { $0.id == "android-system-images" })
        #expect(category.actions.map(\.id) == ["android-unused-images", "android-all-images", "android-review-images"])

        let report = try await Cleaner(policy: SafetyPolicy(home: home.url)).run(category)

        #expect(report.failures.isEmpty)
        #expect(report.reclaimedBytes >= 20_000)
        #expect(sdk.installedSystemImages().map(AndroidSDK.displayName) == ["API 33 · google_apis · arm64-v8a"])
        let apis = try FileManager.default.contentsOfDirectory(atPath: sdk.systemImagesRoot.path(percentEncoded: false))
        #expect(apis == ["android-33"])
    }

    @Test func refusesItemsOutsideTheCategoryFolders() async throws {
        let home = try makeHome()
        let outside = home.url.appending(path: "Documents/importante.txt")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: outside)
        let sdk = AndroidSDK(home: home.url)
        let category = CleanupCategory(
            id: "x", title: "X", detail: "", symbol: "x", paths: [sdk.systemImagesRoot],
            strategy: .deleteItems([sdk.installedSystemImages()[0], outside])
        )

        await #expect(throws: CleanerError.self) {
            try await Cleaner(policy: SafetyPolicy(home: home.url)).run(category)
        }
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
        #expect(sdk.installedSystemImages().count == 3)
    }
}

struct LocalizationTests {
    static let resources = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Resources")

    struct Catalog: Decodable {
        struct Entry: Decodable {
            var extractionState: String?
            var localizations: [String: Localization]?
        }
        struct Localization: Decodable {
            struct StringUnit: Decodable {
                var state: String
                var value: String
            }
            var stringUnit: StringUnit?
        }
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    static func placeholders(in text: String) -> [String] {
        text.matches(of: #/%(?:\d+\$)?(@|lld|ld|d|f)/#).map { String($0.output.1) }.sorted()
    }

    @Test(arguments: ["Localizable.xcstrings", "InfoPlist.xcstrings"])
    func everyStringHasABrazilianPortugueseTranslation(file: String) throws {
        let data = try Data(contentsOf: Self.resources.appending(path: file))
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        #expect(catalog.sourceLanguage == "en")
        #expect(!catalog.strings.isEmpty)

        for (key, entry) in catalog.strings where entry.extractionState != "stale" {
            let unit = entry.localizations?["pt-BR"]?.stringUnit
            #expect(unit?.state == "translated", "\(key)")
            #expect(unit?.value.isEmpty == false, "\(key)")
            if let value = unit?.value, !file.hasPrefix("InfoPlist") {
                #expect(Self.placeholders(in: value) == Self.placeholders(in: key), "\(key)")
            }
        }
    }
}
