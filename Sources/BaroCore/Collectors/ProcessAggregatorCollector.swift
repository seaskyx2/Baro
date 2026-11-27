import Darwin
import Foundation

public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let startAbstime: UInt64

    public init(pid: Int32, startAbstime: UInt64) {
        self.pid = pid
        self.startAbstime = startAbstime
    }
}

public struct RawProcessSample: Sendable, Equatable {
    public let pid: Int32
    public let executablePath: String
    public let fallbackName: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(
        pid: Int32,
        executablePath: String,
        fallbackName: String,
        cpuPercent: Double,
        memoryBytes: UInt64
    ) {
        self.pid = pid
        self.executablePath = executablePath
        self.fallbackName = fallbackName
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

/// 仅在下拉面板展开（热态）或灵动圆环高压检测时触发：
/// 采用 `(pid, startAbstime)` 复合身份键缓存路径与 CPU 基线，既大幅压低扫描开销，又防止 PID 复用串号。
public final class ProcessAggregatorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPUNanosByIdentity: [ProcessIdentity: UInt64] = [:]
    private var previousTimestamp: Date?
    private var pathCacheByIdentity: [ProcessIdentity: (path: String, fallbackName: String)] = [:]
    private var bundleMetaCache: [String: (name: String, bundleId: String?)] = [:]
    private let timebaseNumer: UInt64
    private let timebaseDenom: UInt64

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.timebaseNumer = UInt64(info.numer > 0 ? info.numer : 1)
        self.timebaseDenom = UInt64(info.denom > 0 ? info.denom : 1)
    }

    public func resetBaseline() {
        lock.lock()
        previousCPUNanosByIdentity.removeAll()
        previousTimestamp = nil
        pathCacheByIdentity.removeAll()
        lock.unlock()
    }

    public func sample(limit: Int = 5) -> (topCPU: [AggregatedAppUsage], topMemory: [AggregatedAppUsage]) {
        lock.lock()
        defer { lock.unlock() }

        let pids = Self.listAllPIDs()
        guard !pids.isEmpty else {
            return ([], [])
        }

        let pidCount = pids.count
        let now = Date()
        let dtNanos: Double? = previousTimestamp.flatMap { prev in
            let dt = now.timeIntervalSince(prev)
            return (dt > 0.05 && dt < 30.0) ? (dt * 1_000_000_000.0) : nil
        }

        var nextCPUNanos: [ProcessIdentity: UInt64] = [:]
        nextCPUNanos.reserveCapacity(pidCount)

        var aliveIdentities = Set<ProcessIdentity>()
        aliveIdentities.reserveCapacity(pidCount)

        var rawSamples: [RawProcessSample] = []
        rawSamples.reserveCapacity(pidCount)

        for pid in pids {
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            let gotTask = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard gotTask == taskInfoSize else { continue }

            var rusage = rusage_info_v4()
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }

            let startTag: UInt64
            let memoryBytes: UInt64
            if rusageResult == 0 {
                startTag = rusage.ri_proc_start_abstime
                memoryBytes = rusage.ri_phys_footprint
            } else {
                startTag = readFallbackStartTime(pid: pid)
                memoryBytes = UInt64(taskInfo.pti_resident_size)
            }

            let identity = ProcessIdentity(pid: pid, startAbstime: startTag)
            aliveIdentities.insert(identity)

            let totalTicks = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            let totalNanos = (totalTicks / timebaseDenom) * timebaseNumer
                + ((totalTicks % timebaseDenom) * timebaseNumer) / timebaseDenom
            nextCPUNanos[identity] = totalNanos

            let cpuPercent = Self.computeCPUDeltaPercent(
                identity: identity,
                currentNanos: totalNanos,
                previousNanosByIdentity: previousCPUNanosByIdentity,
                dtNanos: dtNanos
            )

            let cachedInfo: (path: String, fallbackName: String)
            if let hit = pathCacheByIdentity[identity] {
                cachedInfo = hit
            } else {
                let path = readProcessPath(pid: pid)
                let fallback = path.isEmpty ? "PID \(pid)" : URL(fileURLWithPath: path).lastPathComponent
                let entry = (path: path, fallbackName: fallback)
                pathCacheByIdentity[identity] = entry
                cachedInfo = entry
            }

            rawSamples.append(
                RawProcessSample(
                    pid: pid,
                    executablePath: cachedInfo.path,
                    fallbackName: cachedInfo.fallbackName,
                    cpuPercent: cpuPercent,
                    memoryBytes: memoryBytes
                )
            )
        }

        // 淘汰已退出或已更换启动时间的进程缓存，保持内存零增长
        if pathCacheByIdentity.count > aliveIdentities.count + 32 {
            pathCacheByIdentity = pathCacheByIdentity.filter { aliveIdentities.contains($0.key) }
        }
        if bundleMetaCache.count > 256 {
            bundleMetaCache.removeAll()
        }

