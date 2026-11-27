import XCTest
@testable import BaroCore

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

    func testSMCStructLayoutAndDecoders() {
        XCTAssertEqual(MemoryLayout<ReadOnlySMCClient.SMCKeyData>.stride, 80)

        let floatVal: Float = 1234.5
        let floatBytes = withUnsafeBytes(of: floatVal.bitPattern.littleEndian) { Array($0) }
        let fltCode = (UInt32(Character("f").asciiValue!) << 24)
            | (UInt32(Character("l").asciiValue!) << 16)
            | (UInt32(Character("t").asciiValue!) << 8)
            | UInt32(Character(" ").asciiValue!)
        let decodedFloat = ReadOnlySMCClient.decodeSMCValue(bytes: floatBytes, dataType: fltCode, dataSize: 4)
        XCTAssertEqual(decodedFloat ?? 0, 1234.5, accuracy: 0.1)

        // fpe2: 1200 RPM => 1200 * 4 = 4800 = 0x12C0
        let fpe2Code = (UInt32(Character("f").asciiValue!) << 24)
            | (UInt32(Character("p").asciiValue!) << 16)
            | (UInt32(Character("e").asciiValue!) << 8)
            | UInt32(Character("2").asciiValue!)
        let decodedFpe2 = ReadOnlySMCClient.decodeSMCValue(bytes: [0x12, 0xC0], dataType: fpe2Code, dataSize: 2)
        XCTAssertEqual(decodedFpe2 ?? 0, 1200.0, accuracy: 0.01)
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

        let desktopProps: [String: Any] = [
            "BatteryInstalled": false,
            "MaxCapacity": 0,
            "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 22769]
        ]
        let desktopParsed = BatteryPowerCollector.parseSmartBatteryProperties(desktopProps)
        XCTAssertFalse(desktopParsed.hasInternalBattery)
        XCTAssertTrue(desktopParsed.isPluggedIn)
        XCTAssertEqual(desktopParsed.powerWatts, 22.769, accuracy: 0.01)
    }

    func testHealthAnalyzerDiagnosis() {
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
        let elevated = HealthAnalyzer.analyze(snapshot: snap, topCPUApp: xcode)
        XCTAssertEqual(elevated.level, .elevated)
        XCTAssertTrue(elevated.message.contains("Xcode"))

        let elevatedEn = HealthAnalyzer.analyze(snapshot: snap, topCPUApp: xcode, language: .en)
        XCTAssertEqual(elevatedEn.level, .elevated)
        XCTAssertTrue(elevatedEn.message.contains("Xcode"))
        XCTAssertTrue(elevatedEn.message.contains("High Load"))
    }

    func testLocalizationResolutionAndProcessCollectorCache() {
        XCTAssertEqual(BaroL10n.resolve(.zhHans, preferredLanguages: ["en-US"]), .zhHans)
        XCTAssertEqual(BaroL10n.resolve(.en, preferredLanguages: ["zh-Hans-CN"]), .en)
        XCTAssertEqual(BaroL10n.resolve(.system, preferredLanguages: ["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(BaroL10n.resolve(.system, preferredLanguages: ["en-US"]), .en)
        XCTAssertEqual(MenuBarStyle.allCases.count, 5)
        XCTAssertEqual(MenuBarDensity.allCases.count, 3)
        XCTAssertEqual(BaroL10n.menuBarStyleTitle(.miniBars, lang: .zhHans), "双柱仪表")
        XCTAssertEqual(BaroL10n.menuBarDensityTitle(.compact, lang: .en), "Compact")

        let collector = ProcessAggregatorCollector()
        _ = collector.sample(limit: 5)
        let second = collector.sample(limit: 5)
        XCTAssertFalse(second.topMemory.isEmpty)
    }
}
