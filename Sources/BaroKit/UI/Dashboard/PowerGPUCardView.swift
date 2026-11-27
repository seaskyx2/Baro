import BaroCore
import SwiftUI

public struct PowerGPUCardView: View {
    public let power: AppleSiliconPowerSnapshot
    public let thermal: ThermalFanSnapshot
    public let powerHistory: [Double]
    public let lang: ResolvedLanguage
    public let isExpanded: Bool
    public let onToggleExpand: () -> Void

    public init(
        power: AppleSiliconPowerSnapshot,
        thermal: ThermalFanSnapshot,
        powerHistory: [Double],
        lang: ResolvedLanguage,
        isExpanded: Bool,
        onToggleExpand: @escaping () -> Void
    ) {
        self.power = power
        self.thermal = thermal
        self.powerHistory = powerHistory
        self.lang = lang
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(BaroL10n.t("功耗 & GPU", "Power & GPU", lang: lang), systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(power.isAvailable ? String(format: "%.1f W", power.packageWatts) : (thermal.primaryTemperature.map { "\(Int($0.rounded()))°C" } ?? "--"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 6) {
                miniMetric(title: "GPU", value: power.isAvailable ? "\(Int(power.gpuUsagePercent.rounded()))%" : "--")
                Spacer()
                if let fan = thermal.fans.first {
                    miniMetric(title: BaroL10n.t("风扇", "Fan", lang: lang), value: "\(fan.currentRPM) RPM")
                } else if let temp = thermal.primaryTemperature {
                    miniMetric(title: "SoC", value: "\(Int(temp.rounded()))°C")
                }
            }

            VStack(spacing: 3) {
                if power.isAvailable {
                    if power.cpuWatts > 0 || power.aneWatts > 0 || power.dramWatts > 0 {
                        HStack {
                            Text(String(format: "CPU %.1fW · GPU %.1fW", power.cpuWatts, power.gpuWatts))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack {
                            Text(String(format: "ANE %.1fW · DRAM %.1fW", power.aneWatts, power.dramWatts))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        HStack {
                            Text(BaroL10n.t(
                                String(format: "GPU %.2fW · 系统实测", power.gpuWatts),
                                String(format: "GPU %.2fW · System Total", power.gpuWatts),
                                lang: lang
                            ))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        if let temp = thermal.primaryTemperature {
                            HStack {
                                Text(BaroL10n.t(
                                    String(format: "SoC %.1f°C · 传感器 %d 路", temp, thermal.sensors.count),
                                    String(format: "SoC %.1f°C · %d Sensors", temp, thermal.sensors.count),
                                    lang: lang
                                ))
                                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                } else {
                    Text(BaroL10n.t("仅温度/风扇只读遥测", "Thermal / Fan Telemetry", lang: lang))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            SparklineView(
                values: powerHistory,
                lineColor: BaroPalette.power,
                fixedMax: nil,
                valueFormatter: { String(format: "%.1fW", $0) }
            )
            .frame(height: 18)

            if isExpanded && (!thermal.sensors.isEmpty || !thermal.fans.isEmpty) {
                Divider().opacity(0.35)
                sensorDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .bentoCard(isExpanded: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private func miniMetric(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private var sensorDrawer: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(BaroL10n.t("只读热敏与风扇传感器", "Read-Only Thermal & Fan Sensors", lang: lang))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(thermal.fans) { fan in
                HStack {
                    Text(BaroL10n.t("风扇 #\(fan.id)", "Fan #\(fan.id)", lang: lang))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fan.currentRPM) / \(fan.maxRPM) RPM")
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                }
            }

            ForEach(thermal.sensors.prefix(6)) { sensor in
                HStack {
                    Text(sensor.name)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f°C", sensor.celsius))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(BaroPalette.thermalColor(celsius: sensor.celsius))
                }
            }
        }
        .padding(.top, 2)
    }
}
