import Darwin
import Foundation
import IOKit

public final class CPUCollector: @unchecked Sendable {
    public struct CoreTicks: Sendable, Equatable {
        public let user: UInt32
        public let system: UInt32
        public let idle: UInt32
        public let nice: UInt32

        public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    private let lock = NSLock()
    private var previousTicks: [CoreTicks] = []
    private let pCoreCount: Int
    private let eCoreCount: Int
    private let ioRegistryCoreMap: [Int: CoreKind]

    public init() {
        self.pCoreCount = Int(HostInfoReader.sysctlInt32("hw.perflevel0.logicalcpu") ?? 0)
        self.eCoreCount = Int(HostInfoReader.sysctlInt32("hw.perflevel1.logicalcpu") ?? 0)
        self.ioRegistryCoreMap = Self.readIORegistryCoreKinds()
    }

    public func resetBaseline() {
        lock.lock()
        previousTicks.removeAll()
        lock.unlock()
    }

    /// 32 位无符号 CPU tick 差分（兼容跨 `2^31` 符号位翻转与 `2^32` 计数器自然回绕，杜绝有符号扩展溢出）
    public static func computeCoreTickDelta(
        current: CoreTicks,
        previous: CoreTicks
    ) -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        (
            user: UInt64(current.user &- previous.user),
            system: UInt64(current.system &- previous.system),
            idle: UInt64(current.idle &- previous.idle),
            nice: UInt64(current.nice &- previous.nice)
        )
    }

    public func sample() -> CPUSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            HostInfoReader.machHostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return .empty
        }

        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), byteCount)
        }

        let coreCount = Int(numCPUs)
        let stridePerCore = Int(CPU_STATE_MAX)
        guard coreCount > 0, Int(numCPUInfo) >= coreCount * stridePerCore else {
            return .empty
        }

        var currentTicks: [CoreTicks] = []
        currentTicks.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let base = i * stridePerCore
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            currentTicks.append(CoreTicks(user: user, system: system, idle: idle, nice: nice))
        }

        let loadAverages = readLoadAverages()

        guard previousTicks.count == currentTicks.count else {
            previousTicks = currentTicks
            let cores = (0..<coreCount).map { idx in
                CoreLoad(id: idx, kind: coreKind(for: idx, totalCores: coreCount), usagePercent: 0)
            }
            return CPUSnapshot(
                totalUsagePercent: 0,
                userPercent: 0,
                systemPercent: 0,
                pCoreUsagePercent: 0,
                eCoreUsagePercent: 0,
                pCoreCount: pCoreCount,
                eCoreCount: eCoreCount,
                totalCoreCount: coreCount,
                perCoreLoads: cores,
                loadAverage1m: loadAverages.0,
                loadAverage5m: loadAverages.1,
                loadAverage15m: loadAverages.2
            )
        }

        var sumUser: UInt64 = 0
        var sumSystem: UInt64 = 0
        var sumTotal: UInt64 = 0

        var pActive: UInt64 = 0
        var pTotal: UInt64 = 0
        var eActive: UInt64 = 0
        var eTotal: UInt64 = 0

        var perCoreLoads: [CoreLoad] = []
        perCoreLoads.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let delta = Self.computeCoreTickDelta(current: currentTicks[i], previous: previousTicks[i])
            let dUser = delta.user
            let dSys = delta.system
            let dIdle = delta.idle
            let dNice = delta.nice

            let active = dUser + dSys + dNice
            let total = active + dIdle
            let pct = total > 0 ? min(100.0, Double(active) / Double(total) * 100.0) : 0.0

            sumUser += dUser + dNice
            sumSystem += dSys
            sumTotal += total

            let kind = coreKind(for: i, totalCores: coreCount)
            switch kind {
            case .performance:
                pActive += active
                pTotal += total
            case .efficiency:
                eActive += active
                eTotal += total
            case .unknown:
                break
            }

            perCoreLoads.append(CoreLoad(id: i, kind: kind, usagePercent: pct))
        }

        previousTicks = currentTicks

        let totalUsage = sumTotal > 0 ? min(100.0, Double(sumUser + sumSystem) / Double(sumTotal) * 100.0) : 0.0
        let userPct = sumTotal > 0 ? min(100.0, Double(sumUser) / Double(sumTotal) * 100.0) : 0.0
        let systemPct = sumTotal > 0 ? min(100.0, Double(sumSystem) / Double(sumTotal) * 100.0) : 0.0
        let pUsage = pTotal > 0 ? min(100.0, Double(pActive) / Double(pTotal) * 100.0) : 0.0
        let eUsage = eTotal > 0 ? min(100.0, Double(eActive) / Double(eTotal) * 100.0) : 0.0

        return CPUSnapshot(
            totalUsagePercent: totalUsage,
            userPercent: userPct,
            systemPercent: systemPct,
            pCoreUsagePercent: pUsage,
            eCoreUsagePercent: eUsage,
            pCoreCount: pCoreCount,
            eCoreCount: eCoreCount,
            totalCoreCount: coreCount,
            perCoreLoads: perCoreLoads,
            loadAverage1m: loadAverages.0,
            loadAverage5m: loadAverages.1,
            loadAverage15m: loadAverages.2
        )
    }

    private func coreKind(for index: Int, totalCores: Int) -> CoreKind {
        if let mapped = ioRegistryCoreMap[index], mapped != .unknown {
            return mapped
        }
        guard pCoreCount > 0, eCoreCount > 0, (pCoreCount + eCoreCount) == totalCores else {
            return .unknown
        }
        return index < eCoreCount ? .efficiency : .performance
    }

    /// 从 IORegistry 读取每个逻辑核心真实的 `cluster-type`（兼容未来多 Die 交错核心编号）
    public static func readIORegistryCoreKinds() -> [Int: CoreKind] {
        guard let matching = IOServiceMatching("IOPlatformDevice") else { return [:] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var map: [Int: CoreKind] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let clusterObj = IORegistryEntryCreateCFProperty(service, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
                continue
            }
            let kind = parseClusterType(clusterObj)
            guard kind != .unknown else { continue }

            let idObj = IORegistryEntryCreateCFProperty(service, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                ?? IORegistryEntryCreateCFProperty(service, "cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            if let coreIndex = parseLogicalCPUIndex(idObj), coreIndex >= 0 {
                map[coreIndex] = kind
            }
        }
        return map
    }

    public static func parseClusterType(_ raw: Any?) -> CoreKind {
        let text: String
        if let str = raw as? String {
            text = str
        } else if let data = raw as? Data {
            let trimmed = data.prefix { $0 != 0 }
            text = String(decoding: trimmed, as: UTF8.self)
        } else {
            return .unknown
        }
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.hasPrefix("E") { return .efficiency }
        if upper.hasPrefix("P") || upper.hasPrefix("M") { return .performance }
        return .unknown
    }

    public static func parseLogicalCPUIndex(_ raw: Any?) -> Int? {
        if let num = raw as? NSNumber {
            return num.intValue
        }
        if let data = raw as? Data, data.count >= 4 {
            let val = data.withUnsafeBytes { buf -> UInt32 in
                buf.loadUnaligned(as: UInt32.self)
            }
            return Int(UInt32(littleEndian: val))
        }
        return nil
    }

    private func readLoadAverages() -> (Double, Double, Double) {
        var avgs = [Double](repeating: 0, count: 3)
        let count = getloadavg(&avgs, 3)
        guard count == 3 else { return (0, 0, 0) }
        return (avgs[0], avgs[1], avgs[2])
    }
}
