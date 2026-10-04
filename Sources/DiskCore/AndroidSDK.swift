import Foundation

public struct AndroidSDK: Sendable {
    public let sdkRoot: URL
    public let avdHome: URL

    public init(home: URL) {
        sdkRoot = home.appending(path: "Library/Android/sdk", directoryHint: .isDirectory)
        avdHome = home.appending(path: ".android/avd", directoryHint: .isDirectory)
    }

    public var systemImagesRoot: URL { sdkRoot.appending(path: "system-images", directoryHint: .isDirectory) }

    public func installedSystemImages() -> [URL] {
        subdirectories(of: systemImagesRoot)
            .flatMap(subdirectories)
            .flatMap(subdirectories)
            .sorted { $0.path < $1.path }
    }

    public func systemImagesInUse() -> Set<String> {
        var inUse = Set<String>()
        for avd in avdDirectories() {
            guard let config = try? String(contentsOf: avd.appending(path: "config.ini"), encoding: .utf8) else { continue }
            for line in config.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0].hasPrefix("image.sysdir."), !parts[1].isEmpty else { continue }
                inUse.insert(sdkRoot.appending(path: parts[1]).normalizedPath)
            }
        }
        return inUse
    }

    public func unusedSystemImages() -> [URL] {
        let inUse = systemImagesInUse()
        return installedSystemImages().filter { !inUse.contains($0.normalizedPath) }
    }

    public static func displayName(of image: URL) -> String {
        let components = image.pathComponents.suffix(3)
        guard components.count == 3 else { return image.lastPathComponent }
        let api = components.first!.replacingOccurrences(of: "android-", with: "API ")
        return ([api] + components.dropFirst()).joined(separator: " · ")
    }

    private func avdDirectories() -> [URL] {
        var directories = subdirectories(of: avdHome).filter { $0.pathExtension == "avd" }
        let iniFiles = (try? FileManager.default.contentsOfDirectory(at: avdHome, includingPropertiesForKeys: nil)) ?? []
        for ini in iniFiles where ini.pathExtension == "ini" {
            guard let text = try? String(contentsOf: ini, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("path=") {
                directories.append(URL(filePath: String(line.dropFirst("path=".count)), directoryHint: .isDirectory))
            }
        }
        var seen = Set<String>()
        return directories.filter { seen.insert($0.normalizedPath).inserted }
    }

    private func subdirectories(of url: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
