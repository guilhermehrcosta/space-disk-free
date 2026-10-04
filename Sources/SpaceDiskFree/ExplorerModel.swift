import AppKit
import DiskCore
import SwiftUI

@MainActor
@Observable
final class ExplorerModel {
    private(set) var current: URL
    private(set) var nodes: [FileNode] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var permissionDenied = false
    private(set) var measuredAt: Date?
    private var cache = DirectorySizeCache()
    private var history: [URL] = []
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

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
        load(current, force: true)
    }

    func reloadAll() {
        cache.removeAll()
        load(current)
    }

    func remove(_ node: FileNode) {
        nodes.removeAll { $0.id == node.id }
        cache.remove(node.url, knownBytes: node.size)
    }

    func record(_ url: URL, _ measurement: TreeMeasurement) {
        cache.record(url, measurement)
    }

    func contentsChanged(at url: URL, _ measurement: TreeMeasurement) {
        cache.update(url, measurement.total)
        cache.record(url, measurement)
        if current.normalizedPath == url.normalizedPath
            || current.normalizedPath.hasPrefix(url.normalizedPath + "/")
            || url.normalizedPath.hasPrefix(current.normalizedPath + "/")
        {
            load(current)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = current
        panel.prompt = String(localized: "Analyze")
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    private func load(_ url: URL, force: Bool = false) {
        loadTask?.cancel()
        hasLoaded = true
        current = url
        nodes = []
        errorMessage = nil
        permissionDenied = false
        measuredAt = nil
        isLoading = true
        if force { cache.removeDescendants(of: url) }

        loadTask = Task {
            do {
                var listing = try await Task.detached { try DirectoryLister.children(of: url) }.value
                guard !Task.isCancelled else { return }

                var oldestCached: Date?
                for index in listing.indices where listing[index].size == nil {
                    guard let entry = cache.entry(for: listing[index].url) else { continue }
                    listing[index].size = entry.result.bytes
                    if entry.result.permissionDenied { permissionDenied = true }
                    oldestCached = min(oldestCached ?? entry.measuredAt, entry.measuredAt)
                }
                nodes = Self.sorted(listing)

                let needsMeasuring = listing.contains { $0.size == nil }
                await measureDirectories(in: listing)
                guard !Task.isCancelled else { return }

                measuredAt = needsMeasuring ? .now : (oldestCached ?? .now)
                let total = SizeResult(bytes: totalSize, permissionDenied: permissionDenied)
                if force { cache.settle(url, total) } else if cache.entry(for: url) == nil { cache.record(url, total) }
            } catch {
                guard !Task.isCancelled else { return }
                let code = (error as NSError).underlyingErrors.first.map { ($0 as NSError).code }
                permissionDenied =
                    [Int(EPERM), Int(EACCES)].contains(code)
                    || (error as NSError).code == NSFileReadNoPermissionError
                errorMessage = permissionDenied ? String(localized: "No permission to read this folder.") : error.localizedDescription
            }
            if !Task.isCancelled { isLoading = false }
        }
    }

    private func measureDirectories(in listing: [FileNode]) async {
        var pending = listing.filter { $0.size == nil }.map(\.url).makeIterator()

        await withTaskGroup(of: (URL, TreeMeasurement).self) { group in
            func enqueueNext() {
                guard let url = pending.next() else { return }
                group.addTask { (url, SizeCalculator.measureTree(url)) }
            }
            for _ in 0..<maxConcurrentMeasurements { enqueueNext() }

            while let (url, measurement) = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                cache.record(url, measurement)
                if let index = nodes.firstIndex(where: { $0.url == url }) {
                    nodes[index].size = measurement.total.bytes
                }
                if measurement.total.permissionDenied { permissionDenied = true }
                nodes = Self.sorted(nodes)
                enqueueNext()
            }
        }
    }

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
