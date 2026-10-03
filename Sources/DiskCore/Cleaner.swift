import Foundation

public struct CleanupReport: Sendable, Equatable {
    /// Bytes que deixaram as pastas da categoria.
    public var reclaimedBytes: UInt64 = 0
    /// Os itens foram para a Lixeira, então o espaço só é liberado ao esvaziá-la.
    public var movedToTrash = false
    /// Nomes de itens que não puderam ser removidos (em uso, protegidos pelo sistema, sem permissão).
    public var failures: [String] = []
    /// Saída de erro de um comando externo, quando houver.
    public var commandError: String?

    public var succeeded: Bool { failures.isEmpty && commandError == nil }
}

public enum CleanerError: LocalizedError {
    case blockedBySafetyPolicy(String)

    public var errorDescription: String? {
        switch self {
        case .blockedBySafetyPolicy(let path): "Operação bloqueada por segurança: \(path)"
        }
    }
}

public struct Cleaner: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func run(_ category: CleanupCategory) async throws -> CleanupReport {
        let paths = category.existingPaths
        for path in paths where !policy.canClearContents(of: path) {
            throw CleanerError.blockedBySafetyPolicy(path.path(percentEncoded: false))
        }

        let before = SizeCalculator.measure(paths).bytes
        var report = CleanupReport()

        switch category.strategy {
        case .deleteContents:
            for path in paths { report.failures += removeContents(of: path) }
        case .trashContents:
            report.movedToTrash = true
            for path in paths { report.failures += trashContents(of: path) }
        case .emptyTrash:
            report = try await emptyTrash(paths)
        case .command(let command):
            report.commandError = await Shell.run(command)
        case .review:
            return report
        }

        let after = SizeCalculator.measure(paths).bytes
        report.reclaimedBytes = before > after ? before - after : 0
        return report
    }

    /// Move um único item para a Lixeira (usado pela aba Explorar).
    public func trash(_ url: URL) throws {
        guard policy.canTrash(url) else {
            throw CleanerError.blockedBySafetyPolicy(url.path(percentEncoded: false))
        }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
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
            // Sem Acesso Total ao Disco a ~/.Trash não é legível; o Finder consegue esvaziá-la.
            report.commandError = await Shell.run(#"osascript -e 'tell application "Finder" to empty trash'"#)
        }
        return report
    }
}

enum Shell {
    /// Executa `command` num zsh de login (para herdar o PATH do usuário, ex.: Homebrew).
    /// Retorna `nil` em caso de sucesso ou a mensagem de erro.
    static func run(_ command: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(command))
            }
        }
    }

    private static func runBlocking(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do { try process.run() } catch { return error.localizedDescription }
        // Ler até EOF antes de esperar evita travar quando a saída enche o buffer do pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return nil }
        if process.terminationStatus == 127 { return "Ferramenta não encontrada." }
        let lastLine = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last.map(String.init)
        return lastLine ?? "Falhou (código \(process.terminationStatus))."
    }
}
