import BaroCore
import SwiftUI

public struct CPUCardView: View {
    public let cpu: CPUSnapshot
    public let history: [Double]
    public let temperature: Double?
    public let lang: ResolvedLanguage
    public let isExpanded: Bool
    public let onToggleExpand: () -> Void

    public init(
        cpu: CPUSnapshot,
        history: [Double],
        temperature: Double?,
        lang: ResolvedLanguage,
        isExpanded: Bool,
        onToggleExpand: @escaping () -> Void
    ) {
        self.cpu = cpu
        self.history = history
        self.temperature = temperature
        self.lang = lang
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("CPU", systemImage: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", cpu.totalUsagePercent))
                    .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(BaroPalette.usageColor(percent: cpu.totalUsagePercent))
            }

            SparklineView(
                values: history,
                lineColor: BaroPalette.pCore,
                fixedMax: 100,
                valueFormatter: { String(format: "%.0f%%", $0) }
            )
            .frame(height: 28)

            VStack(spacing: 4) {
                if cpu.pCoreCount > 0 && cpu.eCoreCount > 0 {
                    clusterBarRow(
                        label: BaroL10n.t("P核×\(cpu.pCoreCount)", "P×\(cpu.pCoreCount)", lang: lang),
                        percent: cpu.pCoreUsagePercent,
                        tint: BaroPalette.pCore,
                        rightText: temperature.map { "\(Int($0.rounded()))°C" } ?? ""
                    )
                    clusterBarRow(
                        label: BaroL10n.t("E核×\(cpu.eCoreCount)", "E×\(cpu.eCoreCount)", lang: lang),
                        percent: cpu.eCoreUsagePercent,
                        tint: BaroPalette.eCore,
                        rightText: String(format: "%.2f", cpu.loadAverage1m)
                    )
                } else {
                    clusterBarRow(
                        label: BaroL10n.t("用户", "User", lang: lang),
                        percent: cpu.userPercent,
                        tint: BaroPalette.pCore,
                        rightText: temperature.map { "\(Int($0.rounded()))°C" } ?? ""
                    )
                    clusterBarRow(
                        label: BaroL10n.t("系统", "Sys", lang: lang),
                        percent: cpu.systemPercent,
                        tint: BaroPalette.eCore,
                        rightText: String(format: "%.2f", cpu.loadAverage1m)
                    )
                }
            }

            if isExpanded && !cpu.perCoreLoads.isEmpty {
                Divider().opacity(0.35)
                perCoreDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .bentoCard(isExpanded: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private func clusterBarRow(label: String, percent: Double, tint: Color, rightText: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)

            ThinProgressBar(ratio: percent / 100.0, tint: tint, height: 4.5)

            Text("\(Int(percent.rounded()))%")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 30, alignment: .trailing)

            if !rightText.isEmpty {
                Text(rightText)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private var perCoreDrawer: some View {
        let coreCount = cpu.perCoreLoads.count
        let barSpacing: CGFloat = coreCount > 16 ? 1.5 : 3.0
        let labelFontSize: CGFloat = coreCount > 20 ? 7.0 : 8.0

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(BaroL10n.t("全核心实时负载（\(cpu.totalCoreCount) 核）", "Per-Core Load (\(cpu.totalCoreCount) cores)", lang: lang))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Load \(String(format: "%.2f / %.2f", cpu.loadAverage1m, cpu.loadAverage5m))")
                    .font(.system(size: 9, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(cpu.perCoreLoads) { core in
                    let barColor = core.kind == .performance ? BaroPalette.pCore : BaroPalette.eCore
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.primary.opacity(0.09))
                                .frame(height: 26)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(barColor)
                                .frame(height: max(2, 26 * min(1.0, core.usagePercent / 100.0)))
                                .animation(.easeOut(duration: 0.25), value: core.usagePercent)
                        }
                        Text(core.kind == .performance ? "P" : (core.kind == .efficiency ? "E" : "\(core.id)"))
                            .font(.system(size: labelFontSize, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 2)
    }
}
