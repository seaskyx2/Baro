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

    /// 回归：冷态不得沿用上一次热态的进程排行
    func testColdSampleDropsStaleTopApps() {
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
            200: [["AssertType": "PreventUserIdleDisplaySleep", "Process Name": "CaffeineApp"]],
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
        settings.showMenuNetwork = true
        settings.showMenuTemperature = true
        settings.showMenuPower = false

        let calmData = MenuBarRenderData(
            cpuPercent: 18,
            memoryPercent: 64,
            memoryPressure: .normal,
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

                let hotBar = NSRect(x: 516, y: y + 1, width: 148, height: 26)
                NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.16, alpha: 1.0).setFill()
                NSBezierPath(roundedRect: hotBar, xRadius: 6, yRadius: 6).fill()
                settings.showMenuNetwork = false
                settings.showMenuTemperature = false
                let imgHot = MenuBarImageRenderer.render(data: hotData, settings: settings, appearance: darkApp)
                drawPreviewMenuBarImage(imgHot, at: NSPoint(x: hotBar.minX + 8, y: hotBar.minY + 2), templateTint: .white)
                settings.showMenuNetwork = true
                settings.showMenuTemperature = true
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
