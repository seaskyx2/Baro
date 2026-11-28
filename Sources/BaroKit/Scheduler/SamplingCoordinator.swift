import AppKit
import BaroCore
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
public final class SamplingCoordinator: ObservableObject {
    private struct SampledMask: Sendable {
        let cpu: Bool
        let memory: Bool
        let network: Bool
        let power: Bool
        let thermal: Bool
    }

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
    private var coldProcessSamplingActive = false
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []
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

    deinit {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
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
        coldProcessSamplingActive = false
        if open {
            snapshot = latestSnapshot
            healthSummary = latestHealthSummary
            syncHistoryBuffersToPublished()
        } else {
            engine.resetHotProcessThrottle()
        }
        scheduleNextCycle(immediate: true)
    }

    /// 生成一份可导出的完整快照：面板展开时直接复用热态数据；
    /// 面板收起时在现有引擎上间隔 1 秒连续采样两次，确保 CPU / 网速 / 进程等差分指标有效。
    public func captureFreshSnapshot(
        completion: @escaping @MainActor @Sendable (SystemSnapshot, HealthSummary) -> Void
    ) {
        if isPanelOpen {
            completion(snapshot, healthSummary)
            return
        }
        let capturedEngine = engine
        let lang = settings.resolvedLanguage
        Task.detached(priority: .userInitiated) {
            _ = capturedEngine.sampleHot(bypassThrottle: true)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let snap = capturedEngine.sampleHot(bypassThrottle: true)
            let health = HealthAnalyzer.analyze(
                snapshot: snap,
                topCPUApp: snap.topCPUApps.first,
                topMemoryApp: snap.topMemoryApps.first,
                language: lang
            )
            await MainActor.run {
                completion(snap, health)
            }
        }
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
        let style = settings.menuBarStyle

        let menuNeedCPU = settings.showMenuCPU || style == .sparkline || style == .miniBars || style == .breathingDot
        let menuNeedMem = settings.showMenuMemory || style == .sparkline || style == .miniBars

        let sampleCPU = hot ? (settings.showCPUCard || menuNeedCPU) : menuNeedCPU
        let sampleMemory = hot
            ? (settings.showMemoryCard || menuNeedMem || settings.enableMemoryAlert)
            : (menuNeedMem || settings.enableMemoryAlert)
        let sampleDisk = hot
            ? (settings.showDiskCard || settings.showMenuDisk || settings.enableLowDiskAlert)
            : (settings.showMenuDisk || settings.enableLowDiskAlert)
        let sampleNetwork = hot
            ? (settings.showNetworkCard || settings.showMenuNetwork)
            : settings.showMenuNetwork
        let sampleThermal = hot
            ? (settings.showPowerGPUCard || settings.showCPUCard || settings.showMenuTemperature || settings.enableThermalAlert)
            : (settings.showMenuTemperature || settings.enableThermalAlert)
        let samplePower = hot
            ? (settings.showPowerGPUCard || settings.showMenuPower)
            : settings.showMenuPower
        let sampleBattery = hot
            ? (settings.showBatteryPowerCard || settings.enableLowBatteryAlert)
            : settings.enableLowBatteryAlert
        let sampleProcs = hot && (settings.showTopAppsSection || style == .breathingDot)

        // 「灵动圆环」仅在高压态时于冷态做节流进程采样
        let needColdProcs = !hot && style == .breathingDot && latestHealthSummary.level == .elevated
        if !hot && !needColdProcs && coldProcessSamplingActive {
            engine.resetHotProcessThrottle()
        }
        coldProcessSamplingActive = needColdProcs

        let mask = SampledMask(
            cpu: sampleCPU,
            memory: sampleMemory,
            network: sampleNetwork,
            power: samplePower,
            thermal: sampleThermal
        )
        let capturedEngine = engine

        Task.detached(priority: .utility) {
            let nextSnapshot: SystemSnapshot
            if hot {
                nextSnapshot = capturedEngine.sampleHot(
                    includeCPU: sampleCPU,
                    includeMemory: sampleMemory,
                    includeNetwork: sampleNetwork,
                    includeDisk: sampleDisk,
                    includeBattery: sampleBattery,
                    includeSiliconPower: samplePower,
                    includeThermal: sampleThermal,
                    includeProcesses: sampleProcs
                )
            } else {
                nextSnapshot = capturedEngine.sampleCold(
                    needCPU: sampleCPU,
                    needMemory: sampleMemory,
                    needDisk: sampleDisk,
                    needNetwork: sampleNetwork,
                    needThermal: sampleThermal,
                    needPower: samplePower,
                    needBattery: sampleBattery,
                    includeProcesses: needColdProcs
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applySnapshot(nextSnapshot, mask: mask, isHot: hot)
                self.isSamplingInFlight = false
            }
        }
    }

    private func applySnapshot(_ next: SystemSnapshot, mask: SampledMask, isHot: Bool) {
        latestSnapshot = next

        // 仅向本轮实际采样的历史缓冲区追加读数，杜绝未采样模块用旧值污染折线图
        if mask.cpu {
            cpuBuffer.append(next.cpu.totalUsagePercent)
        }
        if mask.memory {
            memoryBuffer.append(next.memory.usedPercent)
        }
        if mask.network {
            downloadBuffer.append(next.network.downloadBytesPerSec)
            uploadBuffer.append(next.network.uploadBytesPerSec)
        }
        if mask.power && next.siliconPower.isAvailable {
            powerBuffer.append(next.siliconPower.packageWatts)
        }
        if mask.thermal, let temp = next.thermalFan.primaryTemperature {
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

        if isHot || settings.enableThermalAlert || settings.enableMemoryAlert || settings.enableLowBatteryAlert || settings.enableLowDiskAlert {
            evaluateAlertsIfEnabled(next)
        }
    }

    private func makeMenuBarRenderData(from snap: SystemSnapshot, health: HealthSummary) -> MenuBarRenderData {
        let primaryVol = snap.disk.primaryVolume
        return MenuBarRenderData(
            cpuPercent: snap.cpu.totalUsagePercent,
            memoryPercent: snap.memory.usedPercent,
            memoryPressure: snap.memory.pressure,
            diskFreeBytes: primaryVol?.availableBytes,
            diskUsedPercent: primaryVol?.usedPercent,
            uploadBytesPerSec: snap.network.uploadBytesPerSec,
            downloadBytesPerSec: snap.network.downloadBytesPerSec,
            temperatureCelsius: snap.thermalFan.primaryTemperature,
            packageWatts: snap.siliconPower.packageWatts,
            isPowerAvailable: snap.siliconPower.isAvailable,
            healthLevel: health.level,
            // 基线轮次所有进程 CPU 均为 0，需过滤掉，避免浮现无关 App 图标
            topCPUAppPath: snap.topCPUApps.first.flatMap { $0.cpuPercent >= 10.0 ? $0.appBundlePath : nil },
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

        if settings.enableLowDiskAlert,
           let vol = snap.disk.primaryVolume,
           vol.totalBytes > 0 {
            let thresholdBytes = UInt64(max(1.0, settings.lowDiskAlertThresholdGB) * 1_000_000_000.0)
            if vol.availableBytes <= thresholdBytes {
                let freeStr = ByteFormatter.diskSize(vol.availableBytes)
                sendNotificationIfNeeded(
                    key: "disk",
                    title: BaroL10n.t("Baro 磁盘空间提醒", "Baro Disk Space Alert", lang: lang),
                    body: BaroL10n.t(
                        "主磁盘剩余可用空间仅余 \(freeStr)。",
                        "Primary disk free space is down to \(freeStr).",
                        lang: lang
                    )
                )
            }
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
