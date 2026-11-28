import Foundation

// MARK: - CPU

public enum CoreKind: String, Sendable, Equatable {
    case performance
    case efficiency
    case unknown
}

public struct CoreLoad: Sendable, Equatable, Identifiable {
    public let id: Int
    public let kind: CoreKind
    public let usagePercent: Double

    public init(id: Int, kind: CoreKind, usagePercent: Double) {
        self.id = id
        self.kind = kind
        self.usagePercent = usagePercent
    }
}

public struct CPUSnapshot: Sendable, Equatable {
    public var totalUsagePercent: Double
    public var userPercent: Double
    public var systemPercent: Double
    public var pCoreUsagePercent: Double
    public var eCoreUsagePercent: Double
    public var pCoreCount: Int
    public var eCoreCount: Int
    public var totalCoreCount: Int
    public var perCoreLoads: [CoreLoad]
    public var loadAverage1m: Double
    public var loadAverage5m: Double
    public var loadAverage15m: Double

    public static let empty = CPUSnapshot(
        totalUsagePercent: 0,
        userPercent: 0,
        systemPercent: 0,
        pCoreUsagePercent: 0,
        eCoreUsagePercent: 0,
        pCoreCount: 0,
        eCoreCount: 0,
        totalCoreCount: 0,
        perCoreLoads: [],
        loadAverage1m: 0,
        loadAverage5m: 0,
        loadAverage15m: 0
    )

    public init(
        totalUsagePercent: Double,
        userPercent: Double,
        systemPercent: Double,
        pCoreUsagePercent: Double,
        eCoreUsagePercent: Double,
        pCoreCount: Int,
        eCoreCount: Int,
        totalCoreCount: Int,
        perCoreLoads: [CoreLoad],
        loadAverage1m: Double,
        loadAverage5m: Double,
        loadAverage15m: Double
    ) {
        self.totalUsagePercent = totalUsagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.pCoreUsagePercent = pCoreUsagePercent
        self.eCoreUsagePercent = eCoreUsagePercent
        self.pCoreCount = pCoreCount
        self.eCoreCount = eCoreCount
        self.totalCoreCount = totalCoreCount
        self.perCoreLoads = perCoreLoads
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.loadAverage15m = loadAverage15m
    }
}

// MARK: - Memory

public enum MemoryPressureLevel: String, Sendable, Equatable {
    case normal
    case warning
    case critical

    public var displayName: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "偏高"
        case .critical: return "紧张"
        }
    }
}

public struct MemorySnapshot: Sendable, Equatable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedFilesBytes: UInt64
    public var freeBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: MemoryPressureLevel

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100.0)
    }

    public static let empty = MemorySnapshot(
        totalBytes: 0,
        usedBytes: 0,
        appBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedFilesBytes: 0,
        freeBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        pressure: .normal
    )

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        appBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        freeBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        pressure: MemoryPressureLevel
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
    }
}

// MARK: - Network

public struct NetworkSnapshot: Sendable, Equatable {
    public var downloadBytesPerSec: Double
    public var uploadBytesPerSec: Double
    public var sessionDownloadBytes: UInt64
    public var sessionUploadBytes: UInt64
    public var primaryInterface: String
    public var localIPAddress: String
    public var isConnected: Bool

    public static let empty = NetworkSnapshot(
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
        sessionDownloadBytes: 0,
        sessionUploadBytes: 0,
        primaryInterface: "--",
        localIPAddress: "--",
        isConnected: false
    )

    public init(
        downloadBytesPerSec: Double,
        uploadBytesPerSec: Double,
        sessionDownloadBytes: UInt64,
        sessionUploadBytes: UInt64,
        primaryInterface: String,
        localIPAddress: String,
        isConnected: Bool
    ) {
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.sessionDownloadBytes = sessionDownloadBytes
        self.sessionUploadBytes = sessionUploadBytes
        self.primaryInterface = primaryInterface
        self.localIPAddress = localIPAddress
        self.isConnected = isConnected
    }
}

