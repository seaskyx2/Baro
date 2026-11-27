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
        case .compactDualRow: return t("双行精工", "Compact Dual-Row", lang: lang)
        case .sparkline: return t("微图表", "Sparkline", lang: lang)
        case .breathingDot: return t("静默呼吸点", "Breathing Dot", lang: lang)
        }
    }

    public static func menuBarStyleSubtitle(_ style: MenuBarStyle, lang: ResolvedLanguage) -> String {
        switch style {
        case .compactDualRow:
            return t("单槽位双行紧凑排布，省空间无遮挡", "Single-slot dual-row layout, crisp & notch-safe", lang: lang)
        case .sparkline:
            return t("CPU 实时微曲线 + 内存比例胶囊", "Live CPU sparkline + memory capsule", lang: lang)
        case .breathingDot:
            return t("平常仅显示状态呼吸点，高压时浮现占用图标", "Calm status dot; reveals top app icon under high load", lang: lang)
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
}
