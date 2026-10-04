import DiskCore
import SwiftUI

struct CleanupListView: View {
    @Environment(AppState.self) private var state
    let onExplore: (URL) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedCategories) { category in
                    CategoryRow(
                        category: category,
                        status: state.status[category.id] ?? .init(),
                        onExplore: onExplore
                    )
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    private var sortedCategories: [CleanupCategory] {
        state.categories.sorted {
            (state.status[$0.id]?.size ?? 0) > (state.status[$1.id]?.size ?? 0)
        }
    }
}

private struct CategoryRow: View {
    @Environment(AppState.self) private var state
    let category: CleanupCategory
    let status: AppState.CategoryStatus
    let onExplore: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(category.title).font(.callout.weight(.medium))
                    if status.permissionDenied {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Parte desta pasta não pôde ser lida")
                    }
                }
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                sizeLabel
                actionButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(category.existingPaths, id: \.self) { url in
                Button("Mostrar \(url.lastPathComponent) no Finder") { state.reveal(url) }
            }
            if let first = category.existingPaths.first {
                Button("Explorar maiores itens") { onExplore(first) }
            }
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if status.isScanning || status.isCleaning {
            ProgressView().controlSize(.mini)
        } else {
            Text(status.size?.formattedBytes ?? "—")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        let isBusy = status.isScanning || status.isCleaning
        let isEmpty = (status.size ?? 0) == 0

        if category.actions.count > 1 {
            Menu("Limpar") {
                ForEach(category.actions) { action in
                    Button(action.title) {
                        if case .review = action.strategy {
                            if let first = category.existingPaths.first { onExplore(first) }
                        } else {
                            state.requestCleanup(category, action: action)
                        }
                    }
                }
            }
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize()
            .disabled(isBusy)
        } else {
            singleActionButton(isBusy: isBusy, isEmpty: isEmpty)
        }
    }

    @ViewBuilder
    private func singleActionButton(isBusy: Bool, isEmpty: Bool) -> some View {
        switch category.strategy {
        case .review:
            Button("Explorar") {
                if let first = category.existingPaths.first { onExplore(first) }
            }
            .controlSize(.small)
        case .command:
            Button("Executar") { state.requestCleanup(category) }
                .controlSize(.small)
                .disabled(isBusy)
        case .emptyTrash:
            Button("Esvaziar") { state.requestCleanup(category) }
                .controlSize(.small)
                .disabled(isBusy || isEmpty)
        case .deleteContents, .deleteItems, .trashContents:
            Button("Limpar") { state.requestCleanup(category) }
                .controlSize(.small)
                .disabled(isBusy || isEmpty)
        }
    }
}