// MARK: - Disk

public struct DiskVolume: Sendable, Equatable, Identifiable {
    public var id: String { mountPath }
    public let name: String
    public let mountPath: String
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let purgeableBytes: UInt64
    public let isInternal: Bool

    public var usedBytes: UInt64 {
        totalBytes >= availableBytes ? totalBytes - availableBytes : 0
    }

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100.0)
    }

    public init(
        name: String,
        mountPath: String,
        totalBytes: UInt64,
        availableBytes: UInt64,
        purgeableBytes: UInt64 = 0,
        isInternal: Bool
    ) {
        self.name = name
        self.mountPath = mountPath
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
        self.isInternal = isInternal
    }
}

public struct NVMeSmartSnapshot: Sendable, Equatable {
    public var isAvailable: Bool
    public var healthPercent: Int
    public var percentageUsed: Int
    public var availableSparePercent: Int
    public var temperatureCelsius: Int?
    public var totalBytesWritten: UInt64
    public var totalBytesRead: UInt64
    public var powerOnHours: UInt64
    public var powerCycles: UInt64

    public init(
        isAvailable: Bool,
        healthPercent: Int,
        percentageUsed: Int,
        availableSparePercent: Int,
        temperatureCelsius: Int?,
        totalBytesWritten: UInt64,
        totalBytesRead: UInt64,
        powerOnHours: UInt64,
        powerCycles: UInt64
    ) {
        self.isAvailable = isAvailable
        self.healthPercent = healthPercent
        self.percentageUsed = percentageUsed
        self.availableSparePercent = availableSparePercent
        self.temperatureCelsius = temperatureCelsius
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesRead = totalBytesRead
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
    }
}

public struct SleepBlocker: Sendable, Equatable, Identifiable {
    public var id: String { "\(pid):\(processName)" }
    public let pid: Int32
    public let processName: String
    public let assertionType: String
    public let preventsDisplaySleep: Bool

    public init(pid: Int32, processName: String, assertionType: String, preventsDisplaySleep: Bool) {
        self.pid = pid
        self.processName = processName
        self.assertionType = assertionType
        self.preventsDisplaySleep = preventsDisplaySleep
    }
}

public struct DiskSnapshot: Sendable, Equatable {
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public var volumes: [DiskVolume]
    public var smart: NVMeSmartSnapshot?

    public var primaryVolume: DiskVolume? { volumes.first }

    public static let empty = DiskSnapshot(
        readBytesPerSec: 0,
        writeBytesPerSec: 0,
        volumes: [],
        smart: nil
    )

    public init(
        readBytesPerSec: Double,
        writeBytesPerSec: Double,
        volumes: [DiskVolume],
        smart: NVMeSmartSnapshot? = nil
    ) {
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.volumes = volumes
        self.smart = smart
    }
}

// MARK: - Power & Battery

public struct HIDPeripheralBattery: Sendable, Equatable, Identifiable {
    public var id: String { "\(name)-\(percent)" }
    public let name: String
    public let percent: Int

    public init(name: String, percent: Int) {
        self.name = name
        self.percent = percent
    }
}

public enum PowerSourceKind: String, Codable, Sendable, Equatable {
    case acPower
    case powerAdapter
    case internalBattery
}

public struct BatteryPowerSnapshot: Sendable, Equatable {
    public var hasInternalBattery: Bool
    public var chargePercent: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var powerWatts: Double // 正为充电，负为放电
    public var healthPercent: Double
    public var cycleCount: Int
    public var temperatureCelsius: Double?
    public var timeRemainingMinutes: Int?
    public var adapterWatts: Int?
    public var powerSource: PowerSourceKind
    public var peripherals: [HIDPeripheralBattery]

    public static let empty = BatteryPowerSnapshot(
        hasInternalBattery: false,
        chargePercent: 0,
        isCharging: false,
        isPluggedIn: true,
        powerWatts: 0,
        healthPercent: 100,
        cycleCount: 0,
        temperatureCelsius: nil,
        timeRemainingMinutes: nil,
        adapterWatts: nil,
        powerSource: .acPower,
        peripherals: []
    )

