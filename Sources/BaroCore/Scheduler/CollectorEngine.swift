import Foundation

public struct MenuBarRenderData: Sendable, Equatable {
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var memoryPressure: MemoryPressureLevel
    public var diskFreeBytes: UInt64?
    public var diskUsedPercent: Double?
    public var uploadBytesPerSec: Double
    public var downloadBytesPerSec: Double
    public var temperatureCelsius: Double?
    public var packageWatts: Double
    public var isPowerAvailable: Bool
    public var healthLevel: HealthLevel
    public var topCPUAppPath: String?
    public var cpuSparklinePoints: [Double]

    public init(
        cpuPercent: Double,
        memoryPercent: Double,
        memoryPressure: MemoryPressureLevel,
        diskFreeBytes: UInt64? = nil,
        diskUsedPercent: Double? = nil,
        uploadBytesPerSec: Double,
        downloadBytesPerSec: Double,
        temperatureCelsius: Double?,
        packageWatts: Double,
        isPowerAvailable: Bool,
        healthLevel: HealthLevel,
        topCPUAppPath: String?,
        cpuSparklinePoints: [Double]
    ) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryPressure = memoryPressure
        self.diskFreeBytes = diskFreeBytes
        self.diskUsedPercent = diskUsedPercent
        self.uploadBytesPerSec = uploadBytesPerSec
        self.downloadBytesPerSec = downloadBytesPerSec
        self.temperatureCelsius = temperatureCelsius
        self.packageWatts = packageWatts
        self.isPowerAvailable = isPowerAvailable
        self.healthLevel = healthLevel
        self.topCPUAppPath = topCPUAppPath
        self.cpuSparklinePoints = cpuSparklinePoints
    }

    public static let empty = MenuBarRenderData(
        cpuPercent: 0,
        memoryPercent: 0,
        memoryPressure: .normal,
        diskFreeBytes: nil,
        diskUsedPercent: nil,
        uploadBytesPerSec: 0,
        downloadBytesPerSec: 0,
        temperatureCelsius: nil,
        packageWatts: 0,
        isPowerAvailable: false,
        healthLevel: .calm,
        topCPUAppPath: nil,
        cpuSparklinePoints: []
    )
}

/// 纯 Foundation 硬件采集引擎（零 AppKit / 零通知框架依赖，可在 CLI、测试或扩展中无头运行）
public final class CollectorEngine: @unchecked Sendable {
    public let cpu = CPUCollector()
    public let memory = MemoryCollector()
    public let network = NetworkCollector()
    public let disk = DiskCollector()
    public let batteryPower = BatteryPowerCollector()
    public let siliconPower = AppleSiliconPowerCollector()
    public let thermalFan = ThermalFanCollector()
    public let sleepAssertion = SleepAssertionCollector()
    public let processAggregator = ProcessAggregatorCollector()

    private let throttleLock = NSLock()
    private var lastDiskSampleAt: Date?
    private var cachedDiskSnapshot: DiskSnapshot = .empty
    private var lastColdVolumeSampleAt: Date?
    private var cachedColdVolumeSnapshot: DiskSnapshot = .empty
    private var lastBatterySampleAt: Date?
    private var cachedBatterySnapshot: BatteryPowerSnapshot = .empty
    private var lastSleepSampleAt: Date?
    private var cachedSleepBlockers: [SleepBlocker] = []
    private var lastProcessSampleAt: Date?
    private var cachedTopCPU: [AggregatedAppUsage] = []
    private var cachedTopMemory: [AggregatedAppUsage] = []
    private var processSampleCountInHot = 0

    public init() {}

    public func resetAllBaselines() {
        cpu.resetBaseline()
        network.resetBaseline()
        disk.resetBaseline()
        siliconPower.resetBaseline()
        processAggregator.resetBaseline()

        throttleLock.lock()
        lastDiskSampleAt = nil
        lastColdVolumeSampleAt = nil
        lastBatterySampleAt = nil
        lastSleepSampleAt = nil
        lastProcessSampleAt = nil
        processSampleCountInHot = 0
        throttleLock.unlock()
    }

