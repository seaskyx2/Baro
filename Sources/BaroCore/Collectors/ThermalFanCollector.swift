import Darwin
import Foundation
import IOKit

/// 纯只读温度与风扇采集器：
/// 1. 优先通过 IOHIDEventSystemClient 读取 Apple Silicon 温度传感器（带 M4 休眠核异常值滤波）
/// 2. 通过只读 AppleSMC 接口读取风扇 RPM 及温度键补充/兜底（绝不包含任何写入命令）
public final class ThermalFanCollector: @unchecked Sendable {
    private typealias IOHIDEventSystemClientRef = UnsafeMutableRawPointer
    private typealias IOHIDServiceClientRef = UnsafeMutableRawPointer
    private typealias IOHIDEventRef = UnsafeMutableRawPointer

    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> IOHIDEventSystemClientRef?
    private typealias ClientSetMatchingFn = @convention(c) (IOHIDEventSystemClientRef, CFDictionary) -> Int32
    private typealias ClientCopyServicesFn = @convention(c) (IOHIDEventSystemClientRef) -> Unmanaged<CFArray>?
    private typealias ServiceCopyPropertyFn = @convention(c) (IOHIDServiceClientRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEventFn = @convention(c) (IOHIDServiceClientRef, Int64, Int32, Int64) -> IOHIDEventRef?
    private typealias EventGetFloatValueFn = @convention(c) (IOHIDEventRef, UInt32) -> Double

    private let lock = NSLock()
    private var iokitHandle: UnsafeMutableRawPointer?
    private var hidClient: IOHIDEventSystemClientRef?

    private var clientCopyServices: ClientCopyServicesFn?
    private var serviceCopyProperty: ServiceCopyPropertyFn?
    private var serviceCopyEvent: ServiceCopyEventFn?
    private var eventGetFloatValue: EventGetFloatValueFn?

    private let smcReader = ReadOnlySMCClient()

    public init() {
        setupHIDTemperatureClient()
    }

    deinit {
        if let client = hidClient {
            Unmanaged<AnyObject>.fromOpaque(client).release()
        }
        if let handle = iokitHandle {
            dlclose(handle)
        }
    }

    public func readSystemPowerWatts() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return smcReader.readSystemPowerWatts()
    }

    public func sample() -> ThermalFanSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var allSensors = readHIDTemperatures()
        let smcSensors = smcReader.readKnownTemperatureKeys()
        for sensor in smcSensors where !allSensors.contains(where: { $0.name == sensor.name }) {
            allSensors.append(sensor)
        }

        let validSensors = Self.filterValidThermalReadings(allSensors)
        let fans = smcReader.readFans()

        let cpuTemp = averageMatching(validSensors, keywords: ["PMU tdie", "eACC", "pACC", "Tp0", "CPU"])
        let gpuTemp = averageMatching(validSensors, keywords: ["GPU", "Tg0"])
        let ssdTemp = averageMatching(validSensors, keywords: ["NAND", "SSD", "TH0"])
        let socTemp = averageMatching(validSensors, keywords: ["SOC MTR", "PMU tdie", "Ts0", "Tp0"]) ?? validSensors.map(\.celsius).max()

