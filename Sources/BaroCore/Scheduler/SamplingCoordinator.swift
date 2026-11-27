import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

public struct CollectorEngine: Sendable {
    public let cpu = CPUCollector()
    public let memory = MemoryCollector()
    public let network = NetworkCollector()
    public let disk = DiskCollector()
    public let batteryPower = BatteryPowerCollector()
    public let siliconPower = AppleSiliconPowerCollector()
    public let thermalFan = ThermalFanCollector()
    public let processAggregator = ProcessAggregatorCollector()

    public init() {}

    public func resetAllBaselines() {
        cpu.resetBaseline()
        network.resetBaseline()
        disk.resetBaseline()
        siliconPower.resetBaseline()
        processAggregator.resetBaseline()
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
                    let batSnap = batteryPower.sample()
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
        includeProcesses: Bool = true
    ) -> SystemSnapshot {
        let cpuSnap = includeCPU ? cpu.sample() : .empty
        let memSnap = includeMemory ? memory.sample() : .empty
        let netSnap = includeNetwork ? network.sample() : .empty
        let diskSnap = includeDisk ? disk.sample() : .empty
        let batSnap = includeBattery ? batteryPower.sample() : .empty
        var powerSnap = includeSiliconPower ? siliconPower.sample() : .empty
        let thermalSnap = includeThermal ? thermalFan.sample() : .empty
        let procs = includeProcesses ? processAggregator.sample(limit: 5) : (topCPU: [], topMemory: [])

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
            topCPUApps: procs.topCPU,
            topMemoryApps: procs.topMemory
        )
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

    public func setPanelOpen(_ open: Bool) {
        guard isPanelOpen != open else { return }
        isPanelOpen = open
        if open {
            syncHistoryBuffersToPublished()
        } else {
            // 退出热态时重置进程基线，避免下次打开间隔过长出现跨小时残留基准
            engine.processAggregator.resetBaseline()
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
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleNextCycle(immediate: false)
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
        // 允许系统合并唤醒，极致省电
        newTimer.tolerance = interval * 0.25
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func triggerSample() {
        guard !isSleeping, !isSamplingInFlight else { return }
        isSamplingInFlight = true

        let hot = isPanelOpen
        let prev = snapshot
        let needCPU = hot || settings.showMenuCPU || settings.menuBarStyle != .compactDualRow
        let needMemory = hot || settings.showMenuMemory || settings.menuBarStyle == .sparkline
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
        snapshot = next

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

        if isHot {
            syncHistoryBuffersToPublished()
        } else if settings.menuBarStyle == .sparkline {
            cpuHistory = cpuBuffer.values
        }

        healthSummary = HealthAnalyzer.analyze(
            snapshot: next,
            topCPUApp: next.topCPUApps.first,
            topMemoryApp: next.topMemoryApps.first
        )

        if isHot || settings.enableThermalAlert || settings.enableMemoryAlert || settings.enableLowBatteryAlert {
            evaluateAlertsIfEnabled(next)
        }
    }

    private func evaluateAlertsIfEnabled(_ snap: SystemSnapshot) {
        if settings.enableThermalAlert,
           let temp = snap.thermalFan.primaryTemperature,
           temp >= settings.thermalAlertThreshold {
            sendNotificationIfNeeded(
                key: "thermal",
                title: "Baro 温度提醒",
                body: "芯片当前温度达到 \(Int(temp.rounded()))°C，请注意散热通风。"
            )
        }

        if settings.enableMemoryAlert, snap.memory.pressure == .critical {
            sendNotificationIfNeeded(
                key: "memory",
                title: "Baro 内存压力提醒",
                body: "统一内存压力处于紧张状态，已用 \(Int(snap.memory.usedPercent.rounded()))%。"
            )
        }

        if settings.enableLowBatteryAlert,
           snap.batteryPower.hasInternalBattery,
           !snap.batteryPower.isPluggedIn,
           snap.batteryPower.chargePercent <= 15.0 {
            sendNotificationIfNeeded(
                key: "battery",
                title: "Baro 低电量提醒",
                body: "内置电池剩余电量 \(Int(snap.batteryPower.chargePercent.rounded()))%。"
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