    public func resetHotProcessThrottle() {
        processAggregator.resetBaseline()
        throttleLock.lock()
        lastProcessSampleAt = nil
        processSampleCountInHot = 0
        throttleLock.unlock()
    }

    public func sampleCold(
        previous: SystemSnapshot,
        needCPU: Bool,
        needMemory: Bool,
        needDisk: Bool = false,
        needNetwork: Bool,
        needThermal: Bool,
        needPower: Bool,
        includeProcesses: Bool = false
    ) -> SystemSnapshot {
        var next = previous
        next.timestamp = Date()
        next.uptimeSeconds = HostInfoReader.uptimeSeconds()

        // 冷态默认不沿用上一次热态的进程排行，避免菜单栏/健康摘要点名过期 App
        if includeProcesses {
            let procs = cachedOrFreshProcesses(minInterval: 3.0)
            next.topCPUApps = procs.topCPU
            next.topMemoryApps = procs.topMemory
        } else {
            next.topCPUApps = []
            next.topMemoryApps = []
        }

        if needCPU {
            next.cpu = cpu.sample()
        }
        if needMemory {
            next.memory = memory.sample()
        }
        if needDisk {
            next.disk = cachedOrFreshColdVolumes(minInterval: 20.0)
        }
        if needNetwork {
            next.network = network.sample()
        }
        if needThermal {
            next.thermalFan = thermalFan.sample()
        }
        if needPower {
            var powerSnap = siliconPower.sample()
            if powerSnap.cpuWatts == 0 && powerSnap.aneWatts == 0 && powerSnap.dramWatts == 0 {
                if let smcWatts = thermalFan.readSystemPowerWatts() {
                    powerSnap.packageWatts = smcWatts
                } else {
                    let batSnap = cachedOrFreshBattery(minInterval: 10.0)
                    if !batSnap.hasInternalBattery && batSnap.powerWatts > 0 {
                        powerSnap.packageWatts = batSnap.powerWatts
                    }
                }
                powerSnap.isAvailable = powerSnap.isAvailable || powerSnap.packageWatts > 0
            }
            next.siliconPower = powerSnap
        }
        return next
    }

    public func sampleHot(
        includeCPU: Bool = true,
        includeMemory: Bool = true,
        includeNetwork: Bool = true,
        includeDisk: Bool = true,
        includeBattery: Bool = true,
        includeSiliconPower: Bool = true,
        includeThermal: Bool = true,
        includeProcesses: Bool = true,
        bypassThrottle: Bool = false
    ) -> SystemSnapshot {
        let cpuSnap = includeCPU ? cpu.sample() : .empty
        let memSnap = includeMemory ? memory.sample() : .empty
        let netSnap = includeNetwork ? network.sample() : .empty
        let diskSnap = includeDisk ? (bypassThrottle ? disk.sample() : cachedOrFreshDisk(minInterval: 4.0)) : .empty
        let batSnap = includeBattery ? (bypassThrottle ? batteryPower.sample() : cachedOrFreshBattery(minInterval: 8.0)) : .empty
        var powerSnap = includeSiliconPower ? siliconPower.sample() : .empty
        let thermalSnap = includeThermal ? thermalFan.sample() : .empty
        let sleepBlockers = bypassThrottle ? sleepAssertion.sample() : cachedOrFreshSleepBlockers(minInterval: 6.0)
        let procs = includeProcesses
            ? (bypassThrottle ? processAggregator.sample(limit: 5) : cachedOrFreshProcesses(minInterval: 3.0))
            : (topCPU: [], topMemory: [])

        if includeSiliconPower && powerSnap.cpuWatts == 0 && powerSnap.aneWatts == 0 && powerSnap.dramWatts == 0 {
            if let smcWatts = thermalFan.readSystemPowerWatts() {
                powerSnap.packageWatts = smcWatts
            } else if !batSnap.hasInternalBattery && batSnap.powerWatts > 0 {
                powerSnap.packageWatts = batSnap.powerWatts
            }
            powerSnap.isAvailable = powerSnap.isAvailable || powerSnap.packageWatts > 0
        }

        return SystemSnapshot(
            timestamp: Date(),
            uptimeSeconds: HostInfoReader.uptimeSeconds(),
            cpu: cpuSnap,
            memory: memSnap,
            network: netSnap,
            disk: diskSnap,
            batteryPower: batSnap,
            siliconPower: powerSnap,
            thermalFan: thermalSnap,
            sleepBlockers: sleepBlockers,
            topCPUApps: procs.topCPU,
            topMemoryApps: procs.topMemory
        )
    }

