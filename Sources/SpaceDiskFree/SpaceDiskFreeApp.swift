import AppKit
import DiskCore
import SwiftUI

@main
struct SpaceDiskFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @AppStorage("showFreeSpaceInMenuBar") private var showFreeSpace = true

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(state)
        } label: {
            MenuBarLabel(volume: state.volume, showFreeSpace: showFreeSpace)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Garante que não apareça no Dock mesmo rodando via `swift run` (fora do .app com LSUIElement).
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarLabel: View {
    let volume: VolumeStatus?
    let showFreeSpace: Bool

    private var isLow: Bool { (volume?.usedFraction ?? 0) > 0.9 }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLow ? "externaldrive.badge.exclamationmark" : "internaldrive")
            if showFreeSpace, let volume {
                Text(volume.availableBytes.formattedBytes)
            }
        }
    }
}
