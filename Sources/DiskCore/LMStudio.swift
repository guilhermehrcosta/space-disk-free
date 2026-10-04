import Foundation

public struct LMStudio: Sendable {
    public let modelsDirectory: URL

    public init(home: URL) {
        let settings = home.appending(path: ".lmstudio/settings.json")
        let defaultDirectory = home.appending(path: ".lmstudio/models", directoryHint: .isDirectory)
        let legacyDirectory = home.appending(path: ".cache/lm-studio/models", directoryHint: .isDirectory)

        if let configured = Self.downloadsFolder(in: settings, home: home) {
            modelsDirectory = configured
        } else if !FileManager.default.fileExists(atPath: defaultDirectory.path(percentEncoded: false)),
            FileManager.default.fileExists(atPath: legacyDirectory.path(percentEncoded: false))
        {
            modelsDirectory = legacyDirectory
        } else {
            modelsDirectory = defaultDirectory
        }
    }

    public func installedModels() -> [URL] {
        subdirectories(of: modelsDirectory)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .flatMap(subdirectories)
            .sorted { $0.path < $1.path }
    }

    public static func displayName(of model: URL) -> String {
        model.pathComponents.suffix(2).joined(separator: "/")
    }

    private static func downloadsFolder(in settings: URL, home: URL) -> URL? {
        guard let data = try? Data(contentsOf: settings),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = json["downloadsFolder"] as? String, !folder.isEmpty
        else { return nil }
        let expanded = folder.hasPrefix("~/") ? home.path(percentEncoded: false) + folder.dropFirst() : folder
        return URL(filePath: expanded, directoryHint: .isDirectory)
    }

    private func subdirectories(of url: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
