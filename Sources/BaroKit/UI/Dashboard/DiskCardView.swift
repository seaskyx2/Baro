import BaroCore
import SwiftUI

public struct DiskCardView: View {
    public let disk: DiskSnapshot
    public let lang: ResolvedLanguage
    public let isExpanded: Bool
    public let onToggleExpand: () -> Void

    public init(
        disk: DiskSnapshot,
        lang: ResolvedLanguage,
        isExpanded: Bool,
        onToggleExpand: @escaping () -> Void
    ) {
        self.disk = disk
        self.lang = lang
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        let primary = disk.primaryVolume
        let extraCount = max(0, disk.volumes.count - 1)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(BaroL10n.t("磁盘空间", "Disk Space", lang: lang), systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let primary {
                    let headline = BaroL10n.t(
                        "余 \(ByteFormatter.diskSize(primary.availableBytes))",
                        "\(ByteFormatter.diskSize(primary.availableBytes)) Free",
                        lang: lang
                    )
                    Text(headline)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(spaceAccentColor(for: primary, defaultPrimary: true))
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let primary {
                ThinProgressBar(
                    ratio: primary.usedPercent / 100.0,
                    tint: spaceBarTint(for: primary),
                    height: 6.0
                )

                HStack(spacing: 4) {
                    Text(BaroL10n.t("已用 ", "Used ", lang: lang) + ByteFormatter.diskSize(primary.usedBytes))
                    Spacer()
                    Text("\(ByteFormatter.diskSize(primary.totalBytes)) (\(Int(primary.usedPercent.rounded()))%)")
                }
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text(BaroL10n.t("未检测到本地卷", "No local volumes", lang: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text(BaroL10n.t("读 ", "R ", lang: lang) + "\(ByteFormatter.compactRate(disk.readBytesPerSec))/s")
                Spacer()
                if extraCount > 0 {
                    Text(BaroL10n.t("+\(extraCount) 卷", "+\(extraCount) vol", lang: lang))
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                Text(BaroL10n.t("写 ", "W ", lang: lang) + "\(ByteFormatter.compactRate(disk.writeBytesPerSec))/s")
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)

            if isExpanded && primary != nil {
                Divider().opacity(0.35)
                expandedDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .bentoCard(isExpanded: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private var expandedDrawer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let primary = disk.primaryVolume {
                Text(primary.name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                drawerRow(
                    title: BaroL10n.t("可用空间", "Available", lang: lang),
                    value: ByteFormatter.diskSize(primary.availableBytes),
                    valueColor: spaceAccentColor(for: primary, defaultPrimary: true)
                )
                drawerRow(
                    title: BaroL10n.t("已用空间", "Used", lang: lang),
                    value: "\(ByteFormatter.diskSize(primary.usedBytes)) / \(ByteFormatter.diskSize(primary.totalBytes))"
                )
                if primary.purgeableBytes >= 100_000_000 {
                    drawerRow(
                        title: BaroL10n.t("含可清除缓存", "Purgeable Cache", lang: lang),
                        value: ByteFormatter.diskSize(primary.purgeableBytes),
                        valueColor: .secondary
                    )
                }
            }

            if disk.volumes.count > 1 {
                Divider().opacity(0.25)
                Text(BaroL10n.t("其他挂载卷", "Other Volumes", lang: lang))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(disk.volumes.dropFirst().prefix(4)) { vol in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(vol.name)
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(BaroL10n.t("余 ", "Free ", lang: lang) + "\(ByteFormatter.diskSize(vol.availableBytes)) / \(ByteFormatter.diskSize(vol.totalBytes))")
                                .font(.system(size: 9.0, weight: .semibold).monospacedDigit())
                                .foregroundStyle(spaceAccentColor(for: vol, defaultPrimary: false))
                        }
                        ThinProgressBar(ratio: vol.usedPercent / 100.0, tint: spaceBarTint(for: vol), height: 4.0)
                    }
                }
            }

            if let smart = disk.smart, smart.isAvailable {
                Divider().opacity(0.25)
                Text(BaroL10n.t("NVMe S.M.A.R.T. 健康只读", "NVMe S.M.A.R.T. Health", lang: lang))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                drawerRow(
                    title: BaroL10n.t("SSD 剩余寿命", "SSD Health", lang: lang),
                    value: "\(smart.healthPercent)%",
                    valueColor: smart.healthPercent >= 80 ? BaroPalette.batteryHealthy : BaroPalette.healthColor(for: .moderate)
                )
                drawerRow(
                    title: BaroL10n.t("累计写入 (TBW)", "Total Written", lang: lang),
                    value: ByteFormatter.diskSize(smart.totalBytesWritten)
                )
                drawerRow(
                    title: BaroL10n.t("累计读取", "Total Read", lang: lang),
                    value: ByteFormatter.diskSize(smart.totalBytesRead)
                )
                if smart.powerOnHours > 0 {
                    drawerRow(
                        title: BaroL10n.t("通电时长", "Power-On Hours", lang: lang),
                        value: "\(smart.powerOnHours)h"
                    )
                }
                if let temp = smart.temperatureCelsius {
                    drawerRow(
                        title: BaroL10n.t("SSD 温度", "SSD Temp", lang: lang),
                        value: "\(temp)°C"
                    )
                }
            }
        }
        .padding(.top, 2)
    }

    private func spaceBarTint(for vol: DiskVolume) -> Color {
        if vol.availableBytes < 12_000_000_000 || vol.usedPercent >= 95.0 {
            return BaroPalette.healthColor(for: .elevated)
        }
        if vol.availableBytes < 25_000_000_000 || vol.usedPercent >= 90.0 {
            return BaroPalette.healthColor(for: .moderate)
        }
        return BaroPalette.disk
    }

    private func spaceAccentColor(for vol: DiskVolume, defaultPrimary: Bool) -> Color {
        if vol.availableBytes < 12_000_000_000 || vol.usedPercent >= 95.0 {
            return BaroPalette.healthColor(for: .elevated)
        }
        if vol.availableBytes < 25_000_000_000 || vol.usedPercent >= 90.0 {
            return BaroPalette.healthColor(for: .moderate)
        }
        return defaultPrimary ? .primary : .secondary
    }

    private func drawerRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }
}
