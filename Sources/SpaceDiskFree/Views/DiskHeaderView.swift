import DiskCore
import SwiftUI

struct DiskHeaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.volume?.name ?? "Disco", systemImage: "internaldrive")
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
                    .help("Analisar novamente")
                }
            }

            if let volume = state.volume {
                UsageBar(fraction: volume.usedFraction)
                HStack {
                    Text("\(volume.availableBytes.formattedBytes) disponíveis")
                        .fontWeight(.medium)
                    Text("de \(volume.totalBytes.formattedBytes)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if state.reclaimableBytes > 0 {
                        Text("\(state.reclaimableBytes.formattedBytes) recuperáveis")
                            .foregroundStyle(.green)
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
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
        .accessibilityLabel("Uso do disco")
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
