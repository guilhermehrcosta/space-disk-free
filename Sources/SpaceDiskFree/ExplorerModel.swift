import AppKit
import DiskCore
import SwiftUI

/// Navegação pelas maiores pastas: lista os filhos do diretório atual e mede cada subpasta em paralelo.
@MainActor
@Observable
final class ExplorerModel {
    private(set) var current: URL
    private(set) var nodes: [FileNode] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var permissionDenied = false
    private var history: [URL] = []
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    /// Quantas subpastas medir ao mesmo tempo. Mais que isso disputa I/O sem ganho real.
    private let maxConcurrentMeasurements = 4

    init(root: URL) {
        current = root
    }

    var canGoBack: Bool { !history.isEmpty }
    var largestSize: UInt64 { nodes.compactMap(\.size).max() ?? 0 }
    var totalSize: UInt64 { nodes.compactMap(\.size).reduce(0, +) }

    func loadIfNeeded() {
        if !hasLoaded { load(current) }
    }

    /// Abre `url` como nova raiz de navegação.
    func open(_ url: URL) {
        history.removeAll()
        load(url)
    }

    func enter(_ node: FileNode) {
        guard node.canEnter else { return }
        history.append(current)
        load(node.url)
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        load(previous)
    }

    func reload() {
        load(current)
    }

    func remove(_ node: FileNode) {
        nodes.removeAll { $0.id == node.id }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = current
        panel.prompt = "Analisar"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    private func load(_ url: URL) {
        loadTask?.cancel()
        hasLoaded = true
        current = url
        nodes = []
        errorMessage = nil
        permissionDenied = false
        isLoading = true

        loadTask = Task {
            do {
                let listing = try await Task.detached { try DirectoryLister.children(of: url) }.value
                guard !Task.isCancelled else { return }
                nodes = Self.sorted(listing)
                await measureDirectories(in: listing)
            } catch {
                guard !Task.isCancelled else { return }
                let code = (error as NSError).underlyingErrors.first.map { ($0 as NSError).code }
                permissionDenied =
                    [Int(EPERM), Int(EACCES)].contains(code)
                    || (error as NSError).code == NSFileReadNoPermissionError
                errorMessage = permissionDenied ? "Sem permissão para ler esta pasta." : error.localizedDescription
            }
            if !Task.isCancelled { isLoading = false }
        }
    }

    private func measureDirectories(in listing: [FileNode]) async {
        var pending = listing.filter { $0.size == nil }.map(\.url).makeIterator()

        await withTaskGroup(of: (URL, SizeResult).self) { group in
            func enqueueNext() {
                guard let url = pending.next() else { return }
                group.addTask { (url, SizeCalculator.measure(url)) }
            }
            for _ in 0..<maxConcurrentMeasurements { enqueueNext() }

            while let (url, result) = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                if let index = nodes.firstIndex(where: { $0.url == url }) {
                    nodes[index].size = result.bytes
                }
                if result.permissionDenied { permissionDenied = true }
                nodes = Self.sorted(nodes)
                enqueueNext()
            }
        }
    }

    /// Maiores primeiro; itens ainda sendo medidos ficam no fim.
    private static func sorted(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { lhs, rhs in
            switch (lhs.size, rhs.size) {
            case let (l?, r?): l == r ? lhs.name < rhs.name : l > r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.name < rhs.name
            }
        }
    }
}