        return ThermalFanSnapshot(
            socTemperature: socTemp,
            cpuTemperature: cpuTemp,
            gpuTemperature: gpuTemp,
            ssdTemperature: ssdTemp,
            sensors: validSensors.sorted { $0.celsius > $1.celsius },
            fans: fans
        )
    }

    /// 过滤 Apple Silicon（含 M4）休眠核或损坏传感器产生的 <=1°C 或 >125°C 异常读数
    public static func filterValidThermalReadings(_ readings: [ThermalSensorReading]) -> [ThermalSensorReading] {
        readings.filter { $0.celsius > 1.0 && $0.celsius <= 125.0 && $0.celsius.isFinite }
    }

    private func averageMatching(_ sensors: [ThermalSensorReading], keywords: [String]) -> Double? {
        let matched = sensors.filter { sensor in
            let upper = sensor.name.uppercased()
            return keywords.contains { upper.contains($0.uppercased()) }
        }
        guard !matched.isEmpty else { return nil }
        return matched.map(\.celsius).reduce(0, +) / Double(matched.count)
    }

    private func setupHIDTemperatureClient() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL) else {
            return
        }
        self.iokitHandle = handle

        func resolve<T>(_ symbol: String, as type: T.Type) -> T? {
            guard let sym = dlsym(handle, symbol) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        guard let createFn = resolve("IOHIDEventSystemClientCreate", as: ClientCreateFn.self),
              let matchFn = resolve("IOHIDEventSystemClientSetMatching", as: ClientSetMatchingFn.self),
              let copyServicesFn = resolve("IOHIDEventSystemClientCopyServices", as: ClientCopyServicesFn.self),
              let copyPropFn = resolve("IOHIDServiceClientCopyProperty", as: ServiceCopyPropertyFn.self),
              let copyEventFn = resolve("IOHIDServiceClientCopyEvent", as: ServiceCopyEventFn.self),
              let getFloatFn = resolve("IOHIDEventGetFloatValue", as: EventGetFloatValueFn.self) else {
            return
        }

        guard let client = createFn(kCFAllocatorDefault) else { return }
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 0x05
        ]
        _ = matchFn(client, matching as CFDictionary)

        self.hidClient = client
        self.clientCopyServices = copyServicesFn
        self.serviceCopyProperty = copyPropFn
        self.serviceCopyEvent = copyEventFn
        self.eventGetFloatValue = getFloatFn
    }

    private func readHIDTemperatures() -> [ThermalSensorReading] {
        guard let client = hidClient,
              let copyServices = clientCopyServices,
              let copyProp = serviceCopyProperty,
              let copyEvent = serviceCopyEvent,
              let getFloat = eventGetFloatValue else {
            return []
        }

        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return []
        }

        var readings: [ThermalSensorReading] = []
        let temperatureEventType: Int64 = 15
        let temperatureField: UInt32 = UInt32(temperatureEventType << 16)

        for serviceObj in services {
            let service = Unmanaged.passUnretained(serviceObj).toOpaque()
            guard let name = copyProp(service, "Product" as CFString)?.takeRetainedValue() as? String else {
                continue
            }
            guard let event = copyEvent(service, temperatureEventType, 0, 0) else {
                continue
            }
            let celsius = getFloat(event, temperatureField)
            Unmanaged<AnyObject>.fromOpaque(event).release()

            readings.append(ThermalSensorReading(name: name, celsius: celsius, source: "HID"))
        }

        return readings
    }
}

// MARK: - Read-Only AppleSMC Client

