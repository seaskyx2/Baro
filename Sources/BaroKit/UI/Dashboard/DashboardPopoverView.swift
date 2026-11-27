import BaroCore
import SwiftUI

public struct DashboardPopoverView: View {
    @ObservedObject public var coordinator: SamplingCoordinator
    @ObservedObject public var settings: BaroSettings
    public let onOpenSettings: () -> Void
    public let onLayoutChanged: () -> Void

    @State private var expandedCPU = false
    @State private var expandedMemory = false
    @State private var expandedPower = false
    @State private var expandedDisk = false
    @State private var copiedSnapshot = false

    public init(
        coordinator: SamplingCoordinator,
        settings: BaroSettings,
        onOpenSettings: @escaping () -> Void,
        onLayoutChanged: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onLayoutChanged = onLayoutChanged
    }

    public var body: some View {
        Group {
            if coordinator.isPanelOpen {
                dashboardBody(lang: settings.resolvedLanguage)
            } else {
                Color.clear
                    .frame(width: 364, height: 10)
            }
        }
    }

    private func dashboardBody(lang: ResolvedLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection(lang: lang)

            if settings.showCPUCard || settings.showMemoryCard {
                twoColumnGrid {
                    if settings.showCPUCard {
                        CPUCardView(
                            cpu: coordinator.snapshot.cpu,
                            history: coordinator.cpuHistory,
                            temperature: coordinator.snapshot.thermalFan.cpuTemperature ?? coordinator.snapshot.thermalFan.socTemperature,
                            lang: lang,
                            isExpanded: expandedCPU,
                            onToggleExpand: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expandedCPU.toggle()
                                }
                                onLayoutChanged()
                            }
                        )
                    }

                    if settings.showMemoryCard {
                        MemoryCardView(
                            memory: coordinator.snapshot.memory,
                            history: coordinator.memoryHistory,
                            lang: lang,
                            isExpanded: expandedMemory,
                            onToggleExpand: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expandedMemory.toggle()
                                }
                                onLayoutChanged()
                            }
                        )
                    }
                }
            }

            if settings.showPowerGPUCard || settings.showNetworkCard {
                twoColumnGrid {
                    if settings.showPowerGPUCard {
                        PowerGPUCardView(
                            power: coordinator.snapshot.siliconPower,
                            thermal: coordinator.snapshot.thermalFan,
                            powerHistory: coordinator.powerHistory,
                            lang: lang,
                            isExpanded: expandedPower,
                            onToggleExpand: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expandedPower.toggle()
                                }
                                onLayoutChanged()
                            }
                        )
                    }

                    if settings.showNetworkCard {
                        NetworkCardView(
                            network: coordinator.snapshot.network,
                            downloadHistory: coordinator.downloadHistory,
                            uploadHistory: coordinator.uploadHistory,
                            lang: lang
                        )
                    }
                }
            }

            if settings.showDiskCard || settings.showBatteryPowerCard {
                twoColumnGrid {
                    if settings.showDiskCard {
                        DiskCardView(
                            disk: coordinator.snapshot.disk,
                            lang: lang,
                            isExpanded: expandedDisk,
                            onToggleExpand: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    expandedDisk.toggle()
                                }
                                onLayoutChanged()
                            }
                        )
                    }

                    if settings.showBatteryPowerCard {
                        BatteryPowerCardView(
                            batteryPower: coordinator.snapshot.batteryPower,
                            sleepBlockers: coordinator.snapshot.sleepBlockers,
                            previewLaptopMode: settings.previewLaptopBatteryOnDesktop,
                            lang: lang
                        )
                    }
                }
            }

            if settings.showTopAppsSection {
                TopAppsSectionView(
                    topCPUApps: coordinator.snapshot.topCPUApps,
                    topMemoryApps: coordinator.snapshot.topMemoryApps,
                    lang: lang,
                    preferredModeRaw: $settings.preferredTopAppsMode
                )
            }

            footerSection(lang: lang)
        }
        .padding(12)
        .frame(width: 364)
        .baroLiquidGlass(cornerRadius: 22)
        .onChange(of: expandedCPU) { _, _ in onLayoutChanged() }
        .onChange(of: expandedMemory) { _, _ in onLayoutChanged() }
        .onChange(of: expandedPower) { _, _ in onLayoutChanged() }
        .onChange(of: expandedDisk) { _, _ in onLayoutChanged() }
    }

    private func headerSection(lang: ResolvedLanguage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "barometer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(coordinator.hostInfo.chipName) (\(ByteFormatter.memorySize(coordinator.hostInfo.totalMemoryBytes)))")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("Up \(ByteFormatter.uptime(coordinator.snapshot.uptimeSeconds))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    let text = SnapshotExporter.formatPlainText(
                        hostInfo: coordinator.hostInfo,
                        snapshot: coordinator.snapshot,
                        health: coordinator.healthSummary,
                        lang: lang
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedSnapshot = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedSnapshot = false
                    }
                } label: {
                    Image(systemName: copiedSnapshot ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedSnapshot ? BaroPalette.batteryHealthy : .secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(BaroL10n.t("复制脱敏系统快照", "Copy Sanitized Snapshot", lang: lang))

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(BaroL10n.t("偏好设置", "Preferences", lang: lang))
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(BaroPalette.healthColor(for: coordinator.healthSummary.level))
                    .frame(width: 6.5, height: 6.5)
                Text(coordinator.healthSummary.message)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func footerSection(lang: ResolvedLanguage) -> some View {
        HStack {
            Text(BaroL10n.t("Baro 晴雨表 · 纯只读零入侵", "Baro · Read-Only, Zero Intrusion", lang: lang))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(coordinator.hostInfo.modelIdentifier)
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func twoColumnGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8, alignment: .top),
                GridItem(.flexible(), spacing: 8, alignment: .top)
            ],
            spacing: 8
        ) {
            content()
        }
    }
}
