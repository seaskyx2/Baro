import Foundation

public enum HealthAnalyzer {
    public static func analyze(
        snapshot: SystemSnapshot,
        topCPUApp: AggregatedAppUsage? = nil,
        topMemoryApp: AggregatedAppUsage? = nil
    ) -> HealthSummary {
        let temp = snapshot.thermalFan.primaryTemperature ?? 0
        let cpu = snapshot.cpu.totalUsagePercent
        let pressure = snapshot.memory.pressure
        let swapBytes = snapshot.memory.swapUsedBytes
        let twoGB: UInt64 = 2 * 1_024 * 1_024 * 1_024

        if temp >= 92.0 {
            return HealthSummary(
                level: .elevated,
                message: "温度偏高 · SoC \(Int(temp.rounded()))°C"
            )
        }

        if pressure == .critical {
            if let memApp = topMemoryApp {
                return HealthSummary(
                    level: .elevated,
                    message: "内存紧张 · \(memApp.name) 占用 \(ByteFormatter.memorySize(memApp.memoryBytes))"
                )
            }
            return HealthSummary(level: .elevated, message: "内存紧张 · 压力偏高")
        }

        if cpu >= 75.0 {
            if let cpuApp = topCPUApp, cpuApp.cpuPercent >= 15.0 {
                return HealthSummary(
                    level: .elevated,
                    message: "高负载 · \(cpuApp.name) 占用 \(Int(cpuApp.cpuPercent.rounded()))% CPU"
                )
            }
            return HealthSummary(level: .elevated, message: "高负载 · CPU \(Int(cpu.rounded()))%")
        }

        if pressure == .warning {
            return HealthSummary(level: .moderate, message: "内存压力上升 · 已用 \(Int(snapshot.memory.usedPercent.rounded()))%")
        }

        if cpu >= 45.0 {
            if let cpuApp = topCPUApp, cpuApp.cpuPercent >= 15.0 {
                return HealthSummary(
                    level: .moderate,
                    message: "负载中等 · \(cpuApp.name) 活跃中"
                )
            }
            return HealthSummary(level: .moderate, message: "负载中等 · CPU \(Int(cpu.rounded()))%")
        }

        if swapBytes >= twoGB {
            return HealthSummary(
                level: .moderate,
                message: "轻度交换 · Swap \(ByteFormatter.memorySize(swapBytes))"
            )
        }

        if swapBytes == 0 {
            return HealthSummary(level: .calm, message: "系统平静 · 零交换压力")
        }

        return HealthSummary(level: .calm, message: "系统平静 · 运行流畅")
    }
}
