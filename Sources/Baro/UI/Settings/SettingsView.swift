import AppKit
import BaroCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: BaroSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchStatusMessage: String?

    public init(settings: BaroSettings) {
        self.settings = settings
    }

    public var body: some View {
        let lang = settings.resolvedLanguage

        TabView {
            generalTab(lang: lang)
                .tabItem {
                    Label(BaroL10n.t("常规", "General", lang: lang), systemImage: "slider.horizontal.3")
                }

            menuBarTab(lang: lang)
                .tabItem {
                    Label(BaroL10n.t("菜单栏", "Menu Bar", lang: lang), systemImage: "menubar.rectangle")
                }

            modulesTab(lang: lang)
                .tabItem {
                    Label(BaroL10n.t("模块与提醒", "Modules & Alerts", lang: lang), systemImage: "square.grid.2x2")
                }
        }
        .padding(18)
        .frame(width: 480, height: 460)
    }

    private func generalTab(lang: ResolvedLanguage) -> some View {
        Form {
            Section(BaroL10n.t("语言与外观", "Language", lang: lang)) {
                Picker(BaroL10n.t("界面语言", "Interface Language", lang: lang), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(BaroL10n.languageOptionTitle(option, lang: lang)).tag(option)
                    }
                }
            }

            Section(BaroL10n.t("启动与省电", "Startup & Power", lang: lang)) {
                Toggle(BaroL10n.t("登录时自动启动 Baro", "Launch Baro at login", lang: lang), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled, lang: lang)
                    }

                if let msg = launchStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(BaroL10n.t("低电量模式下自动放慢采样频率", "Slow down sampling in Low Power Mode", lang: lang), isOn: $settings.adaptToLowPower)

                Toggle(BaroL10n.t("全局快捷键呼出 / 收起仪表盘", "Global shortcut to toggle dashboard", lang: lang), isOn: $settings.enableGlobalHotKey)

                if settings.enableGlobalHotKey {
                    Picker(BaroL10n.t("快捷键组合", "Shortcut", lang: lang), selection: $settings.globalHotKeyPreset) {
                        ForEach(GlobalHotKeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                }
            }

            Section(BaroL10n.t("冷热分层采样频率", "Cold / Hot Sampling Intervals", lang: lang)) {
                Picker(BaroL10n.t("后台冷态刷新（面板收起）", "Cold Refresh (Collapsed)", lang: lang), selection: $settings.coldInterval) {
                    Text(BaroL10n.t("1.0 秒", "1.0s", lang: lang)).tag(1.0)
                    Text(BaroL10n.t("2.0 秒（推荐）", "2.0s (Recommended)", lang: lang)).tag(2.0)
                    Text(BaroL10n.t("3.0 秒", "3.0s", lang: lang)).tag(3.0)
                    Text(BaroL10n.t("5.0 秒", "5.0s", lang: lang)).tag(5.0)
                }

                Picker(BaroL10n.t("面板热态刷新（面板展开）", "Hot Refresh (Expanded)", lang: lang), selection: $settings.hotInterval) {
                    Text(BaroL10n.t("1.0 秒", "1.0s", lang: lang)).tag(1.0)
                    Text(BaroL10n.t("1.5 秒（推荐）", "1.5s (Recommended)", lang: lang)).tag(1.5)
                    Text(BaroL10n.t("2.0 秒", "2.0s", lang: lang)).tag(2.0)
                }
            }

            Section(BaroL10n.t("零入侵声明", "Zero-Intrusion Guarantee", lang: lang)) {
                Text(BaroL10n.t(
                    "Baro 仅调用只读系统接口，不含清理、强杀进程、调速与历史落盘逻辑；默认不联网，仅在手动检查更新时访问 GitHub。",
                    "Baro uses read-only system APIs only. No cleanup, kill switches, fan overrides, or history logs. Offline by default; only a manual update check contacts GitHub.",
                    lang: lang
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func menuBarTab(lang: ResolvedLanguage) -> some View {
        Form {
            Section(BaroL10n.t("实时状态栏预览", "Live Menu Bar Preview", lang: lang)) {
                liveMenuBarPreviewStrip(lang: lang)
            }

            Section(BaroL10n.t("单槽位视觉风格", "Single-Slot Display Style", lang: lang)) {
                ForEach(MenuBarStyle.allCases) { style in
                    styleOptionRow(style: style, lang: lang)
                }

                Toggle(BaroL10n.t("显示晴雨表动态表盘图标", "Show dynamic barometer dial icon", lang: lang), isOn: $settings.showMenuBarIcon)
            }

            Section(BaroL10n.t("菜单栏显示指标（建议 2–3 项）", "Visible Metrics (2–3 Recommended)", lang: lang)) {
                Toggle(BaroL10n.menuBarMetricTitle(.cpu, lang: lang), isOn: $settings.showMenuCPU)
                Toggle(BaroL10n.menuBarMetricTitle(.memory, lang: lang), isOn: $settings.showMenuMemory)
                Toggle(BaroL10n.menuBarMetricTitle(.network, lang: lang), isOn: $settings.showMenuNetwork)
                Toggle(BaroL10n.menuBarMetricTitle(.temperature, lang: lang), isOn: $settings.showMenuTemperature)
                Toggle(BaroL10n.menuBarMetricTitle(.power, lang: lang), isOn: $settings.showMenuPower)
            }
        }
        .formStyle(.grouped)
    }

    private func liveMenuBarPreviewStrip(lang: ResolvedLanguage) -> some View {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let previewAppearance = NSAppearance(named: appearanceName) ?? NSApp.effectiveAppearance
        let previewImg = MenuBarImageRenderer.render(
            data: samplePreviewData,
            settings: settings,
            appearance: previewAppearance
        )

        return HStack(spacing: 0) {
            Text(BaroL10n.t("菜单栏光学比例参考", "Optical Scale Reference", lang: lang))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 11) {
                Image(nsImage: previewImg)
                    .interpolation(.high)

                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.88))

                Image(systemName: "switch.2")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.88))

                Text("9:41")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.92))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
                    )
            )
        }
        .padding(.vertical, 2)
    }

    private func styleOptionRow(style: MenuBarStyle, lang: ResolvedLanguage) -> some View {
        let isSelected = settings.menuBarStyle == style
        return Button {
            settings.menuBarStyle = style
        } label: {
            HStack(spacing: 10) {
                Image(systemName: styleSymbolName(for: style))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(BaroL10n.menuBarStyleTitle(style, lang: lang))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(BaroL10n.menuBarStyleSubtitle(style, lang: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func styleSymbolName(for style: MenuBarStyle) -> String {
        switch style {
        case .compactDualRow: return "rectangle.split.1x2"
        case .singleLine: return "capsule"
        case .sparkline: return "waveform.path.ecg.rectangle"
        case .miniBars: return "slider.vertical.3"
        case .breathingDot: return "smallcircle.filled.circle"
        }
    }

    private var samplePreviewData: MenuBarRenderData {
        var d = MenuBarRenderData.empty
        d.cpuPercent = 18
        d.memoryPercent = 64
        d.memoryPressure = .normal
        d.uploadBytesPerSec = 42 * 1_024
        d.downloadBytesPerSec = 3.8 * 1_024 * 1_024
        d.temperatureCelsius = 42
        d.packageWatts = 14.2
        d.isPowerAvailable = true
        d.healthLevel = .calm
        d.cpuSparklinePoints = [12, 16, 14, 28, 22, 19, 34, 26, 15, 18]
        return d
    }

    private func modulesTab(lang: ResolvedLanguage) -> some View {
        Form {
            Section(BaroL10n.t("仪表盘卡片", "Dashboard Cards", lang: lang)) {
                Toggle(BaroL10n.t("CPU 与分核负载", "CPU & Per-Core Load", lang: lang), isOn: $settings.showCPUCard)
                Toggle(BaroL10n.t("统一内存与压力", "Unified Memory & Pressure", lang: lang), isOn: $settings.showMemoryCard)
                Toggle(BaroL10n.t("芯片功耗、GPU 与风扇", "SoC Power, GPU & Fans", lang: lang), isOn: $settings.showPowerGPUCard)
                Toggle(BaroL10n.t("实时网络吞吐", "Network Throughput", lang: lang), isOn: $settings.showNetworkCard)
                Toggle(BaroL10n.t("磁盘存储与读写速率", "Storage & Disk I/O", lang: lang), isOn: $settings.showDiskCard)
                Toggle(BaroL10n.t("电源、电池与苹果外设电量", "Power, Battery & Apple HID", lang: lang), isOn: $settings.showBatteryPowerCard)
                Toggle(BaroL10n.t("按 App 归并 Top 5 资源榜", "Top 5 Grouped Apps", lang: lang), isOn: $settings.showTopAppsSection)
                Toggle(BaroL10n.t("在台式机上预览笔记本电池卡片", "Preview Laptop Battery Card on Desktop", lang: lang), isOn: $settings.previewLaptopBatteryOnDesktop)
            }

            Section(BaroL10n.t("可选只读通知提醒（默认关闭）", "Optional Read-Only Alerts (Off by Default)", lang: lang)) {
                Toggle(BaroL10n.t("芯片温度过高提醒", "High Temperature Alert", lang: lang), isOn: $settings.enableThermalAlert)
                    .onChange(of: settings.enableThermalAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
                if settings.enableThermalAlert {
                    HStack {
                        Text(BaroL10n.t("温度阈值", "Threshold", lang: lang))
                        Slider(value: $settings.thermalAlertThreshold, in: 75...105, step: 1)
                        Text("\(Int(settings.thermalAlertThreshold))°C")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(BaroL10n.t("内存压力紧张提醒", "Critical Memory Pressure Alert", lang: lang), isOn: $settings.enableMemoryAlert)
                    .onChange(of: settings.enableMemoryAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
                Toggle(BaroL10n.t("笔记本低电量提醒（≤ 15%）", "Low Battery Alert (≤ 15%)", lang: lang), isOn: $settings.enableLowBatteryAlert)
                    .onChange(of: settings.enableLowBatteryAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool, lang: ResolvedLanguage) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                launchStatusMessage = BaroL10n.t("已加入登录项，可在系统设置随时关闭。", "Added to Login Items.", lang: lang)
            } else {
                try SMAppService.mainApp.unregister()
                launchStatusMessage = BaroL10n.t("已取消登录自启。", "Removed from Login Items.", lang: lang)
            }
        } catch {
            launchStatusMessage = BaroL10n.t(
                "提示：请先将 Baro.app 放入 /Applications 目录后再开启登录项。",
                "Move Baro.app into /Applications before enabling Launch at Login.",
                lang: lang
            )
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
