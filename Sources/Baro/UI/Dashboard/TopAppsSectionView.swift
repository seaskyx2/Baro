import AppKit
import BaroCore
import SwiftUI

public struct TopAppsSectionView: View {
    public enum SortMode: String, CaseIterable {
        case cpu = "CPU"
        case memory = "内存"
    }

    public let topCPUApps: [AggregatedAppUsage]
    public let topMemoryApps: [AggregatedAppUsage]

    @State private var mode: SortMode = .cpu

    public init(topCPUApps: [AggregatedAppUsage], topMemoryApps: [AggregatedAppUsage]) {
        self.topCPUApps = topCPUApps
        self.topMemoryApps = topMemoryApps
    }

    public var body: some View {
        let items = mode == .cpu ? topCPUApps : topMemoryApps

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("资源占用排行（按 App 归并）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(SortMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 92)
            }

            if items.isEmpty {
                Text("正在采样进程树…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let maxVal: Double = {
                    switch mode {
                    case .cpu: return max(100.0, items.first?.cpuPercent ?? 100.0)
                    case .memory: return max(1.0, Double(items.first?.memoryBytes ?? 1))
                    }
                }()

                VStack(spacing: 5) {
                    ForEach(items) { app in
                        appRow(app: app, maxVal: maxVal)
                    }
                }
            }
        }
        .bentoCard()
    }

    private func appRow(app: AggregatedAppUsage, maxVal: Double) -> some View {
        let ratio: Double = mode == .cpu
            ? min(1.0, max(0.0, app.cpuPercent / maxVal))
            : min(1.0, max(0.0, Double(app.memoryBytes) / maxVal))

        let valueLabel: String = mode == .cpu
            ? String(format: "%.1f%%", app.cpuPercent)
            : ByteFormatter.memorySize(app.memoryBytes)

        return HStack(spacing: 7) {
            appIcon(for: app)
                .frame(width: 15, height: 15)

            Text(app.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)

            if app.pidsCount > 1 {
                Text("×\(app.pidsCount)")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Spacer(minLength: 4)

            ThinProgressBar(
                ratio: ratio,
                tint: mode == .cpu ? BaroPalette.pCore : BaroPalette.memoryApp,
                height: 4
            )
            .frame(width: 58)

            Text(valueLabel)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func appIcon(for app: AggregatedAppUsage) -> some View {
        if let path = app.appBundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
