import SwiftUI

struct MenuContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            DiskHeaderView()
                .padding(16)

            Picker("Seção", selection: Bindable(state).selectedTab) {
                ForEach(AppState.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if state.needsFullDiskAccess {
                FullDiskAccessBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()

            Group {
                switch state.selectedTab {
                case .cleanup:
                    CleanupListView { url in
                        state.explorer.open(url)
                        state.selectedTab = .explore
                    }
                case .explore:
                    ExplorerView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            FooterView()
        }
        .frame(width: 420, height: 620)
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                ToastView(message: toast)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let confirmation = state.pendingConfirmation {
                ConfirmationOverlay(confirmation: confirmation)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.toast)
        .animation(.easeOut(duration: 0.15), value: state.pendingConfirmation?.id)
        .onAppear { state.refreshIfStale() }
    }
}

private struct FullDiskAccessBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Algumas pastas não puderam ser lidas")
                    .font(.callout.weight(.medium))
                Text("Conceda Acesso Total ao Disco para medir tudo com precisão.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Abrir Ajustes") { state.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FooterView: View {
    @Environment(AppState.self) private var state
    @AppStorage("showFreeSpaceInMenuBar") private var showFreeSpace = true

    var body: some View {
        HStack {
            Menu {
                Toggle("Mostrar espaço livre na barra de menus", isOn: $showFreeSpace)
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Divider()
                Button("Acesso Total ao Disco…") { state.openFullDiskAccessSettings() }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            Button("Sair") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 6, y: 2)
            .padding(.horizontal, 16)
    }
}

private struct ConfirmationOverlay: View {
    @Environment(AppState.self) private var state
    let confirmation: AppState.Confirmation

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { state.pendingConfirmation = nil }

            VStack(alignment: .leading, spacing: 12) {
                Text(confirmation.title)
                    .font(.headline)
                Text(confirmation.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) { state.pendingConfirmation = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(confirmation.confirmTitle, role: confirmation.isDestructive ? .destructive : nil) {
                        state.pendingConfirmation = nil
                        Task { await confirmation.action() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(confirmation.isDestructive ? .red : .accentColor)
                }
            }
            .padding(18)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}