        previousCPUNanosByIdentity = nextCPUNanos
        previousTimestamp = now

        let aggregated = Self.aggregateProcesses(rawSamples) { appPath in
            if let cached = self.bundleMetaCache[appPath] {
                return cached
            }
            let resolved = Self.defaultBundleResolver(appPath)
            self.bundleMetaCache[appPath] = resolved
            return resolved
        }

        let topCPU = Array(aggregated.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let topMemory = Array(aggregated.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (topCPU, topMemory)
    }

    public static func computeCPUDeltaPercent(
        identity: ProcessIdentity,
        currentNanos: UInt64,
        previousNanosByIdentity: [ProcessIdentity: UInt64],
        dtNanos: Double?
    ) -> Double {
        guard let dtNanos, dtNanos > 0,
              let prevNanos = previousNanosByIdentity[identity],
              currentNanos >= prevNanos else {
            return 0.0
        }
        return Double(currentNanos - prevNanos) / dtNanos * 100.0
    }

    /// 列出全部 PID。注意：`proc_listallpids` 的返回值是「PID 个数」而非字节数
    /// （libproc 内部已将 `proc_listpids` 的字节数除以 sizeof(int)），不能再除以 stride。
    public static func listAllPIDs() -> [pid_t] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(estimated) + 128)
        let returnedCount = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        guard returnedCount > 0 else { return [] }
        return buffer.prefix(min(Int(returnedCount), buffer.count)).filter { $0 > 0 }
    }

    private func readFallbackStartTime(pid: Int32) -> UInt64 {
        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size) == size {
            return (bsdInfo.pbi_start_tvsec &* 1_000_000) &+ bsdInfo.pbi_start_tvusec
        }
        return 0
    }

    private func readProcessPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return "" }
        let bytes = buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 提取最外层 `.app` 路径，把内嵌在 Frameworks 中的 Helper/Renderer 进程统一归并到父级 App
    public static func outermostAppBundlePath(from executablePath: String) -> String? {
        guard !executablePath.isEmpty else { return nil }
        let marker = ".app/"
        if let range = executablePath.range(of: marker) {
            return String(executablePath[..<range.lowerBound]) + ".app"
        }
        if executablePath.hasSuffix(".app") {
            return executablePath
        }
        return nil
    }

    public static func aggregateProcesses(
        _ samples: [RawProcessSample],
        bundleInfoResolver: (String) -> (name: String, bundleId: String?) = defaultBundleResolver
    ) -> [AggregatedAppUsage] {
        struct Bucket {
            var id: String
            var name: String
            var bundleIdentifier: String?
            var appBundlePath: String?
            var cpuPercent: Double
            var memoryBytes: UInt64
            var pidsCount: Int
        }

        var buckets: [String: Bucket] = [:]

        for item in samples {
            if let appPath = outermostAppBundlePath(from: item.executablePath) {
                let info = bundleInfoResolver(appPath)
                let key = "app:\(appPath)"
                if var existing = buckets[key] {
                    existing.cpuPercent += item.cpuPercent
                    existing.memoryBytes += item.memoryBytes
                    existing.pidsCount += 1
                    buckets[key] = existing
                } else {
                    buckets[key] = Bucket(
                        id: key,
                        name: info.name,
                        bundleIdentifier: info.bundleId,
                        appBundlePath: appPath,
                        cpuPercent: item.cpuPercent,
                        memoryBytes: item.memoryBytes,
                        pidsCount: 1
                    )
                }
            } else {
                let procName = item.fallbackName.isEmpty ? "Unknown" : item.fallbackName
                let key = "proc:\(procName)"
                if var existing = buckets[key] {
                    existing.cpuPercent += item.cpuPercent
                    existing.memoryBytes += item.memoryBytes
                    existing.pidsCount += 1
                    buckets[key] = existing
                } else {
                    buckets[key] = Bucket(
                        id: key,
                        name: procName,
                        bundleIdentifier: nil,
                        appBundlePath: nil,
                        cpuPercent: item.cpuPercent,
                        memoryBytes: item.memoryBytes,
                        pidsCount: 1
                    )
                }
            }
        }

        return buckets.values.map {
            AggregatedAppUsage(
                id: $0.id,
                name: $0.name,
                bundleIdentifier: $0.bundleIdentifier,
                appBundlePath: $0.appBundlePath,
                cpuPercent: $0.cpuPercent,
                memoryBytes: $0.memoryBytes,
                pidsCount: $0.pidsCount
            )
        }
    }

    public static func defaultBundleResolver(_ appPath: String) -> (name: String, bundleId: String?) {
        if let bundle = Bundle(path: appPath) {
            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return (displayName, bundle.bundleIdentifier)
        }
        let fallback = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        return (fallback, nil)
    }
}