    /// 供无电池台式机用户在设置中预览完整的笔记本电池 UI 形态
    public static func previewLaptopSample(peripherals: [HIDPeripheralBattery] = []) -> BatteryPowerSnapshot {
        BatteryPowerSnapshot(
            hasInternalBattery: true,
            chargePercent: 84,
            isCharging: true,
            isPluggedIn: true,
            powerWatts: 42.6,
            healthPercent: 97.4,
            cycleCount: 48,
            temperatureCelsius: 31.4,
            timeRemainingMinutes: 28,
            adapterWatts: 70,
            powerSource: .powerAdapter,
            peripherals: peripherals.isEmpty ? [
                HIDPeripheralBattery(name: "Magic Mouse", percent: 86),
                HIDPeripheralBattery(name: "Magic Keyboard", percent: 92)
            ] : peripherals
        )
    }

    public init(
        hasInternalBattery: Bool,
        chargePercent: Double,
        isCharging: Bool,
        isPluggedIn: Bool,
        powerWatts: Double,
        healthPercent: Double,
        cycleCount: Int,
        temperatureCelsius: Double?,
        timeRemainingMinutes: Int?,
        adapterWatts: Int?,
        powerSource: PowerSourceKind,
        peripherals: [HIDPeripheralBattery]
    ) {
        self.hasInternalBattery = hasInternalBattery
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.powerWatts = powerWatts
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.timeRemainingMinutes = timeRemainingMinutes
        self.adapterWatts = adapterWatts
        self.powerSource = powerSource
        self.peripherals = peripherals
    }
}

// MARK: - Apple Silicon Power & GPU

public struct AppleSiliconPowerSnapshot: Sendable, Equatable {
    public var isAvailable: Bool
    public var isWarmingUp: Bool
    public var packageWatts: Double
    public var cpuWatts: Double
    public var gpuWatts: Double
    public var aneWatts: Double
    public var dramWatts: Double
    public var gpuUsagePercent: Double

    public static let empty = AppleSiliconPowerSnapshot(
        isAvailable: false,
        isWarmingUp: false,
        packageWatts: 0,
        cpuWatts: 0,
        gpuWatts: 0,
        aneWatts: 0,
        dramWatts: 0,
        gpuUsagePercent: 0
    )

    public init(
        isAvailable: Bool,
        isWarmingUp: Bool = false,
        packageWatts: Double,
        cpuWatts: Double,
        gpuWatts: Double,
        aneWatts: Double,
        dramWatts: Double,
        gpuUsagePercent: Double
    ) {
        self.isAvailable = isAvailable
        self.isWarmingUp = isWarmingUp
        self.packageWatts = packageWatts
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
        self.dramWatts = dramWatts
        self.gpuUsagePercent = gpuUsagePercent
    }
}

// MARK: - Thermal & Fans (Read-Only)

public struct ThermalSensorReading: Sendable, Equatable, Identifiable {
    public var id: String { "\(source):\(name)" }
    public let name: String
    public let celsius: Double
    public let source: String

    public init(name: String, celsius: Double, source: String) {
        self.name = name
        self.celsius = celsius
        self.source = source
    }
}

public struct FanReading: Sendable, Equatable, Identifiable {
    public let id: Int
    public let currentRPM: Int
    public let minRPM: Int
    public let maxRPM: Int

