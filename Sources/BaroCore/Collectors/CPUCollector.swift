import Darwin
import Foundation

public final class CPUCollector: @unchecked Sendable {
    private struct CoreTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    private let lock = NSLock()
    private var previousTicks: [CoreTicks] = []
    private let pCoreCount: Int
    private let eCoreCount: Int

    public init() {
        self.pCoreCount = Int(HostInfoReader.sysctlInt32("hw.perflevel0.logicalcpu") ?? 0)
        self.eCoreCount = Int(HostInfoReader.sysctlInt32("hw.perflevel1.logicalcpu") ?? 0)
    }

    public func resetBaseline() {
        lock.lock()
        previousTicks.removeAll()
        lock.unlock()
    }

    public func sample() -> CPUSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
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
        var currentTicks: [CoreTicks] = []
        currentTicks.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(bitPattern: Int64(info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(bitPattern: Int64(info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(bitPattern: Int64(info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(bitPattern: Int64(info[base + Int(CPU_STATE_NICE)]))
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
            let prev = previousTicks[i]
            let curr = currentTicks[i]

            let dUser = curr.user >= prev.user ? curr.user - prev.user : 0
            let dSys = curr.system >= prev.system ? curr.system - prev.system : 0
            let dIdle = curr.idle >= prev.idle ? curr.idle - prev.idle : 0
            let dNice = curr.nice >= prev.nice ? curr.nice - prev.nice : 0

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
        guard pCoreCount > 0, eCoreCount > 0, (pCoreCount + eCoreCount) == totalCores else {
            return .unknown
        }
        // Apple Silicon host_processor_info 先报告能效核（E-Core），再报告性能核（P-Core）
        return index < eCoreCount ? .efficiency : .performance
    }

    private func readLoadAverages() -> (Double, Double, Double) {
        var avgs = [Double](repeating: 0, count: 3)
        let count = getloadavg(&avgs, 3)
        guard count == 3 else { return (0, 0, 0) }
        return (avgs[0], avgs[1], avgs[2])
    }
}
