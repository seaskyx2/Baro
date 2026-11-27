import Foundation

public enum HealthAnalyzer {
    public static func analyze(
        snapshot: SystemSnapshot,
        topCPUApp: AggregatedAppUsage? = nil,
        topMemoryApp: AggregatedAppUsage? = nil,
        language: ResolvedLanguage = .zhHans
    ) -> HealthSummary {
        let temp = snapshot.thermalFan.primaryTemperature ?? 0
        let cpu = snapshot.cpu.totalUsagePercent
        let pressure = snapshot.memory.pressure
        let swapBytes = snapshot.memory.swapUsedBytes
        let twoGB: UInt64 = 2 * 1_024 * 1_024 * 1_024

        if temp >= 92.0 {
            let deg = Int(temp.rounded())
            return HealthSummary(
                level: .elevated,
                message: BaroL10n.t("温度偏高 · SoC \(deg)°C", "High Temp · SoC \(deg)°C", lang: language)
            )
        }

        if pressure == .critical {
            if let memApp = topMemoryApp {
                let sz = ByteFormatter.memorySize(memApp.memoryBytes)
                return HealthSummary(
                    level: .elevated,
                    message: BaroL10n.t("内存紧张 · \(memApp.name) 占用 \(sz)", "Memory Critical · \(memApp.name) using \(sz)", lang: language)
                )
            }
            return HealthSummary(
                level: .elevated,
                message: BaroL10n.t("内存紧张 · 压力偏高", "Memory Pressure Critical", lang: language)
            )
        }

        if cpu >= 75.0 {
            if let cpuApp = topCPUApp, cpuApp.cpuPercent >= 15.0 {
                let pct = Int(cpuApp.cpuPercent.rounded())
                return HealthSummary(
                    level: .elevated,
                    message: BaroL10n.t("高负载 · \(cpuApp.name) 占用 \(pct)% CPU", "High Load · \(cpuApp.name) at \(pct)% CPU", lang: language)
                )
            }
            let pct = Int(cpu.rounded())
            return HealthSummary(
                level: .elevated,
                message: BaroL10n.t("高负载 · CPU \(pct)%", "High Load · CPU \(pct)%", lang: language)
            )
        }

        if pressure == .warning {
            let pct = Int(snapshot.memory.usedPercent.rounded())
            return HealthSummary(
                level: .moderate,
                message: BaroL10n.t("内存压力上升 · 已用 \(pct)%", "Memory Pressure Rising · \(pct)% used", lang: language)
            )
        }

        if cpu >= 45.0 {
            if let cpuApp = topCPUApp, cpuApp.cpuPercent >= 15.0 {
                return HealthSummary(
                    level: .moderate,
                    message: BaroL10n.t("负载中等 · \(cpuApp.name) 活跃中", "Moderate Load · \(cpuApp.name) active", lang: language)
                )
            }
            let pct = Int(cpu.rounded())
            return HealthSummary(
                level: .moderate,
                message: BaroL10n.t("负载中等 · CPU \(pct)%", "Moderate Load · CPU \(pct)%", lang: language)
            )
        }

        if swapBytes >= twoGB {
            let sw = ByteFormatter.memorySize(swapBytes)
            return HealthSummary(
                level: .moderate,
                message: BaroL10n.t("轻度交换 · Swap \(sw)", "Active Swap · \(sw)", lang: language)
            )
        }

        if swapBytes == 0 {
            return HealthSummary(
                level: .calm,
                message: BaroL10n.t("系统平静 · 零交换压力", "Calm · Zero swap pressure", lang: language)
            )
        }

        return HealthSummary(
            level: .calm,
            message: BaroL10n.t("系统平静 · 运行流畅", "Calm · Running smoothly", lang: language)
        )
    }
}
