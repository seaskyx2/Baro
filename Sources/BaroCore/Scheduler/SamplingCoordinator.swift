import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

public struct MenuBarRenderData: Sendable, Equatable {
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var memoryPressure: MemoryPressureLevel
    public var uploadBytesPerSec: Double
    public var downloadBytesPerSec: Double
    public var temperatureCelsius: Double?
    public var packageWatts: Double
    public var isPowerAvailable: Bool
    public var healthLevel: HealthLevel
    public var topCPUAppPath: String?
    public var cpuSparklinePoints: [Double]

    public static let empty = MenuBarRenderData(
        cpuPercent: 0,
        memoryPercent: 0,
        memoryPressure: .normal,
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
        needNetwork: Bool,
        needThermal: Bool,
        needPower: Bool
    ) -> SystemSnapshot {
        var next = previous
        next.timestamp = Date()
        next.uptimeSeconds = HostInfoReader.uptimeSeconds()

        if needCPU {
            next.cpu = cpu.sample()
        }
        if needMemory {
            next.memory = memory.sample()
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

@MainActor
public final class SamplingCoordinator: ObservableObject {
    public let hostInfo: HostStaticInfo
    public let settings: BaroSettings

    @Published public private(set) var snapshot: SystemSnapshot = .empty
    @Published public private(set) var healthSummary: HealthSummary = .initial
    @Published public private(set) var isPanelOpen: Bool = false
    @Published public private(set) var isSleeping: Bool = false

    @Published public private(set) var cpuHistory: [Double] = []
    @Published public private(set) var memoryHistory: [Double] = []
    @Published public private(set) var downloadHistory: [Double] = []
    @Published public private(set) var uploadHistory: [Double] = []
    @Published public private(set) var powerHistory: [Double] = []
    @Published public private(set) var temperatureHistory: [Double] = []

    /// 供纯 AppKit 菜单栏视图使用：冷态时直接走轻回调，避免触发 SwiftUI ObservableObject 广播
    public var onMenuBarUpdate: ((MenuBarRenderData) -> Void)?

    private var latestSnapshot: SystemSnapshot = .empty
    private var latestHealthSummary: HealthSummary = .initial

    private var cpuBuffer = RingBuffer<Double>(capacity: 60)
    private var memoryBuffer = RingBuffer<Double>(capacity: 60)
    private var downloadBuffer = RingBuffer<Double>(capacity: 60)
    private var uploadBuffer = RingBuffer<Double>(capacity: 60)
    private var powerBuffer = RingBuffer<Double>(capacity: 60)
    private var temperatureBuffer = RingBuffer<Double>(capacity: 60)

    private let engine = CollectorEngine()
    private var timer: Timer?
    private var isSamplingInFlight = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var settingsCancellables = Set<AnyCancellable>()
    private var lastAlertDates: [String: Date] = [:]

    public init(settings: BaroSettings = BaroSettings()) {
        self.settings = settings
        self.hostInfo = HostInfoReader.readStaticInfo()
        self.latestHealthSummary = HealthSummary(
            level: .calm,
            message: BaroL10n.t("正在读取系统晴雨…", "Reading system vitals…", lang: settings.resolvedLanguage)
        )
        self.healthSummary = self.latestHealthSummary
        registerSleepNotifications()
        observeSettingsChanges()
    }

    public func start() {
        scheduleNextCycle(immediate: true)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func currentMenuBarRenderData() -> MenuBarRenderData {
        makeMenuBarRenderData(from: latestSnapshot, health: latestHealthSummary)
    }

    public func setPanelOpen(_ open: Bool) {
        guard isPanelOpen != open else { return }
        isPanelOpen = open
        if open {
            snapshot = latestSnapshot
            healthSummary = latestHealthSummary
            syncHistoryBuffersToPublished()
        } else {
            engine.resetHotProcessThrottle()
        }
        scheduleNextCycle(immediate: true)
    }

    private func syncHistoryBuffersToPublished() {
        cpuHistory = cpuBuffer.values
        memoryHistory = memoryBuffer.values
        downloadHistory = downloadBuffer.values
        uploadHistory = uploadBuffer.values
        powerHistory = powerBuffer.values
        temperatureHistory = temperatureBuffer.values
    }

    private func observeSettingsChanges() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.latestHealthSummary = HealthAnalyzer.analyze(
                    snapshot: self.latestSnapshot,
                    topCPUApp: self.latestSnapshot.topCPUApps.first,
                    topMemoryApp: self.latestSnapshot.topMemoryApps.first,
                    language: self.settings.resolvedLanguage
                )
                if self.isPanelOpen {
                    self.healthSummary = self.latestHealthSummary
                }
                self.onMenuBarUpdate?(self.currentMenuBarRenderData())
                self.scheduleNextCycle(immediate: false)
            }
            .store(in: &settingsCancellables)
    }

    private func registerSleepNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let sleepNames: [NSNotification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification
        ]
        let wakeNames: [NSNotification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification
        ]

        for name in sleepNames {
            let obs = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleSleep()
                }
            }
            workspaceObservers.append(obs)
        }