/// 仅封装只读 SMC 查询指令（kSMCReadKey = 5, kSMCGetKeyInfo = 9），绝不开放任何写入接口
public final class ReadOnlySMCClient: @unchecked Sendable {
    public struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    public struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    public struct SMCKeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        private var _pad0: UInt8 = 0
        private var _pad1: UInt16 = 0
    }

    public typealias SMCBytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    public struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        private var _padVers: UInt16 = 0
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        private var _padData8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes32 = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCReadKeyCmd: UInt8 = 5
    private let kSMCGetKeyInfoCmd: UInt8 = 9

    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfo] = [:]

    private static let candidateTemperatureKeys: [(key: String, label: String)] = [
        ("Tp01", "CPU P-Core 1"),
        ("Tp05", "CPU P-Core 2"),
        ("Tp09", "CPU E-Core 1"),
        ("Tp0D", "CPU E-Core 2"),
        ("Tp0f", "CPU Die"),
        ("Tg05", "GPU 1"),
        ("Tg0D", "GPU 2"),
        ("Tg0f", "GPU Die"),
        ("Ts0P", "SoC Palm"),
        ("Te05", "ANE / SoC"),
        ("TH0a", "SSD NAND A"),
        ("TH0b", "SSD NAND B")
    ]

    public init() {
        openConnection()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func readFans() -> [FanReading] {
        guard connection != 0, let countVal = readNumericValue(forKey: "FNum") else {
            return []
        }
        let fanCount = Int(countVal.rounded())
        guard fanCount > 0, fanCount <= 8 else { return [] }

        var fans: [FanReading] = []
        for idx in 0..<fanCount {
            let current = Int((readNumericValue(forKey: "F\(idx)Ac") ?? 0).rounded())
            let minRPM = Int((readNumericValue(forKey: "F\(idx)Mn") ?? 0).rounded())
            let maxRPM = Int((readNumericValue(forKey: "F\(idx)Mx") ?? 0).rounded())
            fans.append(FanReading(id: idx, currentRPM: max(0, current), minRPM: max(0, minRPM), maxRPM: max(0, maxRPM)))
        }
        return fans
    }

    public func readSystemPowerWatts() -> Double? {
        guard connection != 0 else { return nil }
        for key in ["PSTR", "PHPC", "PDTR"] {
            if let value = readNumericValue(forKey: key), value > 0.1 && value < 500.0 {
                return value
            }
        }
        return nil
    }

    public func readKnownTemperatureKeys() -> [ThermalSensorReading] {
        guard connection != 0 else { return [] }
        var readings: [ThermalSensorReading] = []
        for entry in Self.candidateTemperatureKeys {
            if let value = readNumericValue(forKey: entry.key), value > 1.0 && value <= 125.0 {
                readings.append(ThermalSensorReading(name: entry.label, celsius: value, source: "SMC"))
            }
        }
        return readings
    }

    public static func decodeSMCValue(bytes: [UInt8], dataType: UInt32, dataSize: UInt32) -> Double? {
        let typeStr = fourCCToString(dataType)
        switch typeStr {
        case "flt ":
            guard dataSize >= 4, bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: raw))
        case "fpe2":
            guard dataSize >= 2, bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78":
            guard dataSize >= 2, bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "ui8 ":
            guard dataSize >= 1, bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard dataSize >= 2, bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32":
            guard dataSize >= 4, bytes.count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return Double(raw)
        default:
            return nil
        }
    }

    private func openConnection() {
        guard let matching = IOServiceMatching("AppleSMC") else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        if IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS {
            self.connection = conn
        }
    }

    private func readNumericValue(forKey keyStr: String) -> Double? {
        guard let keyCode = stringToFourCC(keyStr) else { return nil }
        guard let info = readKeyInfo(forKeyCode: keyCode), info.dataSize > 0 else { return nil }

        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = info.dataSize
        input.data8 = kSMCReadKeyCmd

        var output = SMCKeyData()
        guard callSMC(input: &input, output: &output), output.result == 0 else {
            return nil
        }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0) }
        return Self.decodeSMCValue(bytes: bytes, dataType: info.dataType, dataSize: info.dataSize)
    }

    private func readKeyInfo(forKeyCode keyCode: UInt32) -> SMCKeyInfo? {
        if let cached = keyInfoCache[keyCode] {
            return cached
        }
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = kSMCGetKeyInfoCmd

        var output = SMCKeyData()
        guard callSMC(input: &input, output: &output), output.result == 0 else {
            return nil
        }
        keyInfoCache[keyCode] = output.keyInfo
        return output.keyInfo
    }

    private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        guard connection != 0 else { return false }
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            inputSize,
            &output,
            &outputSize
        )
        return kr == KERN_SUCCESS
    }

    private func stringToFourCC(_ str: String) -> UInt32? {
        let bytes = Array(str.utf8)
        guard bytes.count == 4 else { return nil }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }

    private static func fourCCToString(_ code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(decoding: chars, as: UTF8.self)
    }
}