    public var speedPercent: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(100, max(0, Double(currentRPM - minRPM) / Double(maxRPM - minRPM) * 100.0))
    }

    public init(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int) {
        self.id = id
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public struct ThermalFanSnapshot: Sendable, Equatable {
    public var socTemperature: Double?
    public var cpuTemperature: Double?
    public var gpuTemperature: Double?
    public var ssdTemperature: Double?
    public var sensors: [ThermalSensorReading]
    public var fans: [FanReading]

    public var primaryTemperature: Double? {
        socTemperature ?? cpuTemperature ?? gpuTemperature ?? sensors.map(\.celsius).max()
    }

    public static let empty = ThermalFanSnapshot(
        socTemperature: nil,
        cpuTemperature: nil,
        gpuTemperature: nil,
        ssdTemperature: nil,
        sensors: [],
        fans: []
    )

    public init(
        socTemperature: Double?,
        cpuTemperature: Double?,
        gpuTemperature: Double?,
        ssdTemperature: Double?,
        sensors: [ThermalSensorReading],
        fans: [FanReading]
    ) {
        self.socTemperature = socTemperature
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.ssdTemperature = ssdTemperature
        self.sensors = sensors
        self.fans = fans
    }
}

// MARK: - Aggregated Apps (Read-Only)

public struct AggregatedAppUsage: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let appBundlePath: String?
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let pidsCount: Int

    public init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        appBundlePath: String?,
        cpuPercent: Double,
        memoryBytes: UInt64,
        pidsCount: Int
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.appBundlePath = appBundlePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.pidsCount = pidsCount
    }
}

// MARK: - Host Info & Health

public struct HostStaticInfo: Sendable, Equatable {
    public let chipName: String
    public let modelIdentifier: String
    public let osVersionString: String
    public let totalMemoryBytes: UInt64
    public let pCoreCount: Int
    public let eCoreCount: Int
    public let totalCoreCount: Int

    public init(
        chipName: String,
        modelIdentifier: String,
        osVersionString: String,
        totalMemoryBytes: UInt64,
        pCoreCount: Int,
        eCoreCount: Int,
        totalCoreCount: Int
    ) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.osVersionString = osVersionString
        self.totalMemoryBytes = totalMemoryBytes
        self.pCoreCount = pCoreCount
        self.eCoreCount = eCoreCount
        self.totalCoreCount = totalCoreCount
    }
}

public enum HealthLevel: String, Sendable, Equatable {
    case calm
    case moderate
    case elevated
}

public struct HealthSummary: Sendable, Equatable {
    public let level: HealthLevel
    public let message: String

    public static let initial = HealthSummary(level: .calm, message: "正在读取系统晴雨…")

    public init(level: HealthLevel, message: String) {
        self.level = level
        self.message = message
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public var timestamp: Date
    public var uptimeSeconds: TimeInterval
    public var cpu: CPUSnapshot
    public var memory: MemorySnapshot
    public var network: NetworkSnapshot
    public var disk: DiskSnapshot
    public var batteryPower: BatteryPowerSnapshot
    public var siliconPower: AppleSiliconPowerSnapshot
    public var thermalFan: ThermalFanSnapshot
    public var sleepBlockers: [SleepBlocker]
    public var topCPUApps: [AggregatedAppUsage]
    public var topMemoryApps: [AggregatedAppUsage]

    public static let empty = SystemSnapshot(
        timestamp: Date(),
        uptimeSeconds: 0,
        cpu: .empty,
        memory: .empty,
        network: .empty,
        disk: .empty,
        batteryPower: .empty,
        siliconPower: .empty,
        thermalFan: .empty,
        sleepBlockers: [],
        topCPUApps: [],
        topMemoryApps: []
    )

    public init(
        timestamp: Date,
        uptimeSeconds: TimeInterval,
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        network: NetworkSnapshot,
        disk: DiskSnapshot,
        batteryPower: BatteryPowerSnapshot,
        siliconPower: AppleSiliconPowerSnapshot,
        thermalFan: ThermalFanSnapshot,
        sleepBlockers: [SleepBlocker] = [],
        topCPUApps: [AggregatedAppUsage],
        topMemoryApps: [AggregatedAppUsage]
    ) {
        self.timestamp = timestamp
        self.uptimeSeconds = uptimeSeconds
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.disk = disk
        self.batteryPower = batteryPower
        self.siliconPower = siliconPower
        self.thermalFan = thermalFan
        self.sleepBlockers = sleepBlockers
        self.topCPUApps = topCPUApps
        self.topMemoryApps = topMemoryApps
    }
}
