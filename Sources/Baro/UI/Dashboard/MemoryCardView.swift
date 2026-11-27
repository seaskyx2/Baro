import BaroCore
import SwiftUI

public struct MemoryCardView: View {
    public let memory: MemorySnapshot
    public let history: [Double]
    public let isExpanded: Bool
    public let onToggleExpand: () -> Void

    public init(
        memory: MemorySnapshot,
        history: [Double],
        isExpanded: Bool,
        onToggleExpand: @escaping () -> Void
    ) {
        self.memory = memory
        self.history = history
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        let total = max(1.0, Double(memory.totalBytes))
        let segments = [
            MemorySegment(id: "app", ratio: Double(memory.appBytes) / total, color: BaroPalette.memoryApp),
            MemorySegment(id: "wired", ratio: Double(memory.wiredBytes) / total, color: BaroPalette.memoryWired),
            MemorySegment(id: "compressed", ratio: Double(memory.compressedBytes) / total, color: BaroPalette.memoryCompressed)
        ]

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label("统一内存", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteFormatter.memorySize(memory.usedBytes))
                    .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(pressureColor)
            }

            SparklineView(
                values: history,
                lineColor: BaroPalette.memoryApp,
                fixedMax: 100,
                valueFormatter: { String(format: "%.0f%%", $0) }
            )
            .frame(height: 28)

            SegmentedBarView(segments: segments, height: 5.5)

            HStack {
                Text("活跃 \(ByteFormatter.memorySize(memory.appBytes)) · 压缩 \(ByteFormatter.memorySize(memory.compressedBytes))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            HStack {
                Text("压力: \(memory.pressure.displayName)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(memory.pressure == .normal ? AnyShapeStyle(.secondary) : AnyShapeStyle(pressureColor))
                Spacer()
                Text("Swap \(ByteFormatter.memorySize(memory.swapUsedBytes))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Divider().opacity(0.35)
                memoryDetailsDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .bentoCard(isExpanded: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: return .primary
        case .warning: return BaroPalette.healthColor(for: .moderate)
        case .critical: return BaroPalette.healthColor(for: .elevated)
        }
    }

    private var memoryDetailsDrawer: some View {
        VStack(spacing: 3.5) {
            detailRow(dot: BaroPalette.memoryApp, title: "App 内存", value: ByteFormatter.memorySize(memory.appBytes))
            detailRow(dot: BaroPalette.memoryWired, title: "联动内存", value: ByteFormatter.memorySize(memory.wiredBytes))
            detailRow(dot: BaroPalette.memoryCompressed, title: "已压缩", value: ByteFormatter.memorySize(memory.compressedBytes))
            detailRow(dot: Color.secondary.opacity(0.5), title: "已缓存文件", value: ByteFormatter.memorySize(memory.cachedFilesBytes))
            detailRow(dot: Color.primary.opacity(0.2), title: "剩余可用", value: ByteFormatter.memorySize(memory.freeBytes))
        }
        .padding(.top, 2)
    }

    private func detailRow(dot: Color, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 5.5, height: 5.5)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}
