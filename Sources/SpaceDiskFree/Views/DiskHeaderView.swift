import DiskCore
import SwiftUI

struct DiskHeaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.volume?.name ?? String(localized: "Disk"), systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                if state.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        state.refreshVolume()
                        state.scanCategories()
                        state.explorer.reloadAll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Analyze again")
                }
            }

            if let volume = state.volume {
                UsageBar(fraction: volume.usedFraction)
                HStack {
                    Text("\(volume.availableBytes.formattedBytes) available")
                        .fontWeight(.medium)
                    Text("of \(volume.totalBytes.formattedBytes)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if state.reclaimableBytes > 0 {
                        ReclaimableButton()
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }
}

private struct ReclaimableButton: View {
    @Environment(AppState.self) private var state
    @State private var isShowingBreakdown = false

    var body: some View {
        Button {
            isShowingBreakdown.toggle()
        } label: {
            HStack(spacing: 3) {
                Text("\(state.reclaimableBytes.formattedBytes) reclaimable")
                Image(systemName: "info.circle")
                    .imageScale(.small)
            }
            .foregroundStyle(.green)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show what is included")
        .popover(isPresented: $isShowingBreakdown, arrowEdge: .bottom) {
            ReclaimableBreakdownView()
                .environment(state)
        }
    }
}

private struct ReclaimableBreakdownView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reclaimable with one click")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(state.reclaimableBreakdown, id: \.category.id) { item in
                    GridRow {
                        Text(item.category.title)
                        Text(item.bytes.formattedBytes)
                            .gridColumnAlignment(.trailing)
                    }
                }
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("Total")
                    Text(state.reclaimableBytes.formattedBytes)
                }
                .fontWeight(.semibold)
            }
            .font(.callout)
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 6) {
                if !state.excludedFromReclaimable.isEmpty {
                    Text("Not included: \(state.excludedFromReclaimable.map(\.title).formatted(.list(type: .and))).")
                    Text("They are only for review, depend on how much their tool frees, or let you choose item by item.")
                }
                Text("Caches grow back, and files in use or protected by macOS are kept, so the space freed may be smaller.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct UsageBar: View {
    let fraction: Double

    private var color: Color {
        switch fraction {
        case 0.9...: .red
        case 0.75...: .orange
        default: .accentColor
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.gradient)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Disk usage")
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
