import AppKit
import XCTest
@testable import BaroCore
@testable import BaroKit

final class BaroCoreTests: XCTestCase {
    func testRingBufferCapacityAndOrdering() {
        var buffer = RingBuffer<Int>(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        buffer.append(10)
        buffer.append(20)
        buffer.append(30)
        XCTAssertEqual(buffer.values, [10, 20, 30])
        XCTAssertEqual(buffer.latest, 30)

        buffer.append(40)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.values, [20, 30, 40])
        XCTAssertEqual(buffer.latest, 40)

        buffer.clear()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.latest)
    }

    func testByteFormatterCompactAndDetailed() {
        XCTAssertEqual(ByteFormatter.compactRate(0), "0B")
        XCTAssertEqual(ByteFormatter.compactRate(512), "512B")
        XCTAssertEqual(ByteFormatter.compactRate(128 * 1_024), "128K")
        XCTAssertEqual(ByteFormatter.compactRate(4.2 * 1_024 * 1_024), "4.2M")

        XCTAssertEqual(ByteFormatter.detailedRate(4.28 * 1_024 * 1_024), "4.28 MB/s")
        XCTAssertEqual(ByteFormatter.memorySize(16 * 1_024 * 1_024 * 1_024), "16.0 GB")
        XCTAssertEqual(ByteFormatter.compactDiskSize(650_000_000), "650M")
        XCTAssertEqual(ByteFormatter.compactDiskSize(38_400_000_000), "38.4G")
        XCTAssertEqual(ByteFormatter.compactDiskSize(245_000_000_000), "245G")
        XCTAssertEqual(ByteFormatter.compactDiskSize(1_420_000_000_000), "1.42T")
        // 进位临界点防跳变验证
        XCTAssertEqual(ByteFormatter.compactDiskSize(99_960_000_000), "100G")
        XCTAssertEqual(ByteFormatter.compactDiskSize(999_600_000_000), "1.00T")
        XCTAssertEqual(ByteFormatter.compactRate(999.7), "1K")
        XCTAssertEqual(ByteFormatter.detailedRate(999.7), "1.0 KB/s")
        XCTAssertEqual(ByteFormatter.compactRate(999.6 * 1_024), "1.0M")
        XCTAssertEqual(ByteFormatter.memorySize(512), "512 B")
        XCTAssertEqual(ByteFormatter.diskSize(450), "450 B")
        XCTAssertEqual(ByteFormatter.uptime(3 * 86_400 + 14 * 3_600), "3d 14h")
    }

    func testOutermostAppBundleAggregation() {
        let chromeMain = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/130/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let zshProc = "/bin/zsh"

        XCTAssertEqual(
            ProcessAggregatorCollector.outermostAppBundlePath(from: chromeMain),
            "/Applications/Google Chrome.app"
        )
        XCTAssertEqual(
            ProcessAggregatorCollector.outermostAppBundlePath(from: chromeHelper),
            "/Applications/Google Chrome.app"
        )
        XCTAssertNil(ProcessAggregatorCollector.outermostAppBundlePath(from: zshProc))

        let samples = [
            RawProcessSample(pid: 100, executablePath: chromeMain, fallbackName: "Chrome", cpuPercent: 12.0, memoryBytes: 500_000_000),
            RawProcessSample(pid: 101, executablePath: chromeHelper, fallbackName: "Chrome Helper", cpuPercent: 22.5, memoryBytes: 900_000_000),
            RawProcessSample(pid: 200, executablePath: zshProc, fallbackName: "zsh", cpuPercent: 1.0, memoryBytes: 10_000_000)
        ]

        let aggregated = ProcessAggregatorCollector.aggregateProcesses(samples) { path in
            if path.contains("Google Chrome.app") {
                return ("Google Chrome", "com.google.Chrome")
            }
            return ("Unknown", nil)
        }

        let chrome = aggregated.first { $0.name == "Google Chrome" }
        XCTAssertNotNil(chrome)
        XCTAssertEqual(chrome?.pidsCount, 2)
        XCTAssertEqual(chrome?.cpuPercent ?? 0, 34.5, accuracy: 0.01)
        XCTAssertEqual(chrome?.memoryBytes, 1_400_000_000)
    }

    func testProcessIdentityPreventsPIDReuseCollision() {
        let oldProc = ProcessIdentity(pid: 4242, startAbstime: 1_000_000)
        let reusedProc = ProcessIdentity(pid: 4242, startAbstime: 9_999_999)
        let prevMap: [ProcessIdentity: UInt64] = [oldProc: 500_000_000]

        // 相同身份正常计算 25% CPU 差分
        let validPct = ProcessAggregatorCollector.computeCPUDeltaPercent(
            identity: oldProc,
            currentNanos: 750_000_000,
            previousNanosByIdentity: prevMap,
            dtNanos: 1_000_000_000
        )
        XCTAssertEqual(validPct, 25.0, accuracy: 0.001)

        // PID 相同但启动时间不同（PID 被新进程复用），绝不沿用旧进程基线
        let reusedPct = ProcessAggregatorCollector.computeCPUDeltaPercent(
            identity: reusedProc,
            currentNanos: 800_000_000,
            previousNanosByIdentity: prevMap,
            dtNanos: 1_000_000_000
        )
        XCTAssertEqual(reusedPct, 0.0, accuracy: 0.001)
    }

    func testThermalSensorFilteringRemovesDormantCores() {
        let raw = [
            ThermalSensorReading(name: "PMU tdie1", celsius: 41.2, source: "HID"),
            ThermalSensorReading(name: "Dormant Core", celsius: -40.0, source: "HID"),
            ThermalSensorReading(name: "Zero Sensor", celsius: 0.0, source: "HID"),
            ThermalSensorReading(name: "Broken Sensor", celsius: 250.0, source: "SMC"),
            ThermalSensorReading(name: "GPU 1", celsius: 38.5, source: "HID")
        ]
        let filtered = ThermalFanCollector.filterValidThermalReadings(raw)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.name), ["PMU tdie1", "GPU 1"])
    }

    func testSMCStructLayoutDecodersAndNegativeLookupCache() {
        XCTAssertEqual(MemoryLayout<ReadOnlySMCClient.SMCKeyData>.stride, 80)

        let floatVal: Float = 1234.5
        let floatBytes = withUnsafeBytes(of: floatVal.bitPattern.littleEndian) { Array($0) }
        let fltCode = (UInt32(Character("f").asciiValue!) << 24)
            | (UInt32(Character("l").asciiValue!) << 16)
            | (UInt32(Character("t").asciiValue!) << 8)
            | UInt32(Character(" ").asciiValue!)
        let decodedFloat = ReadOnlySMCClient.decodeSMCValue(bytes: floatBytes, dataType: fltCode, dataSize: 4)
        XCTAssertEqual(decodedFloat ?? 0, 1234.5, accuracy: 0.1)

        // 验证全 0xFF (NaN) 或无穷大浮点绝不透传触发下游 Int(...) 强转崩溃
        XCTAssertNil(ReadOnlySMCClient.decodeSMCValue(bytes: [0xFF, 0xFF, 0xFF, 0xFF], dataType: fltCode, dataSize: 4))
        XCTAssertNil(ReadOnlySMCClient.safeRoundedInt(.nan, validRange: 0...30_000))
        XCTAssertNil(ReadOnlySMCClient.safeRoundedInt(.infinity, validRange: 0...30_000))
        XCTAssertNil(ReadOnlySMCClient.safeRoundedInt(99_999.0, validRange: 0...30_000))
        XCTAssertEqual(ReadOnlySMCClient.safeRoundedInt(2150.4, validRange: 0...30_000), 2150)

        let fpe2Code = (UInt32(Character("f").asciiValue!) << 24)
            | (UInt32(Character("p").asciiValue!) << 16)
            | (UInt32(Character("e").asciiValue!) << 8)
            | UInt32(Character("2").asciiValue!)
        let decodedFpe2 = ReadOnlySMCClient.decodeSMCValue(bytes: [0x12, 0xC0], dataType: fpe2Code, dataSize: 2)
        XCTAssertEqual(decodedFpe2 ?? 0, 1200.0, accuracy: 0.01)

        // 验证 SMC 负向缓存：不存在的键只调用底层一次，后续命中 `.some(nil)` 零调用
        var cache: [UInt32: Int?] = [:]
        var backendCalls = 0
        let firstMiss = ReadOnlySMCClient.cachedLookup(key: 0xDEAD_BEEF, cache: &cache) { _ in
            backendCalls += 1
            return nil
        }
        let secondMiss = ReadOnlySMCClient.cachedLookup(key: 0xDEAD_BEEF, cache: &cache) { _ in
            backendCalls += 1
            return 99
        }
        XCTAssertNil(firstMiss)
        XCTAssertNil(secondMiss)
        XCTAssertEqual(backendCalls, 1)
    }

    func testCPUClusterTypeAndLogicalIndexParsing() {
        XCTAssertEqual(CPUCollector.parseClusterType("E"), .efficiency)
        XCTAssertEqual(CPUCollector.parseClusterType("P"), .performance)
        XCTAssertEqual(CPUCollector.parseClusterType(Data([0x45, 0x00])), .efficiency)
        XCTAssertEqual(CPUCollector.parseClusterType(Data([0x50, 0x00])), .performance)
        XCTAssertEqual(CPUCollector.parseClusterType(Data([0x4D, 0x00])), .performance)
        XCTAssertEqual(CPUCollector.parseClusterType("?"), .unknown)

        XCTAssertEqual(CPUCollector.parseLogicalCPUIndex(NSNumber(value: 6)), 6)
        XCTAssertEqual(CPUCollector.parseLogicalCPUIndex(Data([0x07, 0x00, 0x00, 0x00])), 7)
    }

    func testAppleSiliconEnergyUnitConversion() {
        // 2,000,000,000 nJ in 2.0s => 2 J / 2s = 1.0 W
        XCTAssertEqual(AppleSiliconPowerCollector.convertEnergyToWatts(value: 2_000_000_000, unitLabel: "nJ", durationSeconds: 2.0), 1.0, accuracy: 0.0001)
        // 5,000,000 µJ in 0.5s => 5 J / 0.5s = 10.0 W
        XCTAssertEqual(AppleSiliconPowerCollector.convertEnergyToWatts(value: 5_000_000, unitLabel: "µJ", durationSeconds: 0.5), 10.0, accuracy: 0.0001)
        // 3,000 mJ in 1.5s => 3 J / 1.5s = 2.0 W
        XCTAssertEqual(AppleSiliconPowerCollector.convertEnergyToWatts(value: 3_000, unitLabel: "mJ", durationSeconds: 1.5), 2.0, accuracy: 0.0001)
        // 12 J in 3.0s => 4.0 W
        XCTAssertEqual(AppleSiliconPowerCollector.convertEnergyToWatts(value: 12, unitLabel: "J", durationSeconds: 3.0), 4.0, accuracy: 0.0001)
        XCTAssertEqual(AppleSiliconPowerCollector.convertEnergyToWatts(value: 100, unitLabel: "mJ", durationSeconds: 0), 0.0)
    }

    func testUpdateCheckerVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersionNewer(remote: "1.3.0", current: "1.2.2"))
        XCTAssertTrue(UpdateChecker.isVersionNewer(remote: "v1.2.10", current: "1.2.2"))
        XCTAssertTrue(UpdateChecker.isVersionNewer(remote: "2.0", current: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isVersionNewer(remote: "1.3.0", current: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isVersionNewer(remote: "1.3", current: "1.3.0"))
        XCTAssertFalse(UpdateChecker.isVersionNewer(remote: "1.2.1", current: "1.2.2"))
        XCTAssertFalse(UpdateChecker.isVersionNewer(remote: "", current: "1.2.2"))

        // SemVer 预发布与安全跳转 URL 白名单验证
        XCTAssertFalse(UpdateChecker.isVersionNewer(remote: "v1.4.1-rc.2", current: "1.4.1"))
        XCTAssertTrue(UpdateChecker.isVersionNewer(remote: "v1.4.1", current: "1.4.1-rc.2"))
        XCTAssertTrue(UpdateChecker.isVersionNewer(remote: "1.4.2-rc.2", current: "1.4.2-rc.1"))
        XCTAssertEqual(
            UpdateChecker.sanitizedReleaseURL("https://github.com/seaskyx2/Baro/releases/tag/v1.4.2").absoluteString,
            "https://github.com/seaskyx2/Baro/releases/tag/v1.4.2"
        )
        XCTAssertEqual(
            UpdateChecker.sanitizedReleaseURL("file:///System/Applications/Calculator.app").absoluteString,
            "https://github.com/seaskyx2/Baro/releases/latest"
        )
        XCTAssertEqual(
            UpdateChecker.sanitizedReleaseURL("https://evil.example.com/seaskyx2/Baro/releases").absoluteString,
            "https://github.com/seaskyx2/Baro/releases/latest"
        )
    }

    func testSmartBatteryParser() {
        let props: [String: Any] = [
            "AppleRawCurrentCapacity": 4200,
            "AppleRawMaxCapacity": 4850,
            "DesignCapacity": 5000,
            "CycleCount": 48,
            "IsCharging": false,
            "ExternalConnected": false,
            "Voltage": 12000,
            "InstantAmperage": Int64(-750),
            "Temperature": 3050,
            "TimeRemaining": 240,
            "AdapterDetails": ["Watts": 70]
        ]

        let parsed = BatteryPowerCollector.parseSmartBatteryProperties(props)
        XCTAssertTrue(parsed.hasInternalBattery)
        XCTAssertEqual(parsed.chargePercent, 86.59, accuracy: 0.1)
        XCTAssertEqual(parsed.healthPercent, 97.0, accuracy: 0.1)
        XCTAssertEqual(parsed.powerWatts, -9.0, accuracy: 0.01)
        XCTAssertEqual(parsed.temperatureCelsius ?? 0, 30.5, accuracy: 0.01)
        XCTAssertEqual(parsed.cycleCount, 48)
        XCTAssertEqual(parsed.adapterWatts, 70)
        XCTAssertEqual(parsed.powerSource, .internalBattery)

        let desktopProps: [String: Any] = [
            "BatteryInstalled": false,
            "MaxCapacity": 0,
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 22769]
        ]
        let desktopParsed = BatteryPowerCollector.parseSmartBatteryProperties(desktopProps)
        XCTAssertFalse(desktopParsed.hasInternalBattery)
        XCTAssertTrue(desktopParsed.isPluggedIn)
        XCTAssertEqual(desktopParsed.powerSource, .acPower)
        XCTAssertEqual(desktopParsed.powerWatts, 22.769, accuracy: 0.01)
    }

    func testHealthAnalyzerThresholdsAndMessages() {
        var snap = SystemSnapshot.empty
        snap.memory = MemorySnapshot(
            totalBytes: 16_000_000_000,
            usedBytes: 8_000_000_000,
            appBytes: 5_000_000_000,
            wiredBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            cachedFilesBytes: 2_000_000_000,
            freeBytes: 8_000_000_000,
            swapUsedBytes: 0,
            swapTotalBytes: 0,
            pressure: .normal
        )
        let calm = HealthAnalyzer.analyze(snapshot: snap)
        XCTAssertEqual(calm.level, .calm)
        XCTAssertEqual(calm.message, "系统平静 · 零交换压力")

        snap.cpu.totalUsagePercent = 52.0
        let moderate = HealthAnalyzer.analyze(snapshot: snap, language: .en)
        XCTAssertEqual(moderate.level, .moderate)
        XCTAssertTrue(moderate.message.contains("Moderate Load"))

        snap.cpu.totalUsagePercent = 82.0
        let xcode = AggregatedAppUsage(
            id: "app:Xcode",
            name: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            appBundlePath: "/Applications/Xcode.app",
            cpuPercent: 64.0,
            memoryBytes: 2_000_000_000,
            pidsCount: 5
        )
        let elevated = HealthAnalyzer.analyze(snapshot: snap, topCPUApp: xcode, language: .en)
        XCTAssertEqual(elevated.level, .elevated)
        XCTAssertTrue(elevated.message.contains("Xcode"))
        XCTAssertTrue(elevated.message.contains("High Load"))

        // 验证低磁盘空间健康诊断
        var lowDiskSnap = SystemSnapshot.empty
        lowDiskSnap.disk = DiskSnapshot(
            readBytesPerSec: 0,
            writeBytesPerSec: 0,
            volumes: [DiskVolume(name: "Macintosh HD", mountPath: "/", totalBytes: 500_000_000_000, availableBytes: 8_500_000_000, isInternal: true)]
        )
        let lowDiskHealth = HealthAnalyzer.analyze(snapshot: lowDiskSnap, language: .zhHans)
        XCTAssertEqual(lowDiskHealth.level, .elevated)
        XCTAssertTrue(lowDiskHealth.message.contains("磁盘空间告急"))
    }

    func testLocalizationResolution() {
        XCTAssertEqual(BaroL10n.resolve(.zhHans, preferredLanguages: ["en-US"]), .zhHans)
        XCTAssertEqual(BaroL10n.resolve(.en, preferredLanguages: ["zh-Hans-CN"]), .en)
        XCTAssertEqual(BaroL10n.resolve(.system, preferredLanguages: ["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(BaroL10n.resolve(.system, preferredLanguages: ["en-US"]), .en)
        XCTAssertEqual(MenuBarStyle.allCases.count, 5)
        XCTAssertEqual(BaroL10n.menuBarStyleTitle(.miniBars, lang: .zhHans), "精工双柱")
        XCTAssertEqual(BaroL10n.menuBarStyleTitle(.singleLine, lang: .en), "Inline Pill")
        XCTAssertEqual(BaroL10n.powerSourceTitle(.acPower, lang: .en), "AC Power")
    }

    /// 回归：proc_listallpids 返回 PID 个数，曾被误除以 4 导致只扫描约 1/4 进程
    func testListAllPIDsCoversAllProcesses() {
        let expected = Int(proc_listallpids(nil, 0))
        let pids = ProcessAggregatorCollector.listAllPIDs()
        XCTAssertGreaterThan(expected, 0)
        XCTAssertGreaterThanOrEqual(pids.count, expected * 8 / 10)
        XCTAssertTrue(pids.contains(ProcessInfo.processInfo.processIdentifier))
    }

    /// 回归：冷态不得沿用上一次热态的进程排行或未采样模块的旧峰值（如旧高温/旧高网速）
    func testColdSampleDropsStaleTopAppsAndUnsampledPeaks() {
        var prev = SystemSnapshot.empty
        let stale = AggregatedAppUsage(
            id: "app:Stale",
            name: "Stale",
            bundleIdentifier: nil,
            appBundlePath: "/Applications/Stale.app",
            cpuPercent: 90,
            memoryBytes: 1,
            pidsCount: 1
        )
        prev.topCPUApps = [stale]
        prev.topMemoryApps = [stale]
        prev.thermalFan = ThermalFanSnapshot(
            socTemperature: 95.0,
            cpuTemperature: 95.0,
            gpuTemperature: nil,
            ssdTemperature: nil,
            sensors: [],
            fans: []
        )
        prev.network = NetworkSnapshot(
            downloadBytesPerSec: 25_000_000,
            uploadBytesPerSec: 5_000_000,
            sessionDownloadBytes: 100,
            sessionUploadBytes: 100,
            primaryInterface: "en0",
            localIPAddress: "10.0.0.2",
            isConnected: true
        )
        let next = CollectorEngine().sampleCold(
            previous: prev,
            needCPU: false,
            needMemory: false,
            needNetwork: false,
            needThermal: false,
            needPower: false
        )
        XCTAssertTrue(next.topCPUApps.isEmpty)
        XCTAssertTrue(next.topMemoryApps.isEmpty)
        XCTAssertNil(next.thermalFan.primaryTemperature)
        XCTAssertEqual(next.network.downloadBytesPerSec, 0)
        XCTAssertEqual(HealthAnalyzer.analyze(snapshot: next).level, .calm)
    }

    /// 回归：面板收起时导出的快照必须带有效结构与核心读数
    @MainActor
    func testCaptureFreshSnapshotProducesPopulatedSnapshot() {
        let suiteName = "com.baro.tests.capture"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let coordinator = SamplingCoordinator(settings: BaroSettings(defaults: defaults))
        let done = expectation(description: "capture")
        var captured: SystemSnapshot?
        coordinator.captureFreshSnapshot { snap, _ in
            captured = snap
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        defaults.removePersistentDomain(forName: suiteName)

        let snap = try! XCTUnwrap(captured)
        XCTAssertGreaterThan(snap.cpu.totalCoreCount, 0)
        XCTAssertGreaterThan(snap.memory.totalBytes, 0)
    }

    func testNVMeSmartUnitConversionAndSleepAssertionsAndSanitizedExport() {
        let smart = DiskCollector.convertNVMeReading(
            percentageUsed: 3,
            availableSpare: 100,
            temperatureCelsius: 36,
            dataUnitsReadLow: 20_000_000,
            dataUnitsWrittenLow: 10_000_000,
            powerOnHours: 420,
            powerCycles: 32
        )
        XCTAssertEqual(smart.healthPercent, 97)
        XCTAssertEqual(smart.totalBytesWritten, 5_120_000_000_000)
        XCTAssertEqual(smart.totalBytesRead, 10_240_000_000_000)
        XCTAssertEqual(smart.temperatureCelsius, 36)

        let rawAssertions: [NSNumber: [[String: Any]]] = [
            100: [["AssertType": "PreventUserIdleSystemSleep", "Process Name": "powerd"]],
            200: [["AssertType": "PreventUserIdleSystemSleep", "Process Name": "CaffeineApp"]],
            201: [["AssertType": "PreventUserIdleDisplaySleep", "Process Name": "CaffeineApp"]],
            300: [["AssertType": "BackgroundTask", "Process Name": "SomeTask"]]
        ]
        let blockers = SleepAssertionCollector.parseAssertions(rawAssertions)
        XCTAssertEqual(blockers.count, 1)
        XCTAssertEqual(blockers.first?.processName, "CaffeineApp")
        XCTAssertTrue(blockers.first?.preventsDisplaySleep == true)

        var snap = SystemSnapshot.empty
        snap.network = NetworkSnapshot(
            downloadBytesPerSec: 1_024_000,
            uploadBytesPerSec: 512_000,
            sessionDownloadBytes: 5_000_000,
            sessionUploadBytes: 2_000_000,
            primaryInterface: "en0",
            localIPAddress: "192.168.1.99",
            isConnected: true
        )
        snap.sleepBlockers = blockers
        let host = HostStaticInfo(
            chipName: "Apple M4",
            modelIdentifier: "Mac",
            osVersionString: "macOS 27.2",
            totalMemoryBytes: 17_179_869_184,
            pCoreCount: 4,
            eCoreCount: 6,
            totalCoreCount: 10
        )
        let exported = SnapshotExporter.formatPlainText(
            hostInfo: host,
            snapshot: snap,
            health: HealthAnalyzer.analyze(snapshot: snap, language: .en),
            lang: .en
        )
        XCTAssertFalse(exported.contains("192.168.1.99"))
        XCTAssertFalse(exported.contains("/Users/"))
        XCTAssertTrue(exported.contains("CaffeineApp"))
    }

    /// 回归：关闭偏好设置窗口绝不能触发 NSWindow 过度释放崩溃（isReleasedWhenClosed 必须为 false）
    @MainActor
    func testClosingSettingsWindowDoesNotCrashOrOverRelease() throws {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(app))

        let win = try XCTUnwrap(delegate.openSettingsWindowForTesting())
        XCTAssertFalse(win.isReleasedWhenClosed)
        win.close()

        let drained = expectation(description: "drain main queue after window close")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 2.0)
    }

    /// 回归：验证 32 位 CPU Tick 跨 2^31 符号位与 2^32 回绕、64/32 位网卡跨位宽隔离、Settings 非有限浮点净化、单实例平局裁决及跨阈值签名重绘
    @MainActor
    func testAuditHardeningRegressions() throws {
        // 1. CPU 跨 0x7FFF_FFFF (2^31) 符号位翻转与 0xFFFF_FFFF (2^32) 回绕绝不有符号扩展溢出
        let prevSignBoundary = CPUCollector.CoreTicks(user: 0x7FFF_FFF0, system: 100, idle: 0xFFFF_FFF0, nice: 0)
        let currSignBoundary = CPUCollector.CoreTicks(user: 0x8000_0010, system: 120, idle: 0x0000_0010, nice: 0)
        let tickDelta = CPUCollector.computeCoreTickDelta(current: currSignBoundary, previous: prevSignBoundary)
        XCTAssertEqual(tickDelta.user, 32)
        XCTAssertEqual(tickDelta.system, 20)
        XCTAssertEqual(tickDelta.idle, 32)
        XCTAssertEqual(tickDelta.nice, 0)

        // 2. Network 64 位与 32 位回退之间严禁跨位宽相减产生 N × 4 GiB 假尖峰
        let prev32: [String: NetworkCollector.InterfaceTotals] = ["en0": .init(inBytes: 500_000_000, outBytes: 100_000)]
        let curr64: [String: NetworkCollector.InterfaceTotals] = ["en0": .init(inBytes: 9_089_934_592, outBytes: 4_295_067_296)]
        XCTAssertNil(NetworkCollector.computeSafeTrafficDelta(
            currentTotals: curr64,
            currentIs64Bit: true,
            previousTotals: prev32,
            previousIs64Bit: false
        ))
        let sameWidth = NetworkCollector.computeSafeTrafficDelta(
            currentTotals: ["en0": .init(inBytes: 9_090_034_592, outBytes: 4_295_077_296)],
            currentIs64Bit: true,
            previousTotals: curr64,
            previousIs64Bit: true
        )
        XCTAssertEqual(sameWidth?.deltaIn, 100_000)
        XCTAssertEqual(sameWidth?.deltaOut, 10_000)

        // 3. BaroSettings 对 NaN / ±Inf 与越界值的防御
        XCTAssertEqual(BaroSettings.sanitizedDouble(.nan, default: 20.0, range: 1.0...2_000.0), 20.0)
        XCTAssertEqual(BaroSettings.sanitizedDouble(.infinity, default: 20.0, range: 1.0...2_000.0), 20.0)
        XCTAssertEqual(BaroSettings.sanitizedDouble(99_999.0, default: 20.0, range: 1.0...2_000.0), 2_000.0)

        // 4. 双实例同毫秒并发启动确定性胜出（较小 PID 留存，较大 PID 退出，绝不互杀）
        let t0 = Date()
        let peers: [(pid: pid_t, launchDate: Date?, isTerminated: Bool)] = [
            (pid: 1001, launchDate: t0, isTerminated: false),
            (pid: 1002, launchDate: t0, isTerminated: false)
        ]
        XCTAssertFalse(AppDelegate.shouldTerminateAsDuplicate(currentPID: 1001, currentLaunchDate: t0, peers: peers))
        XCTAssertTrue(AppDelegate.shouldTerminateAsDuplicate(currentPID: 1002, currentLaunchDate: t0, peers: peers))

        // 5. MenuBarImageRenderer 跨 65.0% 变色阈值但同整数桶 (64.6 vs 65.2 -> 65) 必须产生不同签名触发重绘
        let suiteName = "com.baro.tests.audit.sig"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = BaroSettings(defaults: defaults)
        settings.menuBarStyle = .compactDualRow
        settings.showMenuCPU = true
        let darkApp = try XCTUnwrap(NSAppearance(named: .darkAqua))

        var belowThreshold = MenuBarRenderData.empty
        belowThreshold.cpuPercent = 64.6
        var aboveThreshold = MenuBarRenderData.empty
        aboveThreshold.cpuPercent = 65.2

        let sigBelow = MenuBarImageRenderer.renderSignature(data: belowThreshold, settings: settings, appearance: darkApp)
        let sigAbove = MenuBarImageRenderer.renderSignature(data: aboveThreshold, settings: settings, appearance: darkApp)
        XCTAssertNotEqual(sigBelow, sigAbove)

        // 6. 非 .app 测试环境下通知守卫必须安全拦截而不抛异常
        SamplingCoordinator.requestNotificationPermissionIfNeeded()
    }

    @MainActor
    func testMenuBarStylesRenderValidBitmapsAndSignatures() throws {
        let suiteName = "com.baro.tests.menubar.render"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = BaroSettings(defaults: defaults)
        settings.showMenuBarIcon = true
        settings.showMenuCPU = true
        settings.showMenuMemory = true
        settings.showMenuDisk = true
        settings.showMenuNetwork = true
        settings.showMenuTemperature = false
        settings.showMenuPower = false

        let calmData = MenuBarRenderData(
            cpuPercent: 18,
            memoryPercent: 64,
            memoryPressure: .normal,
            diskFreeBytes: 245_000_000_000,
            diskUsedPercent: 51,
            uploadBytesPerSec: 48 * 1_024,
            downloadBytesPerSec: 4.2 * 1_024 * 1_024,
            temperatureCelsius: 41,
            packageWatts: 14.5,
            isPowerAvailable: true,
            healthLevel: .calm,
            topCPUAppPath: nil,
            cpuSparklinePoints: [10, 14, 12, 26, 20, 18, 35, 29, 16, 18]
        )

        let hotData = MenuBarRenderData(
            cpuPercent: 88,
            memoryPercent: 86,
            memoryPressure: .warning,
            diskFreeBytes: 9_200_000_000,
            diskUsedPercent: 96,
            uploadBytesPerSec: 120 * 1_024,
            downloadBytesPerSec: 12.6 * 1_024 * 1_024,
            temperatureCelsius: 82,
            packageWatts: 34.0,
            isPowerAvailable: true,
            healthLevel: .elevated,
            topCPUAppPath: "/System/Applications/Utilities/Activity Monitor.app",
            cpuSparklinePoints: [30, 45, 52, 68, 74, 80, 76, 85, 91, 88]
        )

        let darkApp = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightApp = try XCTUnwrap(NSAppearance(named: .aqua))

        for style in MenuBarStyle.allCases {
            settings.menuBarStyle = style

            let sig1 = MenuBarImageRenderer.renderSignature(data: calmData, settings: settings, appearance: darkApp)
            let sig2 = MenuBarImageRenderer.renderSignature(data: calmData, settings: settings, appearance: darkApp)
            let sigHot = MenuBarImageRenderer.renderSignature(data: hotData, settings: settings, appearance: darkApp)
            XCTAssertEqual(sig1, sig2)
            XCTAssertNotEqual(sig1, sigHot)

            let calmImage = MenuBarImageRenderer.render(data: calmData, settings: settings, appearance: darkApp)
            XCTAssertEqual(calmImage.size.height, 22, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(calmImage.size.width, 18)
            XCTAssertLessThanOrEqual(calmImage.size.width, 220)

            // 除灵动圆环外，所有风格在平静负载下必须启用原生 template 模式
            if style == .breathingDot {
                XCTAssertFalse(calmImage.isTemplate)
            } else {
                XCTAssertTrue(calmImage.isTemplate, "\(style.rawValue) should use native isTemplate in calm state")
            }

            let rep = try XCTUnwrap(calmImage.representations.first as? NSBitmapImageRep)
            XCTAssertGreaterThan(Self.countNonTransparentPixels(in: rep), 40, "\(style.rawValue) bitmap must contain visible strokes")

            // 高压状态下必须切换为非 template 语义着色渲染
            let hotImage = MenuBarImageRenderer.render(data: hotData, settings: settings, appearance: lightApp)
            XCTAssertFalse(hotImage.isTemplate)
            let hotRep = try XCTUnwrap(hotImage.representations.first as? NSBitmapImageRep)
            XCTAssertGreaterThan(Self.countNonTransparentPixels(in: hotRep), 40)
        }

        if let exportPath = ProcessInfo.processInfo.environment["BARO_RENDER_SHEET_PATH"], !exportPath.isEmpty {
            try Self.exportVisualQASheet(
                to: URL(fileURLWithPath: exportPath),
                calmData: calmData,
                hotData: hotData,
                settings: settings,
                darkApp: darkApp,
                lightApp: lightApp
            )
        }
    }

    private static func countNonTransparentPixels(in rep: NSBitmapImageRep) -> Int {
        guard let ptr = rep.bitmapData else { return 0 }
        let totalBytes = rep.bytesPerRow * rep.pixelsHigh
        var nonZeroAlpha = 0
        var idx = 3
        while idx < totalBytes {
            if ptr[idx] > 16 {
                nonZeroAlpha += 1
            }
            idx += 4
        }
        return nonZeroAlpha
    }

    @MainActor
    private static func exportVisualQASheet(
        to url: URL,
        calmData: MenuBarRenderData,
        hotData: MenuBarRenderData,
        settings: BaroSettings,
        darkApp: NSAppearance,
        lightApp: NSAppearance
    ) throws {
        let styles = MenuBarStyle.allCases
        let canvasW: CGFloat = 680
        let rowH: CGFloat = 46
        let canvasH: CGFloat = CGFloat(styles.count) * rowH + 34
        let scale: CGFloat = 3.0

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasW * scale),
            pixelsHigh: Int(canvasH * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: canvasW, height: canvasH)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high

            NSColor(calibratedWhite: 0.11, alpha: 1.0).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasW, height: canvasH)).fill()

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6)
            ]
            ("深色菜单栏（平静态 Template）" as NSString).draw(at: NSPoint(x: 96, y: canvasH - 22), withAttributes: headerAttrs)
            ("浅色菜单栏（平静态 Template）" as NSString).draw(at: NSPoint(x: 308, y: canvasH - 22), withAttributes: headerAttrs)
            ("高压预警态（Semantic Color）" as NSString).draw(at: NSPoint(x: 520, y: canvasH - 22), withAttributes: headerAttrs)

            for (i, st) in styles.enumerated() {
                settings.menuBarStyle = st
                let y = canvasH - 26 - CGFloat(i + 1) * rowH + 8

                let title = BaroL10n.menuBarStyleTitle(st, lang: .zhHans)
                (title as NSString).draw(at: NSPoint(x: 14, y: y + 6), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92)
                ])

                let darkBar = NSRect(x: 92, y: y + 1, width: 204, height: 26)
                NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1.0).setFill()
                NSBezierPath(roundedRect: darkBar, xRadius: 6, yRadius: 6).fill()
                let imgDark = MenuBarImageRenderer.render(data: calmData, settings: settings, appearance: darkApp)
                drawPreviewMenuBarImage(imgDark, at: NSPoint(x: darkBar.minX + 8, y: darkBar.minY + 2), templateTint: .white)

                let lightBar = NSRect(x: 304, y: y + 1, width: 204, height: 26)
                NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0).setFill()
                NSBezierPath(roundedRect: lightBar, xRadius: 6, yRadius: 6).fill()
                let imgLight = MenuBarImageRenderer.render(data: calmData, settings: settings, appearance: lightApp)
                drawPreviewMenuBarImage(imgLight, at: NSPoint(x: lightBar.minX + 8, y: lightBar.minY + 2), templateTint: NSColor(calibratedWhite: 0.08, alpha: 1.0))

                let hotBar = NSRect(x: 516, y: y + 1, width: 164, height: 26)
                NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.16, alpha: 1.0).setFill()
                NSBezierPath(roundedRect: hotBar, xRadius: 6, yRadius: 6).fill()
                settings.showMenuNetwork = false
                let imgHot = MenuBarImageRenderer.render(data: hotData, settings: settings, appearance: darkApp)
                drawPreviewMenuBarImage(imgHot, at: NSPoint(x: hotBar.minX + 8, y: hotBar.minY + 2), templateTint: .white)
                settings.showMenuNetwork = true
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private static func drawPreviewMenuBarImage(_ img: NSImage, at origin: NSPoint, templateTint: NSColor) {
        let rect = NSRect(origin: origin, size: img.size)
        if img.isTemplate {
            let tinted = NSImage(size: img.size)
            tinted.lockFocus()
            img.draw(in: NSRect(origin: .zero, size: img.size))
            templateTint.set()
            NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        } else {
            img.draw(in: rect)
        }
    }
}
