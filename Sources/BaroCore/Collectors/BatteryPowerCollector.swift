import Foundation
import IOKit

public final class BatteryPowerCollector: @unchecked Sendable {
    public init() {}

    public func sample() -> BatteryPowerSnapshot {
        let peripherals = readHIDPeripherals()
        if let battery = readInternalSmartBattery(peripherals: peripherals) {
            return battery
        }
        return BatteryPowerSnapshot(
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
            peripherals: peripherals
        )
    }

    /// 解析 AppleSmartBattery 属性字典（抽离为纯函数便于单元测试）
    public static func parseSmartBatteryProperties(
        _ props: [String: Any],
        peripherals: [HIDPeripheralBattery] = []
    ) -> BatteryPowerSnapshot {
        let batteryInstalled = (props["BatteryInstalled"] as? Bool) ?? true
        let currentCap = (props["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0
        let maxCap = (props["MaxCapacity"] as? NSNumber)?.doubleValue ?? 0
        let appleRawCurrent = (props["AppleRawCurrentCapacity"] as? NSNumber)?.doubleValue
        let appleRawMax = (props["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        let designCap = (props["DesignCapacity"] as? NSNumber)?.doubleValue ?? 0

        let telemetryPowerWatts: Double = {
            if let telemetry = props["PowerTelemetryData"] as? [String: Any],
               let sysPowerInMW = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue,
               sysPowerInMW > 0 {
                return sysPowerInMW / 1_000.0
            }
            return 0
        }()

        // 台式机（如 Mac mini）也可能注册 AppleSmartBattery 节点，但 BatteryInstalled = false 且容量为 0
        if !batteryInstalled || (maxCap <= 0 && (appleRawMax ?? 0) <= 0) {
            return BatteryPowerSnapshot(
                hasInternalBattery: false,
                chargePercent: 0,
                isCharging: false,
                isPluggedIn: true,
                powerWatts: telemetryPowerWatts,
                healthPercent: 100,
                cycleCount: 0,
                temperatureCelsius: nil,
                timeRemainingMinutes: nil,
                adapterWatts: nil,
                powerSource: .acPower,
                peripherals: peripherals
            )
        }

        let chargePercent: Double
        if let rawCur = appleRawCurrent, let rawMax = appleRawMax, rawMax > 0 {
            chargePercent = min(100, max(0, rawCur / rawMax * 100.0))
        } else if maxCap > 0 {
            chargePercent = min(100, max(0, currentCap / maxCap * 100.0))
        } else {
            chargePercent = min(100, max(0, currentCap))
        }

        let healthPercent: Double
        if let rawMax = appleRawMax, designCap > 0 {
            healthPercent = min(100, max(0, rawMax / designCap * 100.0))
        } else if designCap > 0, maxCap > 100 {
            healthPercent = min(100, max(0, maxCap / designCap * 100.0))
        } else {
            healthPercent = 100
        }

        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        let cycleCount = (props["CycleCount"] as? NSNumber)?.intValue ?? 0

        let voltageMV = (props["Voltage"] as? NSNumber)?.doubleValue ?? 0
        let rawAmperage = (props["InstantAmperage"] as? NSNumber)?.int64Value ?? 0
        let powerWatts = (voltageMV * Double(rawAmperage)) / 1_000_000.0

        let tempRaw = (props["Temperature"] as? NSNumber)?.doubleValue
        let tempC = tempRaw.map { $0 / 100.0 }

        var timeRemaining: Int?
        if let mins = (props["TimeRemaining"] as? NSNumber)?.intValue, mins > 0, mins < 6000 {
            timeRemaining = mins
        }

        var adapterWatts: Int?
        if let adapter = props["AdapterDetails"] as? [String: Any],
           let watts = (adapter["Watts"] as? NSNumber)?.intValue, watts > 0 {
            adapterWatts = watts
        }

        let sourceKind: PowerSourceKind = externalConnected ? .powerAdapter : .internalBattery

        return BatteryPowerSnapshot(
            hasInternalBattery: true,
            chargePercent: chargePercent,
            isCharging: isCharging,
            isPluggedIn: externalConnected,
            powerWatts: powerWatts,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            temperatureCelsius: tempC,
            timeRemainingMinutes: timeRemaining,
            adapterWatts: adapterWatts,
            powerSource: sourceKind,
            peripherals: peripherals
        )
    }

    private func readInternalSmartBattery(peripherals: [HIDPeripheralBattery]) -> BatteryPowerSnapshot? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsUnmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return Self.parseSmartBatteryProperties(props, peripherals: peripherals)
    }

    /// 免蓝牙弹窗读取苹果蓝牙外设电量
    private func readHIDPeripherals() -> [HIDPeripheralBattery] {
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else {
            return []
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var list: [HIDPeripheralBattery] = []
        var seen = Set<String>()

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let batteryObj = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let percent = (batteryObj as? NSNumber)?.intValue else {
                continue
            }
            let product = (IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? "Apple HID"
            let key = "\(product)-\(percent)"
            if !seen.contains(key) {
                seen.insert(key)
                list.append(HIDPeripheralBattery(name: product, percent: max(0, min(100, percent))))
            }
        }
        return list
    }
}
