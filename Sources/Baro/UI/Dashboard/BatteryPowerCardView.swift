import BaroCore
import SwiftUI

public struct BatteryPowerCardView: View {
    public let batteryPower: BatteryPowerSnapshot
    public let previewLaptopMode: Bool
    public let lang: ResolvedLanguage

    public init(batteryPower: BatteryPowerSnapshot, previewLaptopMode: Bool, lang: ResolvedLanguage) {
        self.batteryPower = batteryPower
        self.previewLaptopMode = previewLaptopMode
        self.lang = lang
    }

    public var body: some View {
        let displaySnapshot: BatteryPowerSnapshot = {
            if !batteryPower.hasInternalBattery && previewLaptopMode {
                return BatteryPowerSnapshot.previewLaptopSample(peripherals: batteryPower.peripherals)
            }
            return batteryPower
        }()

        let statusBadge: String = {
            if displaySnapshot.hasInternalBattery {
                if displaySnapshot.isCharging {
                    return BaroL10n.t("充电中", "Charging", lang: lang)
                }
                return displaySnapshot.isPluggedIn
                    ? BaroL10n.t("电源适配器", "Adapter", lang: lang)
                    : BaroL10n.t("内置电池", "Battery", lang: lang)
            }
            return BaroL10n.t("交流供电", "AC Power", lang: lang)
        }()

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(BaroL10n.t("电源与电池", "Power & Battery", lang: lang), systemImage: displaySnapshot.hasInternalBattery ? "battery.75percent" : "powerplug.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusBadge)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(displaySnapshot.isCharging ? BaroPalette.batteryHealthy : .secondary)
            }

            if displaySnapshot.hasInternalBattery {
                laptopBatteryView(displaySnapshot)
            } else {
                desktopPowerView(displaySnapshot)
            }
        }
        .bentoCard()
    }

    private func laptopBatteryView(_ snap: BatteryPowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                CircularGaugeView(
                    progress: snap.chargePercent / 100.0,
                    tint: snap.chargePercent <= 15 && !snap.isPluggedIn ? BaroPalette.healthColor(for: .elevated) : BaroPalette.batteryHealthy,
                    lineWidth: 4,
                    centerLabel: "\(Int(snap.chargePercent.rounded()))%"
                )
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    let sign = snap.powerWatts >= 0 ? "+" : ""
                    Text(String(format: "%@%.1f W", sign, snap.powerWatts))
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())

                    if let mins = snap.timeRemainingMinutes {
                        let rem = ByteFormatter.remainingTime(minutes: mins)
                        Text(snap.isCharging
                             ? BaroL10n.t("充满约 \(rem)", "Full in \(rem)", lang: lang)
                             : BaroL10n.t("续航约 \(rem)", "\(rem) left", lang: lang))
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if let watts = snap.adapterWatts {
                        Text(BaroL10n.t("适配器 \(watts)W", "\(watts)W Adapter", lang: lang))
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text(BaroL10n.t(
                    "健康 \(Int(snap.healthPercent.rounded()))% · 循环 \(snap.cycleCount)",
                    "Health \(Int(snap.healthPercent.rounded()))% · \(snap.cycleCount) cycles",
                    lang: lang
                ))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let temp = snap.temperatureCelsius {
                    Text(String(format: "%.0f°C", temp))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !snap.peripherals.isEmpty {
                peripheralsInlineRow(snap.peripherals)
            }
        }
    }

    private func desktopPowerView(_ snap: BatteryPowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(BaroPalette.batteryHealthy)
                    .frame(width: 6, height: 6)
                Text(snap.powerWatts > 0
                     ? BaroL10n.t(String(format: "整机输入 %.1f W", snap.powerWatts), String(format: "System In %.1f W", snap.powerWatts), lang: lang)
                     : BaroL10n.t("交流电源稳定供电", "Stable AC Power", lang: lang))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Spacer()
            }

            if snap.peripherals.isEmpty {
                Text(BaroL10n.t("未连接苹果 HID 无线外设", "No Apple HID peripherals", lang: lang))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text(BaroL10n.t("可在设置中预览笔记本电池卡", "Preview laptop card in Preferences", lang: lang))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(snap.peripherals.prefix(2)) { item in
                    HStack(spacing: 5) {
                        Text(item.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        ThinProgressBar(
                            ratio: Double(item.percent) / 100.0,
                            tint: item.percent <= 15 ? BaroPalette.healthColor(for: .elevated) : BaroPalette.batteryHealthy,
                            height: 4
                        )
                        .frame(width: 34)
                        Text("\(item.percent)%")
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    private func peripheralsInlineRow(_ items: [HIDPeripheralBattery]) -> some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(2)) { item in
                Text("\(shortPeripheralName(item.name)) \(item.percent)%")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func shortPeripheralName(_ name: String) -> String {
        name.replacingOccurrences(of: "Magic ", with: "")
    }
}
