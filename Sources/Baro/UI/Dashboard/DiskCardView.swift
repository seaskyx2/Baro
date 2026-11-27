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

            if isExpanded && disk.volumes.count > 1 {
                Divider().opacity(0.35)
                VStack(spacing: 4) {
                    ForEach(disk.volumes.dropFirst().prefix(3)) { vol in
                        HStack {
                            Text(vol.name)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(BaroL10n.t("余 ", "Free ", lang: lang) + ByteFormatter.diskSize(vol.availableBytes))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        }
                    }
                }
            }
        }
        .bentoCard(isExpanded: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }
}
