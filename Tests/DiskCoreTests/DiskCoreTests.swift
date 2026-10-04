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

    @Test func defaultCategoriesAreAllAllowedByPolicy() {
        let home = URL(filePath: "/Users/teste")
        let policy = SafetyPolicy(home: home)
        let categories = CleanupCategory.defaults(home: home)
        #expect(Set(categories.map(\.id)).count == categories.count)
        for category in categories where category.strategy != .review {
            for path in category.paths {
                #expect(policy.canClearContents(of: path), "\(path)")
            }
        }
    }
}

/// Diretório temporário apagado ao sair de escopo. Usa o caminho real (sem o symlink /var → /private/var).
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
