import AppKit
import BaroCore
import SwiftUI

public struct MenuBarContentView: View {
    @ObservedObject public var coordinator: SamplingCoordinator
    @ObservedObject public var settings: BaroSettings

    public init(coordinator: SamplingCoordinator, settings: BaroSettings) {
        self.coordinator = coordinator
        self.settings = settings
    }

    public var body: some View {
        Group {
            switch settings.menuBarStyle {
            case .compactDualRow:
                compactDualRowView
            case .sparkline:
                sparklineStyleView
            case .breathingDot:
                breathingDotView
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .contentShape(Rectangle())
    }

    // MARK: - 风格 A：极简双行精工胶囊

    private var compactDualRowView: some View {
        let items = activeItems
        if items.isEmpty {
            return AnyView(
                HStack(spacing: 4) {
                    Circle()
                        .fill(BaroPalette.healthColor(for: coordinator.healthSummary.level))
                        .frame(width: 6, height: 6)
                    Text("Baro")
                        .font(.system(size: 11, weight: .medium))
                }
            )
        }

        return AnyView(
            HStack(spacing: 7) {
                if items.contains(.cpu) || items.contains(.memory) {
                    VStack(alignment: .leading, spacing: -1) {
                        if items.contains(.cpu) {
                            compactKVRow(
                                label: "CPU",
                                value: "\(Int(coordinator.snapshot.cpu.totalUsagePercent.rounded()))%",
                                color: BaroPalette.usageColor(percent: coordinator.snapshot.cpu.totalUsagePercent)
                            )
                        }
                        if items.contains(.memory) {
                            compactKVRow(
                                label: "MEM",
                                value: "\(Int(coordinator.snapshot.memory.usedPercent.rounded()))%",
                                color: coordinator.snapshot.memory.pressure == .normal ? .primary : BaroPalette.healthColor(for: .elevated)
                            )
                        }
                    }
                }

                if items.contains(.network) {
                    VStack(alignment: .trailing, spacing: -1) {
                        compactKVRow(
                            label: "↑",
                            value: ByteFormatter.compactRate(coordinator.snapshot.network.uploadBytesPerSec),
                            color: .primary
                        )
                        compactKVRow(
                            label: "↓",
                            value: ByteFormatter.compactRate(coordinator.snapshot.network.downloadBytesPerSec),
                            color: .primary
                        )
                    }
                }

                if items.contains(.temperature) || items.contains(.power) {
                    VStack(alignment: .trailing, spacing: -1) {
                        if items.contains(.temperature) {
                            let tempText = coordinator.snapshot.thermalFan.primaryTemperature.map { "\(Int($0.rounded()))°C" } ?? "--°"
                            Text(tempText)
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(
                                    coordinator.snapshot.thermalFan.primaryTemperature.map { BaroPalette.thermalColor(celsius: $0) } ?? .secondary
                                )
                        }
                        if items.contains(.power) {
                            let powerText = coordinator.snapshot.siliconPower.isAvailable
                                ? String(format: "%.1fW", coordinator.snapshot.siliconPower.packageWatts)
                                : "--W"
                            Text(powerText)
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        )
    }

    private func compactKVRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .lineLimit(1)
    }

    // MARK: - 风格 B：微图表精工

    private var sparklineStyleView: some View {
        HStack(spacing: 6) {
            MiniMenuSparkline(values: Array(coordinator.cpuHistory.suffix(16)))
                .frame(width: 24, height: 13)
            Text("\(Int(coordinator.snapshot.cpu.totalUsagePercent.rounded()))%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())

            if settings.showMenuMemory {
                let memRatio = min(1.0, max(0.0, coordinator.snapshot.memory.usedPercent / 100.0))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 22, height: 7)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.primary.opacity(0.78))
                        .frame(width: max(2, 22 * memRatio), height: 7)
                }
                Text("\(Int(coordinator.snapshot.memory.usedPercent.rounded()))%")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 风格 C：静默呼吸点

    private var breathingDotView: some View {
        let level = coordinator.healthSummary.level
        let cpu = Int(coordinator.snapshot.cpu.totalUsagePercent.rounded())
        let topApp = coordinator.snapshot.topCPUApps.first

        return HStack(spacing: 5) {
            Circle()
                .fill(BaroPalette.healthColor(for: level))
                .frame(width: 7, height: 7)

            if level == .elevated, let path = topApp?.appBundlePath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 13, height: 13)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            Text("\(cpu)%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
    }

    private var activeItems: [MenuBarMetric] {
        MenuBarMetric.allCases.filter { settings.activeMenuMetrics.contains($0) }
    }
}

private struct MiniMenuSparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            let pts = values.count >= 2 ? values : [0, 0]
            var path = Path()
            let step = size.width / CGFloat(pts.count - 1)
            for (idx, val) in pts.enumerated() {
                let x = CGFloat(idx) * step
                let ratio = min(1.0, max(0.0, val / 100.0))
                let y = size.height - CGFloat(ratio) * (size.height - 2) - 1
                if idx == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