        for name in wakeNames {
            let obs = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWake()
                }
            }
            workspaceObservers.append(obs)
        }
    }

    private func handleSleep() {
        isSleeping = true
        timer?.invalidate()
        timer = nil
    }

    private func handleWake() {
        isSleeping = false
        engine.resetAllBaselines()
        scheduleNextCycle(immediate: true)
    }

    private func currentInterval() -> TimeInterval {
        let base = isPanelOpen ? settings.hotInterval : settings.coldInterval
        if settings.adaptToLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled {
            return max(base * 2.0, 3.0)
        }
        return max(0.8, base)
    }

    private func scheduleNextCycle(immediate: Bool) {
        timer?.invalidate()
        timer = nil
        guard !isSleeping else { return }

        if immediate {
            triggerSample()
        }

        let interval = currentInterval()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.triggerSample()
            }
        }
        newTimer.tolerance = interval * 0.25
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func triggerSample() {
        guard !isSleeping, !isSamplingInFlight else { return }
        isSamplingInFlight = true

        let hot = isPanelOpen
        let prev = latestSnapshot
        let style = settings.menuBarStyle
        let needCPU = hot || settings.showMenuCPU || style == .sparkline || style == .miniBars || style == .breathingDot
        let needMemory = hot || settings.showMenuMemory || style == .sparkline || style == .miniBars
        let needNetwork = hot || settings.showMenuNetwork
        let needThermal = hot || settings.showMenuTemperature
        let needPower = hot || settings.showMenuPower

        let includeDisk = hot && settings.showDiskCard
        let includeBattery = hot && settings.showBatteryPowerCard
        let includeProcs = hot && (settings.showTopAppsSection || settings.menuBarStyle == .breathingDot)
        let capturedEngine = engine

        Task.detached(priority: .utility) {
            let nextSnapshot: SystemSnapshot
            if hot {
                nextSnapshot = capturedEngine.sampleHot(
                    includeCPU: true,
                    includeMemory: true,
                    includeNetwork: true,
                    includeDisk: includeDisk,
                    includeBattery: includeBattery,
                    includeSiliconPower: true,
                    includeThermal: true,
                    includeProcesses: includeProcs
                )
            } else {
                nextSnapshot = capturedEngine.sampleCold(
                    previous: prev,
                    needCPU: needCPU,
                    needMemory: needMemory,
                    needNetwork: needNetwork,
                    needThermal: needThermal,
                    needPower: needPower
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applySnapshot(nextSnapshot, isHot: hot)
                self.isSamplingInFlight = false
            }
        }
    }

    private func applySnapshot(_ next: SystemSnapshot, isHot: Bool) {
        latestSnapshot = next

        cpuBuffer.append(next.cpu.totalUsagePercent)
        memoryBuffer.append(next.memory.usedPercent)
        downloadBuffer.append(next.network.downloadBytesPerSec)
        uploadBuffer.append(next.network.uploadBytesPerSec)

        if next.siliconPower.isAvailable {
            powerBuffer.append(next.siliconPower.packageWatts)
        }
        if let temp = next.thermalFan.primaryTemperature {
            temperatureBuffer.append(temp)
        }

        let summary = HealthAnalyzer.analyze(
            snapshot: next,
            topCPUApp: next.topCPUApps.first,
            topMemoryApp: next.topMemoryApps.first,
            language: settings.resolvedLanguage
        )
        latestHealthSummary = summary

        if isHot {
            snapshot = next
            healthSummary = summary
            syncHistoryBuffersToPublished()
        }

        onMenuBarUpdate?(makeMenuBarRenderData(from: next, health: summary))

        if isHot || settings.enableThermalAlert || settings.enableMemoryAlert || settings.enableLowBatteryAlert {
            evaluateAlertsIfEnabled(next)
        }
    }

    private func makeMenuBarRenderData(from snap: SystemSnapshot, health: HealthSummary) -> MenuBarRenderData {
        MenuBarRenderData(
            cpuPercent: snap.cpu.totalUsagePercent,
            memoryPercent: snap.memory.usedPercent,
            memoryPressure: snap.memory.pressure,
            uploadBytesPerSec: snap.network.uploadBytesPerSec,
            downloadBytesPerSec: snap.network.downloadBytesPerSec,
            temperatureCelsius: snap.thermalFan.primaryTemperature,
            packageWatts: snap.siliconPower.packageWatts,
            isPowerAvailable: snap.siliconPower.isAvailable,
            healthLevel: health.level,
            topCPUAppPath: snap.topCPUApps.first?.appBundlePath,
            cpuSparklinePoints: Array(cpuBuffer.values.suffix(16))
        )
    }

    private func evaluateAlertsIfEnabled(_ snap: SystemSnapshot) {
        let lang = settings.resolvedLanguage

        if settings.enableThermalAlert,
           let temp = snap.thermalFan.primaryTemperature,
           temp >= settings.thermalAlertThreshold {
            let deg = Int(temp.rounded())
            sendNotificationIfNeeded(
                key: "thermal",
                title: BaroL10n.t("Baro 温度提醒", "Baro Thermal Alert", lang: lang),
                body: BaroL10n.t(
                    "芯片当前温度达到 \(deg)°C，请注意散热通风。",
                    "SoC temperature reached \(deg)°C.",
                    lang: lang
                )
            )
        }

        if settings.enableMemoryAlert, snap.memory.pressure == .critical {
            let pct = Int(snap.memory.usedPercent.rounded())
            sendNotificationIfNeeded(
                key: "memory",
                title: BaroL10n.t("Baro 内存压力提醒", "Baro Memory Alert", lang: lang),
                body: BaroL10n.t(
                    "统一内存压力处于紧张状态，已用 \(pct)%。",
                    "Memory pressure is critical (\(pct)% used).",
                    lang: lang
                )
            )
        }

        if settings.enableLowBatteryAlert,
           snap.batteryPower.hasInternalBattery,
           !snap.batteryPower.isPluggedIn,
           snap.batteryPower.chargePercent <= 15.0 {
            let pct = Int(snap.batteryPower.chargePercent.rounded())
            sendNotificationIfNeeded(
                key: "battery",
                title: BaroL10n.t("Baro 低电量提醒", "Baro Low Battery", lang: lang),
                body: BaroL10n.t(
                    "内置电池剩余电量 \(pct)%。",
                    "Internal battery remaining: \(pct)%.",
                    lang: lang
                )
            )
        }
    }

    private func sendNotificationIfNeeded(key: String, title: String, body: String) {
        let now = Date()
        if let last = lastAlertDates[key], now.timeIntervalSince(last) < 600 {
            return
        }
        lastAlertDates[key] = now

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "baro.alert.\(key).\(Int(now.timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    public static func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
