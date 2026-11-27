import AppKit
import BaroCore
import SwiftUI

public struct TopAppsSectionView: View {
    public enum SortMode: String, CaseIterable {
        case cpu
        case memory

        public func title(lang: ResolvedLanguage) -> String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return BaroL10n.t("内存", "Memory", lang: lang)
            }
        }
    }

    public let topCPUApps: [AggregatedAppUsage]
    public let topMemoryApps: [AggregatedAppUsage]
    public let lang: ResolvedLanguage
    @Binding public var preferredModeRaw: String

    public init(
        topCPUApps: [AggregatedAppUsage],
        topMemoryApps: [AggregatedAppUsage],
        lang: ResolvedLanguage,
        preferredModeRaw: Binding<String>
    ) {
        self.topCPUApps = topCPUApps
        self.topMemoryApps = topMemoryApps
        self.lang = lang
        self._preferredModeRaw = preferredModeRaw
    }

    private var mode: SortMode {
        SortMode(rawValue: preferredModeRaw) ?? .cpu
    }

    private var modeBinding: Binding<SortMode> {
        Binding(
            get: { SortMode(rawValue: preferredModeRaw) ?? .cpu },
            set: { preferredModeRaw = $0.rawValue }
        )
    }

    public var body: some View {
        let items = mode == .cpu ? topCPUApps : topMemoryApps

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(BaroL10n.t("资源占用排行（按 App 归并）", "Top Apps (Grouped)", lang: lang))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: modeBinding) {
                    ForEach(SortMode.allCases, id: \.self) { m in
                        Text(m.title(lang: lang)).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 96)
            }

            if items.isEmpty {
                Text(BaroL10n.t("正在采样进程树…", "Sampling processes…", lang: lang))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                let maxVal: Double = {
                    switch mode {
                    case .cpu: return max(100.0, items.first?.cpuPercent ?? 100.0)
                    case .memory: return max(1.0, Double(items.first?.memoryBytes ?? 1))
                    }
                }()

                VStack(spacing: 5) {
                    ForEach(items) { app in
                        appRow(app: app, maxVal: maxVal)
                    }
                }
            }
        }
        .bentoCard()
    }

    private func appRow(app: AggregatedAppUsage, maxVal: Double) -> some View {
        let ratio: Double = mode == .cpu
            ? min(1.0, max(0.0, app.cpuPercent / maxVal))
            : min(1.0, max(0.0, Double(app.memoryBytes) / maxVal))

        let valueLabel: String = mode == .cpu
            ? String(format: "%.1f%%", app.cpuPercent)
            : ByteFormatter.memorySize(app.memoryBytes)

        return HStack(spacing: 7) {
            appIcon(for: app)
                .frame(width: 15, height: 15)

            Text(app.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)

            if app.pidsCount > 1 {
                Text("×\(app.pidsCount)")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }

            Spacer(minLength: 4)

            ThinProgressBar(
                ratio: ratio,
                tint: mode == .cpu ? BaroPalette.pCore : BaroPalette.memoryApp,
                height: 4
            )
            .frame(width: 58)

            Text(valueLabel)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func appIcon(for app: AggregatedAppUsage) -> some View {
        if let path = app.appBundlePath {
            Image(nsImage: AppIconCache.shared.icon(forAppPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
