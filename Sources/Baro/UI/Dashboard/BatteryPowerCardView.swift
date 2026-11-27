import BaroCore
import SwiftUI

public struct BatteryPowerCardView: View {
    public let batteryPower: BatteryPowerSnapshot
    public let previewLaptopMode: Bool

    public init(batteryPower: BatteryPowerSnapshot, previewLaptopMode: Bool) {
        self.batteryPower = batteryPower
        self.previewLaptopMode = previewLaptopMode
    }

    public var body: some View {
        let displaySnapshot: BatteryPowerSnapshot = {
            if !batteryPower.hasInternalBattery && previewLaptopMode {
                return BatteryPowerSnapshot.previewLaptopSample(peripherals: batteryPower.peripherals)
            }
            return batteryPower
        }()

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("电源与电池", systemImage: displaySnapshot.hasInternalBattery ? "battery.75percent" : "powerplug.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displaySnapshot.hasInternalBattery ? (displaySnapshot.isCharging ? "充电中" : displaySnapshot.powerSourceName) : "交流供电")
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
                        Text(snap.isCharging ? "充满约 \(ByteFormatter.remainingTime(minutes: mins))" : "续航约 \(ByteFormatter.remainingTime(minutes: mins))")
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if let watts = snap.adapterWatts {
                        Text("适配器 \(watts)W")
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("健康 \(Int(snap.healthPercent.rounded()))% · 循环 \(snap.cycleCount)")
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
                Text(snap.powerWatts > 0 ? String(format: "整机输入 %.1f W", snap.powerWatts) : "交流电源稳定供电")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Spacer()
            }

            if snap.peripherals.isEmpty {
                Text("未连接苹果 HID 无线外设")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text("可在设置中预览笔记本电池卡")
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
