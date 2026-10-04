import Foundation

public struct CleanupReport: Sendable, Equatable {
    public var reclaimedBytes: UInt64 = 0
    public var movedToTrash = false
    public var failures: [String] = []
    public var commandError: String?
    public var commandOutput: String?

    public var succeeded: Bool { failures.isEmpty && commandError == nil }
}

public enum CleanerError: LocalizedError {
    case blockedBySafetyPolicy(String)
    case unknownAction(String)

    public var errorDescription: String? {
        switch self {
        case .blockedBySafetyPolicy(let path): "Operação bloqueada por segurança: \(path)"
        case .unknownAction(let id): "Ação desconhecida: \(id)"
        }
    }
}

public struct Cleaner: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func run(_ category: CleanupCategory, action: CleanupAction? = nil) async throws -> CleanupReport {
        let action = action ?? category.actions[0]
        guard category.actions.contains(action) else { throw CleanerError.unknownAction(action.id) }

        let paths = category.existingPaths
        for path in paths where !policy.canClearContents(of: path) {
            throw CleanerError.blockedBySafetyPolicy(path.path(percentEncoded: false))
        }

        let before = SizeCalculator.measure(paths).bytes
        var report = CleanupReport()

        switch action.strategy {
        case .deleteContents:
            for path in paths { report.failures += removeContents(of: path) }
        case .deleteItems(let items):
            report.failures = try deleteItems(items, within: paths)
        case .trashContents:
            report.movedToTrash = true
            for path in paths { report.failures += trashContents(of: path) }
        case .emptyTrash:
            report = try await emptyTrash(paths)
        case .command(let command):
            let result = await Shell.run(command)
            if result.succeeded {
                report.commandOutput = result.lastLine
            } else {
                report.commandError = result.lastLine ?? "Falhou."
            }
        case .review:
            return report
        }

        let after = SizeCalculator.measure(paths).bytes
        report.reclaimedBytes = before > after ? before - after : 0
        return report
    }

    public func trash(_ url: URL) throws {
        guard policy.canTrash(url) else {
            throw CleanerError.blockedBySafetyPolicy(url.path(percentEncoded: false))
        }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func deleteItems(_ items: [URL], within roots: [URL]) throws -> [String] {
        let rootPaths = roots.map { $0.resolvingSymlinksInPath().normalizedPath }
        func root(of item: URL) -> String? {
            let path = item.resolvingSymlinksInPath().normalizedPath
            return rootPaths.first { path.hasPrefix($0 + "/") }
        }
        for item in items where root(of: item) == nil {
            throw CleanerError.blockedBySafetyPolicy(item.path(percentEncoded: false))
        }

        var failures: [String] = []
        for item in items {
            if Task.isCancelled { break }
            do {
                let itemRoot = root(of: item)!
                try FileManager.default.removeItem(at: item)
                removeEmptyParents(of: item.resolvingSymlinksInPath(), upTo: itemRoot)
            } catch {
                failures.append(item.lastPathComponent)
            }
        }
        return failures
    }

    private func removeEmptyParents(of item: URL, upTo rootPath: String) {
        var parent = item.deletingLastPathComponent()
        while parent.normalizedPath.hasPrefix(rootPath + "/") {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: parent.path(percentEncoded: false))) ?? ["?"]
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
            guard (try? FileManager.default.removeItem(at: parent)) != nil else { return }
            parent = parent.deletingLastPathComponent()
        }
    }

    private func removeContents(of directory: URL) -> [String] {
        forEachChild(of: directory) { try FileManager.default.removeItem(at: $0) }
    }

    private func trashContents(of directory: URL) -> [String] {
        forEachChild(of: directory) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    }

    private func forEachChild(of directory: URL, _ body: (URL) throws -> Void) -> [String] {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            return [directory.lastPathComponent]
        }
        var failures: [String] = []
        for child in children {
            if Task.isCancelled { break }
            do { try body(child) } catch { failures.append(child.lastPathComponent) }
        }
        return failures
    }

    private func emptyTrash(_ paths: [URL]) async throws -> CleanupReport {
        var report = CleanupReport()
        let readable = paths.allSatisfy { (try? FileManager.default.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) != nil }
        if readable {
            for path in paths { report.failures += removeContents(of: path) }
        } else {
            let result = await Shell.run(#"osascript -e 'tell application "Finder" to empty trash'"#)
            if !result.succeeded { report.commandError = result.lastLine ?? "Falhou." }
        }
        return report
    }
}

enum Shell {
    struct Result {
        var succeeded: Bool
        var lastLine: String?
    }

    static func run(_ command: String) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(command))
            }
        }
    }

    private static func runBlocking(_ command: String) -> Result {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do { try process.run() } catch { return Result(succeeded: false, lastLine: error.localizedDescription) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let status = process.terminationStatus
        if status == 127 { return Result(succeeded: false, lastLine: "Ferramenta não encontrada.") }
        let lastLine = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return Result(succeeded: status == 0, lastLine: lastLine ?? (status == 0 ? nil : "Falhou (código \(status))."))
    }
}
