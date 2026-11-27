import BaroCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: BaroSettings

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
        .frame(width: 450, height: 365)
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
                    "Baro 仅调用只读系统接口，不含清理、强杀进程、调速、联网与历史落盘逻辑。",
                    "Baro uses read-only system APIs only. No cleanup, kill switches, fan overrides, or network calls.",
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
            Section(BaroL10n.t("单槽位视觉风格", "Single-Slot Style", lang: lang)) {
                Picker(BaroL10n.t("显示风格", "Style", lang: lang), selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(BaroL10n.menuBarStyleTitle(style, lang: lang)).tag(style)
                    }
                }
                Text(BaroL10n.menuBarStyleSubtitle(settings.menuBarStyle, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(BaroL10n.t("在菜单栏左侧显示晴雨表图标", "Show barometer icon in menu bar", lang: lang), isOn: $settings.showMenuBarIcon)
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
