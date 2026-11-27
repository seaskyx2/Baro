import Foundation

/// 生成纯文本、严格脱敏（不含任何 IP、用户名、主机名或磁盘个人路径）的只读系统快照
public enum SnapshotExporter {
    public static func formatPlainText(
        hostInfo: HostStaticInfo,
        snapshot: SystemSnapshot,
        health: HealthSummary,
        lang: ResolvedLanguage
    ) -> String {
        var lines: [String] = []
        lines.append(BaroL10n.t("## Baro 系统状态快照（只读脱敏）", "## Baro System Snapshot (Sanitized)", lang: lang))
        lines.append("- Host: \(hostInfo.chipName) | \(hostInfo.osVersionString) | RAM \(ByteFormatter.memorySize(hostInfo.totalMemoryBytes))")
        lines.append("- Uptime: \(ByteFormatter.uptime(snapshot.uptimeSeconds))")
        lines.append("- Health: \(health.message)")

        let cpuLine = String(
            format: "- CPU: %.1f%% (P: %.1f%% / E: %.1f%%) | Load: %.2f %.2f %.2f",
            snapshot.cpu.totalUsagePercent,
            snapshot.cpu.pCoreUsagePercent,
            snapshot.cpu.eCoreUsagePercent,
            snapshot.cpu.loadAverage1m,
            snapshot.cpu.loadAverage5m,
            snapshot.cpu.loadAverage15m
        )
        lines.append(cpuLine)

        lines.append(
            "- Memory: \(ByteFormatter.memorySize(snapshot.memory.usedBytes)) / \(ByteFormatter.memorySize(snapshot.memory.totalBytes)) (\(Int(snapshot.memory.usedPercent.rounded()))%) | Swap: \(ByteFormatter.memorySize(snapshot.memory.swapUsedBytes)) | Pressure: \(BaroL10n.pressureDisplayName(snapshot.memory.pressure, lang: lang))"
        )

        if snapshot.siliconPower.isAvailable {
            lines.append(
                String(
                    format: "- Power & GPU: %.1f W | GPU %d%%",
                    snapshot.siliconPower.packageWatts,
                    Int(snapshot.siliconPower.gpuUsagePercent.rounded())
                )
            )
        }

        if let temp = snapshot.thermalFan.primaryTemperature {
            let fanText = snapshot.thermalFan.fans.first.map { " | Fan \($0.currentRPM) RPM" } ?? ""
            lines.append(String(format: "- Thermal: %.1f°C%@", temp, fanText))
        }

        lines.append(
            "- Network: ↓ \(ByteFormatter.detailedRate(snapshot.network.downloadBytesPerSec)) | ↑ \(ByteFormatter.detailedRate(snapshot.network.uploadBytesPerSec)) | Session \(ByteFormatter.diskSize(snapshot.network.sessionDownloadBytes + snapshot.network.sessionUploadBytes))"
        )

        if let vol = snapshot.disk.primaryVolume {
            var diskLine = "- Storage: \(ByteFormatter.diskSize(vol.availableBytes)) free / \(ByteFormatter.diskSize(vol.totalBytes)) (\(Int(vol.usedPercent.rounded()))% used)"
            if let smart = snapshot.disk.smart, smart.isAvailable {
                diskLine += " | SSD Health \(smart.healthPercent)% | TBW \(ByteFormatter.diskSize(smart.totalBytesWritten))"
            }
            lines.append(diskLine)
        }

        if !snapshot.sleepBlockers.isEmpty {
            let names = snapshot.sleepBlockers.map(\.processName).joined(separator: ", ")
            lines.append("- Sleep Assertions: \(names)")
        }

        if !snapshot.topCPUApps.isEmpty {
            let topCPU = snapshot.topCPUApps.prefix(5).map {
                "\($0.name) (\(String(format: "%.1f%%", $0.cpuPercent)), \(ByteFormatter.memorySize($0.memoryBytes)))"
            }.joined(separator: "; ")
            lines.append("- Top CPU Apps: \(topCPU)")
        }

        if !snapshot.topMemoryApps.isEmpty {
            let topMem = snapshot.topMemoryApps.prefix(5).map {
                "\($0.name) (\(ByteFormatter.memorySize($0.memoryBytes)))"
            }.joined(separator: "; ")
            lines.append("- Top Memory Apps: \(topMem)")
        }

        return lines.joined(separator: "\n")
    }
}
