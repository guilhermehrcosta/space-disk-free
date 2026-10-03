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
