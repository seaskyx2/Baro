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
        TabView {
            generalTab
                .tabItem {
                    Label("常规", systemImage: "slider.horizontal.3")
                }

            menuBarTab
                .tabItem {
                    Label("菜单栏", systemImage: "menubar.rectangle")
                }

            modulesTab
                .tabItem {
                    Label("模块与提醒", systemImage: "square.grid.2x2")
                }
        }
        .padding(18)
        .frame(width: 440, height: 340)
    }

    private var generalTab: some View {
        Form {
            Section("启动与省电") {
                Toggle("登录时自动启动 Baro", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }

                if let msg = launchStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("低电量模式下自动放慢采样频率", isOn: $settings.adaptToLowPower)
            }

            Section("冷热分层采样频率") {
                Picker("后台冷态刷新（面板收起）", selection: $settings.coldInterval) {
                    Text("1.0 秒").tag(1.0)
                    Text("2.0 秒（推荐）").tag(2.0)
                    Text("3.0 秒").tag(3.0)
                    Text("5.0 秒").tag(5.0)
                }

                Picker("面板热态刷新（面板展开）", selection: $settings.hotInterval) {
                    Text("1.0 秒").tag(1.0)
                    Text("1.5 秒（推荐）").tag(1.5)
                    Text("2.0 秒").tag(2.0)
                }
            }

            Section("零入侵声明") {
                Text("Baro 仅调用只读系统接口，不含清理、强杀进程、调速、联网与历史落盘逻辑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var menuBarTab: some View {
        Form {
            Section("单槽位视觉风格") {
                Picker("显示风格", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Text(settings.menuBarStyle.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏显示指标（建议 2–3 项）") {
                Toggle("CPU 占用率", isOn: $settings.showMenuCPU)
                Toggle("统一内存占用率", isOn: $settings.showMenuMemory)
                Toggle("实时上传 / 下载网速", isOn: $settings.showMenuNetwork)
                Toggle("SoC 芯片温度", isOn: $settings.showMenuTemperature)
                Toggle("整机实时功耗（W）", isOn: $settings.showMenuPower)
            }
        }
        .formStyle(.grouped)
    }

    private var modulesTab: some View {
        Form {
            Section("仪表盘卡片") {
                Toggle("CPU 与分核负载", isOn: $settings.showCPUCard)
                Toggle("统一内存与压力", isOn: $settings.showMemoryCard)
                Toggle("芯片功耗、GPU 与风扇", isOn: $settings.showPowerGPUCard)
                Toggle("实时网络吞吐", isOn: $settings.showNetworkCard)
                Toggle("磁盘存储与读写速率", isOn: $settings.showDiskCard)
                Toggle("电源、电池与苹果外设电量", isOn: $settings.showBatteryPowerCard)
                Toggle("按 App 归并 Top 5 资源榜", isOn: $settings.showTopAppsSection)
                Toggle("在台式机上预览笔记本电池卡片", isOn: $settings.previewLaptopBatteryOnDesktop)
            }

            Section("可选只读通知提醒（默认关闭）") {
                Toggle("芯片温度过高提醒", isOn: $settings.enableThermalAlert)
                    .onChange(of: settings.enableThermalAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
                if settings.enableThermalAlert {
                    HStack {
                        Text("温度阈值")
                        Slider(value: $settings.thermalAlertThreshold, in: 75...105, step: 1)
                        Text("\(Int(settings.thermalAlertThreshold))°C")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("内存压力紧张提醒", isOn: $settings.enableMemoryAlert)
                    .onChange(of: settings.enableMemoryAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
                Toggle("笔记本低电量提醒（≤ 15%）", isOn: $settings.enableLowBatteryAlert)
                    .onChange(of: settings.enableLowBatteryAlert) { _, val in
                        if val { SamplingCoordinator.requestNotificationPermissionIfNeeded() }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                launchStatusMessage = "已加入登录项，可在系统设置随时关闭。"
            } else {
                try SMAppService.mainApp.unregister()
                launchStatusMessage = "已取消登录自启。"
            }
        } catch {
            launchStatusMessage = "提示：请先将 Baro.app 放入 /Applications 目录后再开启登录项。"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
