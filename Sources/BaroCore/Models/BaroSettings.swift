import Combine
import Foundation

public enum MenuBarStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case compactDualRow
    case singleLine
    case sparkline
    case miniBars
    case breathingDot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compactDualRow: return "双行精工"
        case .singleLine: return "单行胶囊"
        case .sparkline: return "脉搏微图"
        case .miniBars: return "精工双柱"
        case .breathingDot: return "灵动圆环"
        }
    }

    public var subtitle: String {
        switch self {
        case .compactDualRow: return "微分割双行精密排布，紧凑防遮挡"
        case .singleLine: return "微缩硬件符号与圆角浅框，大屏舒展直读"
        case .sparkline: return "平滑面积波形视窗 + 内存圆环微表盘"
        case .miniBars: return "原生单色双槽液位表，极致节省刘海空间"
        case .breathingDot: return "同心光晕状态灯，高压时浮现占用图标"
        }
    }
}

public enum GlobalHotKeyPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case ctrlOptionB
    case ctrlShiftB
    case optionCommandB

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ctrlOptionB: return "⌃⌥B"
        case .ctrlShiftB: return "⌃⇧B"
        case .optionCommandB: return "⌥⌘B"
        }
    }
}

public enum MenuBarMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu
    case memory
    case network
    case temperature
    case power

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .network: return "网速"
        case .temperature: return "温度"
        case .power: return "功耗"
        }
    }
}

@MainActor
public final class BaroSettings: ObservableObject {
    private enum Keys {
        static let language = "baro.language"
        static let menuBarStyle = "baro.menuBarStyle"
        static let showMenuBarIcon = "baro.showMenuBarIcon"
        static let showMenuCPU = "baro.showMenuCPU"
        static let showMenuMemory = "baro.showMenuMemory"
        static let showMenuNetwork = "baro.showMenuNetwork"
        static let showMenuTemperature = "baro.showMenuTemperature"
        static let showMenuPower = "baro.showMenuPower"
        static let coldInterval = "baro.coldInterval"
        static let hotInterval = "baro.hotInterval"
        static let adaptToLowPower = "baro.adaptToLowPower"
        static let enableGlobalHotKey = "baro.enableGlobalHotKey"
        static let globalHotKeyPreset = "baro.globalHotKeyPreset"
        static let showCPUCard = "baro.showCPUCard"
        static let showMemoryCard = "baro.showMemoryCard"
        static let showPowerGPUCard = "baro.showPowerGPUCard"
        static let showNetworkCard = "baro.showNetworkCard"
        static let showDiskCard = "baro.showDiskCard"
        static let showBatteryPowerCard = "baro.showBatteryPowerCard"
        static let showTopAppsSection = "baro.showTopAppsSection"
        static let preferredTopAppsMode = "baro.preferredTopAppsMode"
        static let previewLaptopBatteryOnDesktop = "baro.previewLaptopBatteryOnDesktop"
        static let enableThermalAlert = "baro.enableThermalAlert"
        static let thermalAlertThreshold = "baro.thermalAlertThreshold"
        static let enableMemoryAlert = "baro.enableMemoryAlert"
        static let enableLowBatteryAlert = "baro.enableLowBatteryAlert"
    }

    private let defaults: UserDefaults

    @Published public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published public var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    @Published public var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published public var showMenuCPU: Bool {
        didSet { defaults.set(showMenuCPU, forKey: Keys.showMenuCPU) }
    }
    @Published public var showMenuMemory: Bool {
        didSet { defaults.set(showMenuMemory, forKey: Keys.showMenuMemory) }
    }
    @Published public var showMenuNetwork: Bool {
        didSet { defaults.set(showMenuNetwork, forKey: Keys.showMenuNetwork) }
    }
    @Published public var showMenuTemperature: Bool {
        didSet { defaults.set(showMenuTemperature, forKey: Keys.showMenuTemperature) }
    }
    @Published public var showMenuPower: Bool {
        didSet { defaults.set(showMenuPower, forKey: Keys.showMenuPower) }
    }

    @Published public var coldInterval: TimeInterval {
        didSet { defaults.set(coldInterval, forKey: Keys.coldInterval) }
    }
    @Published public var hotInterval: TimeInterval {
        didSet { defaults.set(hotInterval, forKey: Keys.hotInterval) }
    }
    @Published public var adaptToLowPower: Bool {
        didSet { defaults.set(adaptToLowPower, forKey: Keys.adaptToLowPower) }
    }
    @Published public var enableGlobalHotKey: Bool {
        didSet { defaults.set(enableGlobalHotKey, forKey: Keys.enableGlobalHotKey) }
    }
    @Published public var globalHotKeyPreset: GlobalHotKeyPreset {
        didSet { defaults.set(globalHotKeyPreset.rawValue, forKey: Keys.globalHotKeyPreset) }
    }

