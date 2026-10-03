import AppKit
import DiskCore
import SwiftUI

struct ExplorerView: View {
    @Environment(AppState.self) private var state

    private var explorer: ExplorerModel { state.explorer }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            content
        }
        .onAppear { explorer.loadIfNeeded() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                explorer.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!explorer.canGoBack)
            .help("Voltar")

            VStack(alignment: .leading, spacing: 0) {
                Text(explorer.current.lastPathComponent.isEmpty ? "/" : explorer.current.lastPathComponent)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(explorer.current.path(percentEncoded: false).abbreviatingHome)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if explorer.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(explorer.totalSize.formattedBytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Menu {
                Button("Pasta pessoal") { explorer.open(state.home) }
                Button("Disco inteiro") { explorer.open(URL(filePath: "/")) }
                Button("Aplicativos") { explorer.open(URL(filePath: "/Applications")) }
                Divider()
                Button("Escolher pasta…") { explorer.chooseFolder() }
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Escolher local para analisar")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = explorer.errorMessage {
            ContentUnavailableView {
                Label(error, systemImage: "exclamationmark.lock")
            } actions: {
                if explorer.permissionDenied {
                    Button("Conceder Acesso Total ao Disco") { state.openFullDiskAccessSettings() }
                }
            }
        } else if explorer.nodes.isEmpty, !explorer.isLoading {
            ContentUnavailableView("Pasta vazia", systemImage: "folder")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(explorer.nodes) { node in
                        FileRow(node: node, largest: explorer.largestSize)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct FileRow: View {
    @Environment(AppState.self) private var state
    let node: FileNode
    let largest: UInt64
    @State private var isHovering = false

    private var fraction: Double {
        guard let size = node.size, largest > 0 else { return 0 }
        return Double(size) / Double(largest)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { proxy in
                    Capsule().fill(.tint.opacity(0.6))
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 2 : 0))
                }
                .frame(height: 3)
            }

            if isHovering {
                Button {
                    state.reveal(node.url)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Mostrar no Finder")
                Button {
                    state.requestTrash(node)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Mover para a Lixeira")
            }

            Group {
                if let size = node.size {
                    Text(size.formattedBytes)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 72, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(node.canEnter ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { state.explorer.enter(node) }
        .contextMenu {
            if node.canEnter {
                Button("Abrir") { state.explorer.enter(node) }
            }
            Button("Mostrar no Finder") { state.reveal(node.url) }
            Divider()
            Button("Mover para a Lixeira…", role: .destructive) { state.requestTrash(node) }
        }
    }
}
