import BaroCore
import SwiftUI

public struct DiskCardView: View {
    public let disk: DiskSnapshot
    public let isExpanded: Bool
    public let onToggleExpand: () -> Void

    public init(
        disk: DiskSnapshot,
        isExpanded: Bool,
        onToggleExpand: @escaping () -> Void
    ) {
        self.disk = disk
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        let primary = disk.primaryVolume

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("磁盘存储", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(primary.map { "\(Int($0.usedPercent.rounded()))%" } ?? "--")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            if let primary {
                ThinProgressBar(ratio: primary.usedPercent / 100.0, tint: BaroPalette.disk, height: 5.5)

                Text("余 \(ByteFormatter.diskSize(primary.availableBytes)) / \(ByteFormatter.diskSize(primary.totalBytes))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("未检测到本地卷")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("读 \(ByteFormatter.compactRate(disk.readBytesPerSec))/s")
                Spacer()
                Text("写 \(ByteFormatter.compactRate(disk.writeBytesPerSec))/s")
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
                            Text("余 \(ByteFormatter.diskSize(vol.availableBytes))")
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
