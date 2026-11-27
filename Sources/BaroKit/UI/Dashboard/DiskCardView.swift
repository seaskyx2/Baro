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
        let hasExtraDrawer = disk.volumes.count > 1 || (disk.smart?.isAvailable == true)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(BaroL10n.t("磁盘存储", "Storage", lang: lang), systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(primary.map { "\(Int($0.usedPercent.rounded()))%" } ?? "--")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            if let primary {
                ThinProgressBar(ratio: primary.usedPercent / 100.0, tint: BaroPalette.disk, height: 5.5)

                Text(BaroL10n.t("余 ", "Free ", lang: lang) + "\(ByteFormatter.diskSize(primary.availableBytes)) / \(ByteFormatter.diskSize(primary.totalBytes))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(BaroL10n.t("未检测到本地卷", "No local volumes", lang: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(BaroL10n.t("读 ", "R ", lang: lang) + "\(ByteFormatter.compactRate(disk.readBytesPerSec))/s")
                Spacer()
                Text(BaroL10n.t("写 ", "W ", lang: lang) + "\(ByteFormatter.compactRate(disk.writeBytesPerSec))/s")
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)

            if isExpanded && hasExtraDrawer {
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
        VStack(alignment: .leading, spacing: 4) {
            if let smart = disk.smart, smart.isAvailable {
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

            if disk.volumes.count > 1 {
                if disk.smart?.isAvailable == true {
                    Divider().opacity(0.25)
                }
                ForEach(disk.volumes.dropFirst().prefix(3)) { vol in
                    drawerRow(
                        title: vol.name,
                        value: BaroL10n.t("余 ", "Free ", lang: lang) + ByteFormatter.diskSize(vol.availableBytes)
                    )
                }
            }
        }
        .padding(.top, 2)
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
