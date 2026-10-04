import AppKit
import DiskCore
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppState {
    struct CategoryStatus {
        var size: UInt64?
        var isScanning = false
        var isCleaning = false
        var permissionDenied = false
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmTitle: String
        let isDestructive: Bool
        let action: @MainActor () async -> Void
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let explorer: ExplorerModel
    private let cleaner: Cleaner

    private(set) var volume: VolumeStatus?
    private(set) var categories: [CleanupCategory] = []
    private(set) var status: [String: CategoryStatus] = [:]
    private(set) var lastScan: Date?
    private(set) var toast: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var pendingConfirmation: Confirmation?

    private var scanTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        cleaner = Cleaner(policy: SafetyPolicy(home: home))
        explorer = ExplorerModel(root: home)
        refreshVolume()
        scanCategories()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshVolume()
            }
        }
    }

    // MARK: - Derivados

    var isScanning: Bool { status.values.contains { $0.isScanning } }

    var needsFullDiskAccess: Bool {
        status.values.contains { $0.permissionDenied } || explorer.permissionDenied
    }

    var reclaimableBytes: UInt64 {
        categories
            .filter(\.countsTowardReclaimable)
            .compactMap { status[$0.id]?.size }
            .reduce(0, +)
    }

    // MARK: - Varredura

    func refreshVolume() {
        volume = VolumeStatus.current()
    }

    /// Chamado ao abrir o menu: só refaz a varredura se a última tiver mais de 5 minutos.
    func refreshIfStale() {
        refreshVolume()
        if let lastScan, Date.now.timeIntervalSince(lastScan) < 300 { return }
        scanCategories()
    }

    func scanCategories() {
        scanTask?.cancel()
        categories = CleanupCategory.defaults(home: home).filter(\.isAvailable)
        for category in categories {
            status[category.id, default: CategoryStatus()].isScanning = true
        }

        let categories = categories
        scanTask = Task {
            await withTaskGroup(of: (String, [(URL, TreeMeasurement)]).self) { group in
                for category in categories {
                    group.addTask { (category.id, Self.measure(category)) }
                }
                for await (id, measurements) in group {
                    guard !Task.isCancelled else { return }
                    apply(measurements, to: id)
                    // As mesmas pastas aparecem no explorador: aproveita a medição.
                    for (url, measurement) in measurements { explorer.record(url, measurement) }
                }
            }
            if !Task.isCancelled { lastScan = .now }
        }
    }

    private func rescan(_ category: CleanupCategory) async {
        status[category.id]?.isScanning = true
        let measurements = await Task.detached { Self.measure(category) }.value
        apply(measurements, to: category.id)
        for (url, measurement) in measurements { explorer.contentsChanged(at: url, measurement) }
    }

    nonisolated private static func measure(_ category: CleanupCategory) -> [(URL, TreeMeasurement)] {
        category.existingPaths.map { ($0, SizeCalculator.measureTree($0)) }
    }

    private func apply(_ measurements: [(URL, TreeMeasurement)], to id: String) {
        let total = measurements.reduce(SizeResult()) { $0 + $1.1.total }
        status[id]?.size = total.bytes
        status[id]?.permissionDenied = total.permissionDenied
        status[id]?.isScanning = false
    }

    // MARK: - Limpeza

    func requestCleanup(_ category: CleanupCategory, action: CleanupAction? = nil) {
        let action = action ?? category.actions[0]
        let size = status[category.id]?.size?.formattedBytes ?? "?"
        let extra = action.detail.map { "\n\($0)" } ?? "\n\(category.detail)"
        let (message, confirmTitle, destructive): (String, String, Bool) =
            switch action.strategy {
            case .deleteContents:
                ("\(size) serão apagados permanentemente.\(extra)", "Apagar", true)
            case .deleteItems:
                ("Serão apagados permanentemente.\(extra)", "Apagar", true)
            case .trashContents:
                ("\(size) serão movidos para a Lixeira.", "Mover para Lixeira", false)
            case .emptyTrash:
                ("\(size) serão apagados permanentemente. Não é possível desfazer.", "Esvaziar", true)
            case .command(let command):
                ("Será executado:\n\(command)\n\(extra)", "Executar", true)
            case .review:
                ("", "", false)
            }
        if case .review = action.strategy { return }

        // "Remover volumes sem uso…" vira "Docker: Remover volumes sem uso?".
        let actionTitle = action.title.trimmingCharacters(in: CharacterSet(charactersIn: "…"))
        pendingConfirmation = Confirmation(
            title: category.actions.count > 1 ? "\(category.title): \(actionTitle)?" : "Limpar \(category.title)?",
            message: message,
            confirmTitle: confirmTitle,
            isDestructive: destructive,
            action: { [weak self] in await self?.performCleanup(category, action: action) }
        )
    }

    private func performCleanup(_ category: CleanupCategory, action: CleanupAction) async {
        status[category.id]?.isCleaning = true
        defer { status[category.id]?.isCleaning = false }

        do {
            let report = try await cleaner.run(category, action: action)
            showToast(Self.summary(of: report, category: category))
        } catch {
            showToast(error.localizedDescription)
        }
        await rescan(category)
        refreshVolume()

        // Ferramentas como o Docker devolvem o espaço ao macOS aos poucos (o Docker.raw
        // encolhe depois do prune). Mede de novo um pouco depois para mostrar o valor real.
        if case .command = action.strategy {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                await self?.rescan(category)
                self?.refreshVolume()
            }
        }
    }

    private static func summary(of report: CleanupReport, category: CleanupCategory) -> String {
        if let error = report.commandError { return "\(category.title): \(error)" }
        // Comandos externos costumam informar quanto liberaram; pouco espaço medido na hora
        // geralmente significa que o espaço ainda vai ser devolvido (ex.: Docker).
        if let output = report.commandOutput, report.reclaimedBytes < 1_000_000 {
            return "\(category.title): \(output)"
        }
        var text =
            report.movedToTrash
            ? "\(report.reclaimedBytes.formattedBytes) movidos para a Lixeira"
            : "\(report.reclaimedBytes.formattedBytes) liberados em \(category.title)"
        if !report.failures.isEmpty {
            text += " · \(report.failures.count) itens em uso ou protegidos foram mantidos"
        }
        return text
    }

    func requestTrash(_ node: FileNode) {
        guard cleaner.policy.canTrash(node.url) else {
            showToast("\(node.name) é uma pasta protegida e não pode ser removida.")
            return
        }
        let size = node.size?.formattedBytes ?? "?"
        pendingConfirmation = Confirmation(
            title: "Mover “\(node.name)” para a Lixeira?",
            message: "\(size) · \(node.url.path(percentEncoded: false).abbreviatingHome)",
            confirmTitle: "Mover para Lixeira",
            isDestructive: false,
            action: { [weak self] in self?.performTrash(node) }
        )
    }

    private func performTrash(_ node: FileNode) {
        do {
            try cleaner.trash(node.url)
            explorer.remove(node)
            showToast("“\(node.name)” foi para a Lixeira")
            if let trash = categories.first(where: { $0.id == "trash" }) {
                Task { await rescan(trash) }
            }
        } catch {
            showToast("Não foi possível mover: \(error.localizedDescription)")
        }
    }

    // MARK: - Sistema

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showToast("Não foi possível alterar: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { toast = nil }
        }
    }
}

extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
