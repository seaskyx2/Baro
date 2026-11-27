import AppKit
import BaroCore
import Foundation

@main
@MainActor
struct BaroMain {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            runHardwareProbe()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static func runHardwareProbe() {
        let host = HostInfoReader.readStaticInfo()
        let engine = CollectorEngine()

        // 首次基准采样 + 间隔 1 秒热态采样，确保所有差分指标生效
        _ = engine.sampleHot()
        Thread.sleep(forTimeInterval: 1.0)
        let snap = engine.sampleHot()
        let health = HealthAnalyzer.analyze(
            snapshot: snap,
            topCPUApp: snap.topCPUApps.first,
            topMemoryApp: snap.topMemoryApps.first
        )

        print("==================================================")
        print("Baro Read-Only Hardware Probe")
        print("==================================================")
        print("Host       : \(host.chipName) (\(host.modelIdentifier)) | \(host.osVersionString)")
        print("Cores      : \(host.totalCoreCount) total (\(host.pCoreCount)P + \(host.eCoreCount)E)")
        print("Memory Cap : \(ByteFormatter.memorySize(host.totalMemoryBytes))")
        print("Uptime     : \(ByteFormatter.uptime(snap.uptimeSeconds))")
        print("Health     : [\(health.level.rawValue.uppercased())] \(health.message)")
        print("--------------------------------------------------")
        print(String(
            format: "CPU        : %.1f%% (User %.1f%% / Sys %.1f%%) | P: %.1f%% | E: %.1f%% | Load: %.2f %.2f %.2f",
            snap.cpu.totalUsagePercent,
            snap.cpu.userPercent,
            snap.cpu.systemPercent,
            snap.cpu.pCoreUsagePercent,
            snap.cpu.eCoreUsagePercent,
            snap.cpu.loadAverage1m,
            snap.cpu.loadAverage5m,
            snap.cpu.loadAverage15m
        ))
        print("Memory     : Used \(ByteFormatter.memorySize(snap.memory.usedBytes)) (\(String(format: "%.1f%%", snap.memory.usedPercent))) | App \(ByteFormatter.memorySize(snap.memory.appBytes)) | Wired \(ByteFormatter.memorySize(snap.memory.wiredBytes)) | Compressed \(ByteFormatter.memorySize(snap.memory.compressedBytes)) | Swap \(ByteFormatter.memorySize(snap.memory.swapUsedBytes)) | Pressure: \(snap.memory.pressure.displayName)")
        print("Network    : \(snap.network.primaryInterface) (\(snap.network.localIPAddress)) | Down \(ByteFormatter.detailedRate(snap.network.downloadBytesPerSec)) | Up \(ByteFormatter.detailedRate(snap.network.uploadBytesPerSec))")
        if let vol = snap.disk.primaryVolume {
            print("Disk       : \(vol.name) Free \(ByteFormatter.diskSize(vol.availableBytes)) / \(ByteFormatter.diskSize(vol.totalBytes)) (\(String(format: "%.1f%%", vol.usedPercent)) used) | Read \(ByteFormatter.detailedRate(snap.disk.readBytesPerSec)) | Write \(ByteFormatter.detailedRate(snap.disk.writeBytesPerSec))")
        }
        print("Power/Batt : InternalBattery=\(snap.batteryPower.hasInternalBattery) | Source=\(snap.batteryPower.powerSourceName) | HID Peripherals=\(snap.batteryPower.peripherals.count)")
        if snap.siliconPower.isAvailable {
            print(String(
                format: "IOReport   : Package %.2fW (CPU %.2fW / GPU %.2fW / ANE %.2fW / DRAM %.2fW) | GPU %.1f%%",
                snap.siliconPower.packageWatts,
                snap.siliconPower.cpuWatts,
                snap.siliconPower.gpuWatts,
                snap.siliconPower.aneWatts,
                snap.siliconPower.dramWatts,
                snap.siliconPower.gpuUsagePercent
            ))
        } else {
            print("IOReport   : Unavailable")
        }
        let tempSummary = snap.thermalFan.primaryTemperature.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let fanSummary = snap.thermalFan.fans.map { "Fan#\($0.id): \($0.currentRPM) RPM (\($0.minRPM)-\($0.maxRPM))" }.joined(separator: ", ")
        print("Thermal    : Primary \(tempSummary) | Sensors=\(snap.thermalFan.sensors.count) | Fans: \(fanSummary.isEmpty ? "None" : fanSummary)")
        print("--------------------------------------------------")
        print("Top CPU Apps:")
        for app in snap.topCPUApps {
            print(String(format: "  - %-24@ %6.1f%%  (%d procs, %@)", app.name as NSString, app.cpuPercent, app.pidsCount, ByteFormatter.memorySize(app.memoryBytes)))
        }
        print("Top Memory Apps:")
        for app in snap.topMemoryApps {
            print(String(format: "  - %-24@ %8@  (%d procs, %.1f%% CPU)", app.name as NSString, ByteFormatter.memorySize(app.memoryBytes) as NSString, app.pidsCount, app.cpuPercent))
        }
        print("==================================================")
    }
}
