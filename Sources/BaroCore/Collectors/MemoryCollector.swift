import Darwin
import Foundation

public final class MemoryCollector: @unchecked Sendable {
    private let totalMemoryBytes: UInt64
    private let pageSize: UInt64

    public init() {
        self.totalMemoryBytes = HostInfoReader.sysctlUInt64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        var pageSizeValue: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeValue)
        self.pageSize = UInt64(pageSizeValue > 0 ? pageSizeValue : 16_384)
    }

    public func sample() -> MemorySnapshot {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let kr = withUnsafeMutablePointer(to: &vmStats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return .empty
        }

        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let appPages = internalPages >= purgeablePages ? (internalPages - purgeablePages) : 0

        let appBytes = appPages * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let externalBytes = UInt64(vmStats.external_page_count) * pageSize
        let cachedFilesBytes = externalBytes + purgeablePages * pageSize

        let rawUsed = appBytes + wiredBytes + compressedBytes
        let usedBytes = min(totalMemoryBytes, rawUsed)
        let freeBytes = totalMemoryBytes >= usedBytes ? (totalMemoryBytes - usedBytes) : 0

        let swap = readSwapUsage()
        let pressure = readMemoryPressure()

        return MemorySnapshot(
            totalBytes: totalMemoryBytes,
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedFilesBytes: cachedFilesBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: pressure
        )
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (swap.xsu_used, swap.xsu_total)
    }

    private func readMemoryPressure() -> MemoryPressureLevel {
        if let raw = HostInfoReader.sysctlInt32("kern.memorystatus_vm_pressure_level") {
            switch raw {
            case 4: return .critical
            case 2: return .warning
            default: return .normal
            }
        }
        return .normal
    }
}
