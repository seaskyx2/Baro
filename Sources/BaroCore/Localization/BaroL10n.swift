import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }
}

public enum ResolvedLanguage: String, Sendable, Equatable {
    case zhHans
    case en
}

public enum BaroL10n {
    public static func resolve(_ preference: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedLanguage {
        switch preference {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        case .system:
            if let first = preferredLanguages.first?.lowercased(), first.hasPrefix("zh") {
                return .zhHans
            }
            return .en
        }
    }

    public static func t(_ zh: String, _ en: String, lang: ResolvedLanguage) -> String {
        lang == .zhHans ? zh : en
    }

    public static func languageOptionTitle(_ option: AppLanguage, lang: ResolvedLanguage) -> String {
        switch option {
        case .system: return t("跟随系统", "Follow System", lang: lang)
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    public static func menuBarStyleTitle(_ style: MenuBarStyle, lang: ResolvedLanguage) -> String {
        switch style {
        case .compactDualRow: return t("双行精工", "Dual-Row Precision", lang: lang)
        case .singleLine: return t("单行胶囊", "Inline Pill", lang: lang)
        case .sparkline: return t("脉搏微图", "Pulse Graph", lang: lang)
        case .miniBars: return t("精工双柱", "Micro Meters", lang: lang)
        case .breathingDot: return t("灵动圆环", "Halo Dot", lang: lang)
        }
    }

    public static func menuBarStyleSubtitle(_ style: MenuBarStyle, lang: ResolvedLanguage) -> String {
        switch style {
        case .compactDualRow:
            return t("微分割双行精密排布，紧凑防遮挡", "Hairline-divided dual-row instrument layout", lang: lang)
        case .singleLine:
            return t("微缩硬件符号与圆角浅框，大屏舒展直读", "Micro hardware glyphs framed in a sleek subtle pill", lang: lang)
        case .sparkline:
            return t("平滑面积波形视窗 + 内存圆环微表盘", "Smooth area waveform viewport + memory ring gauge", lang: lang)
        case .miniBars:
            return t("原生单色双槽液位表，极致节省刘海空间", "Native monochrome twin capsule meters for notched screens", lang: lang)
        case .breathingDot:
            return t("同心光晕状态灯，高压时浮现占用图标", "Concentric halo dot; reveals top app icon under high load", lang: lang)
        }
    }

    public static func menuBarMetricTitle(_ metric: MenuBarMetric, lang: ResolvedLanguage) -> String {
        switch metric {
        case .cpu: return t("CPU 占用率", "CPU Usage", lang: lang)
        case .memory: return t("统一内存占用率", "Memory Usage", lang: lang)
        case .network: return t("实时上传 / 下载网速", "Network Speed (Up / Down)", lang: lang)
        case .temperature: return t("SoC 芯片温度", "SoC Temperature", lang: lang)
        case .power: return t("整机实时功耗（W）", "System Power (W)", lang: lang)
        }
    }

    public static func pressureDisplayName(_ level: MemoryPressureLevel, lang: ResolvedLanguage) -> String {
        switch level {
        case .normal: return t("正常", "Normal", lang: lang)
        case .warning: return t("偏高", "Elevated", lang: lang)
        case .critical: return t("紧张", "Critical", lang: lang)
        }
    }

    public static func powerSourceTitle(_ kind: PowerSourceKind, lang: ResolvedLanguage) -> String {
        switch kind {
        case .acPower: return t("交流电源", "AC Power", lang: lang)
        case .powerAdapter: return t("电源适配器", "Power Adapter", lang: lang)
        case .internalBattery: return t("内置电池", "Internal Battery", lang: lang)
        }
    }
}