    @Published public var showCPUCard: Bool {
        didSet { defaults.set(showCPUCard, forKey: Keys.showCPUCard) }
    }
    @Published public var showMemoryCard: Bool {
        didSet { defaults.set(showMemoryCard, forKey: Keys.showMemoryCard) }
    }
    @Published public var showPowerGPUCard: Bool {
        didSet { defaults.set(showPowerGPUCard, forKey: Keys.showPowerGPUCard) }
    }
    @Published public var showNetworkCard: Bool {
        didSet { defaults.set(showNetworkCard, forKey: Keys.showNetworkCard) }
    }
    @Published public var showDiskCard: Bool {
        didSet { defaults.set(showDiskCard, forKey: Keys.showDiskCard) }
    }
    @Published public var showBatteryPowerCard: Bool {
        didSet { defaults.set(showBatteryPowerCard, forKey: Keys.showBatteryPowerCard) }
    }
    @Published public var showTopAppsSection: Bool {
        didSet { defaults.set(showTopAppsSection, forKey: Keys.showTopAppsSection) }
    }
    @Published public var preferredTopAppsMode: String {
        didSet { defaults.set(preferredTopAppsMode, forKey: Keys.preferredTopAppsMode) }
    }
    @Published public var previewLaptopBatteryOnDesktop: Bool {
        didSet { defaults.set(previewLaptopBatteryOnDesktop, forKey: Keys.previewLaptopBatteryOnDesktop) }
    }

    @Published public var enableThermalAlert: Bool {
        didSet { defaults.set(enableThermalAlert, forKey: Keys.enableThermalAlert) }
    }
    @Published public var thermalAlertThreshold: Double {
        didSet { defaults.set(thermalAlertThreshold, forKey: Keys.thermalAlertThreshold) }
    }
    @Published public var enableMemoryAlert: Bool {
        didSet { defaults.set(enableMemoryAlert, forKey: Keys.enableMemoryAlert) }
    }
    @Published public var enableLowBatteryAlert: Bool {
        didSet { defaults.set(enableLowBatteryAlert, forKey: Keys.enableLowBatteryAlert) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawLang = defaults.string(forKey: Keys.language),
           let parsedLang = AppLanguage(rawValue: rawLang) {
            self.language = parsedLang
        } else {
            self.language = .system
        }

        if let raw = defaults.string(forKey: Keys.menuBarStyle),
           let parsed = MenuBarStyle(rawValue: raw) {
            self.menuBarStyle = parsed
        } else {
            self.menuBarStyle = .compactDualRow
        }

        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        self.showMenuCPU = defaults.object(forKey: Keys.showMenuCPU) as? Bool ?? true
        self.showMenuMemory = defaults.object(forKey: Keys.showMenuMemory) as? Bool ?? true
        self.showMenuNetwork = defaults.object(forKey: Keys.showMenuNetwork) as? Bool ?? true
        self.showMenuTemperature = defaults.object(forKey: Keys.showMenuTemperature) as? Bool ?? false
        self.showMenuPower = defaults.object(forKey: Keys.showMenuPower) as? Bool ?? false

        let savedCold = defaults.double(forKey: Keys.coldInterval)
        self.coldInterval = savedCold > 0 ? savedCold : 2.0
        let savedHot = defaults.double(forKey: Keys.hotInterval)
        self.hotInterval = savedHot > 0 ? savedHot : 1.5
        self.adaptToLowPower = defaults.object(forKey: Keys.adaptToLowPower) as? Bool ?? true
        self.enableGlobalHotKey = defaults.object(forKey: Keys.enableGlobalHotKey) as? Bool ?? true
        if let rawHK = defaults.string(forKey: Keys.globalHotKeyPreset),
           let parsedHK = GlobalHotKeyPreset(rawValue: rawHK) {
            self.globalHotKeyPreset = parsedHK
        } else {
            self.globalHotKeyPreset = .ctrlOptionB
        }

        self.showCPUCard = defaults.object(forKey: Keys.showCPUCard) as? Bool ?? true
        self.showMemoryCard = defaults.object(forKey: Keys.showMemoryCard) as? Bool ?? true
        self.showPowerGPUCard = defaults.object(forKey: Keys.showPowerGPUCard) as? Bool ?? true
        self.showNetworkCard = defaults.object(forKey: Keys.showNetworkCard) as? Bool ?? true
        self.showDiskCard = defaults.object(forKey: Keys.showDiskCard) as? Bool ?? true
        self.showBatteryPowerCard = defaults.object(forKey: Keys.showBatteryPowerCard) as? Bool ?? true
        self.showTopAppsSection = defaults.object(forKey: Keys.showTopAppsSection) as? Bool ?? true
        self.preferredTopAppsMode = defaults.string(forKey: Keys.preferredTopAppsMode) ?? "cpu"
        self.previewLaptopBatteryOnDesktop = defaults.object(forKey: Keys.previewLaptopBatteryOnDesktop) as? Bool ?? false

        self.enableThermalAlert = defaults.object(forKey: Keys.enableThermalAlert) as? Bool ?? false
        let savedThermal = defaults.double(forKey: Keys.thermalAlertThreshold)
        self.thermalAlertThreshold = savedThermal > 0 ? savedThermal : 92.0
        self.enableMemoryAlert = defaults.object(forKey: Keys.enableMemoryAlert) as? Bool ?? false
        self.enableLowBatteryAlert = defaults.object(forKey: Keys.enableLowBatteryAlert) as? Bool ?? false
    }

    public var resolvedLanguage: ResolvedLanguage {
        BaroL10n.resolve(language)
    }

    public var activeMenuMetrics: Set<MenuBarMetric> {
        var set: Set<MenuBarMetric> = []
        if showMenuCPU { set.insert(.cpu) }
        if showMenuMemory { set.insert(.memory) }
        if showMenuNetwork { set.insert(.network) }
        if showMenuTemperature { set.insert(.temperature) }
        if showMenuPower { set.insert(.power) }
        return set
    }
}