    private func cachedOrFreshDisk(minInterval: TimeInterval) -> DiskSnapshot {
        let now = Date()
        throttleLock.lock()
        let last = lastDiskSampleAt
        let cached = cachedDiskSnapshot
        throttleLock.unlock()

        if let last, now.timeIntervalSince(last) < minInterval {
            return cached
        }
        let fresh = disk.sample()
        throttleLock.lock()
        lastDiskSampleAt = now
        cachedDiskSnapshot = fresh
        cachedColdVolumeSnapshot = fresh
        lastColdVolumeSampleAt = now
        throttleLock.unlock()
        return fresh
    }

    private func cachedOrFreshColdVolumes(minInterval: TimeInterval) -> DiskSnapshot {
        let now = Date()
        throttleLock.lock()
        let last = lastColdVolumeSampleAt
        let cached = cachedColdVolumeSnapshot
        throttleLock.unlock()

        if let last, now.timeIntervalSince(last) < minInterval, !cached.volumes.isEmpty {
            return cached
        }
        let fresh = disk.sampleVolumesOnly()
        throttleLock.lock()
        lastColdVolumeSampleAt = now
        cachedColdVolumeSnapshot = fresh
        throttleLock.unlock()
        return fresh
    }

    private func cachedOrFreshBattery(minInterval: TimeInterval) -> BatteryPowerSnapshot {
        let now = Date()
        throttleLock.lock()
        let last = lastBatterySampleAt
        let cached = cachedBatterySnapshot
        throttleLock.unlock()

        if let last, now.timeIntervalSince(last) < minInterval {
            return cached
        }
        let fresh = batteryPower.sample()
        throttleLock.lock()
        lastBatterySampleAt = now
        cachedBatterySnapshot = fresh
        throttleLock.unlock()
        return fresh
    }

    private func cachedOrFreshSleepBlockers(minInterval: TimeInterval) -> [SleepBlocker] {
        let now = Date()
        throttleLock.lock()
        let last = lastSleepSampleAt
        let cached = cachedSleepBlockers
        throttleLock.unlock()

        if let last, now.timeIntervalSince(last) < minInterval {
            return cached
        }
        let fresh = sleepAssertion.sample()
        throttleLock.lock()
        lastSleepSampleAt = now
        cachedSleepBlockers = fresh
        throttleLock.unlock()
        return fresh
    }

    private func cachedOrFreshProcesses(minInterval: TimeInterval) -> (topCPU: [AggregatedAppUsage], topMemory: [AggregatedAppUsage]) {
        let now = Date()
        throttleLock.lock()
        let last = lastProcessSampleAt
        let countInHot = processSampleCountInHot
        let cached = (cachedTopCPU, cachedTopMemory)
        throttleLock.unlock()

        // 前两轮（建立基准 + 首次出 CPU 差分）立即采样，后续按 minInterval 节流降低扫描开销
        if countInHot >= 2, let last, now.timeIntervalSince(last) < minInterval {
            return cached
        }

        let fresh = processAggregator.sample(limit: 5)
        throttleLock.lock()
        lastProcessSampleAt = now
        cachedTopCPU = fresh.topCPU
        cachedTopMemory = fresh.topMemory
        processSampleCountInHot = countInHot + 1
        throttleLock.unlock()
        return fresh
    }
}
