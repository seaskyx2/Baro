import CNVMeSmart
import Foundation
import IOKit

public final class DiskCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousIO: (readBytes: UInt64, writeBytes: UInt64, timestamp: Date)?
    private var lastSmartFetchAt: Date?
    private var cachedSmartSnapshot: NVMeSmartSnapshot?

    public init() {}

    public func resetBaseline() {
        lock.lock()
        previousIO = nil
        lastSmartFetchAt = nil
        lock.unlock()
    }

    public func sample() -> DiskSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let volumes = readVolumes()
        let (totalRead, totalWrite) = readBlockStorageBytes()
        let now = Date()

        var readRate = 0.0
        var writeRate = 0.0

        if let prev = previousIO {
            let dt = now.timeIntervalSince(prev.timestamp)
            if dt > 0.05 && dt < 30.0 {
                if totalRead >= prev.readBytes {
                    readRate = Double(totalRead - prev.readBytes) / dt
                }
                if totalWrite >= prev.writeBytes {
                    writeRate = Double(totalWrite - prev.writeBytes) / dt
                }
            }
        }
        previousIO = (totalRead, totalWrite, now)

        let smart = readSmartWithThrottle(now: now)

        return DiskSnapshot(
            readBytesPerSec: readRate,
            writeBytesPerSec: writeRate,
            volumes: volumes,
            smart: smart
        )
    }

    private func readSmartWithThrottle(now: Date) -> NVMeSmartSnapshot? {
        if let last = lastSmartFetchAt, now.timeIntervalSince(last) < 60.0 {
            return cachedSmartSnapshot
        }
        var raw = BaroNVMeSmartReading()
        let ok = baro_read_nvme_smart(&raw)
        lastSmartFetchAt = now
        if ok && raw.available {
            let parsed = Self.convertNVMeReading(
                percentageUsed: raw.percentageUsed,
                availableSpare: raw.availableSpare,
                temperatureCelsius: raw.temperatureCelsius,
                dataUnitsReadLow: raw.dataUnitsReadLow,
                dataUnitsWrittenLow: raw.dataUnitsWrittenLow,
                powerOnHours: raw.powerOnHours,
                powerCycles: raw.powerCycles
            )
            cachedSmartSnapshot = parsed
            return parsed
        }
        return cachedSmartSnapshot
    }

    /// 按 NVMe 规范（1 data unit = 1000 × 512 = 512,000 bytes）换算读写总量与剩余健康度
    public static func convertNVMeReading(
        percentageUsed: UInt8,
        availableSpare: UInt8,
        temperatureCelsius: Int32,
        dataUnitsReadLow: UInt64,
        dataUnitsWrittenLow: UInt64,
        powerOnHours: UInt64,
        powerCycles: UInt64
    ) -> NVMeSmartSnapshot {
        let pctUsed = Int(percentageUsed)
        let health = max(0, min(100, 100 - pctUsed))
        let unitSize: UInt64 = 512_000
        let written = dataUnitsWrittenLow.multipliedReportingOverflow(by: unitSize).overflow
            ? UInt64.max
            : dataUnitsWrittenLow * unitSize
        let read = dataUnitsReadLow.multipliedReportingOverflow(by: unitSize).overflow
            ? UInt64.max
            : dataUnitsReadLow * unitSize
        let temp: Int? = (temperatureCelsius > 0 && temperatureCelsius < 120) ? Int(temperatureCelsius) : nil

        return NVMeSmartSnapshot(
            isAvailable: true,
            healthPercent: health,
            percentageUsed: pctUsed,
            availableSparePercent: Int(availableSpare),
            temperatureCelsius: temp,
            totalBytesWritten: written,
            totalBytesRead: read,
            powerOnHours: powerOnHours,
            powerCycles: powerCycles
        )
    }

    private func readVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var seenKeys = Set<String>()
        var result: [DiskVolume] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.path
            if path.hasPrefix("/System/Volumes/") && path != "/System/Volumes/Data" {
                continue
            }
            guard let total = values.volumeTotalCapacity, total > 0 else { continue }
            let availableInt64 = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            let available = UInt64(max(0, availableInt64))
            let name = values.volumeName ?? url.lastPathComponent
            let isInternal = values.volumeIsInternal ?? false

            let dedupKey = "\(name)-\(total)"
            if seenKeys.contains(dedupKey) {
                continue
            }
            seenKeys.insert(dedupKey)

            result.append(
                DiskVolume(
                    name: name,
                    mountPath: path,
                    totalBytes: UInt64(total),
                    availableBytes: available,
                    isInternal: isInternal
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.mountPath == "/" { return true }
            if rhs.mountPath == "/" { return false }
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal && !rhs.isInternal }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    private func readBlockStorageBytes() -> (read: UInt64, write: UInt64) {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return (0, 0)
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let prop = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let readVal = (prop["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totalRead += readVal
                }
                if let writeVal = (prop["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totalWrite += writeVal
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return (totalRead, totalWrite)
    }
}
