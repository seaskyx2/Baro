import Darwin
import Foundation

public enum HostInfoReader {
    /// 进程级静态复用的 Mach Host Port，避免每次采样重复调用 `mach_host_self()` 泄漏 Send Rights
    public static let machHostPort: mach_port_t = mach_host_self()

    public static func readStaticInfo() -> HostStaticInfo {
        let chipName = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let modelIdentifier = sysctlString("hw.model") ?? "Mac"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let totalMemory = sysctlUInt64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory

        let pCores = Int(sysctlInt32("hw.perflevel0.logicalcpu") ?? 0)
        let eCores = Int(sysctlInt32("hw.perflevel1.logicalcpu") ?? 0)
        let totalCores = Int(sysctlInt32("hw.ncpu") ?? Int32(ProcessInfo.processInfo.processorCount))

        return HostStaticInfo(
            chipName: chipName,
            modelIdentifier: modelIdentifier,
            osVersionString: osVersionString,
            totalMemoryBytes: totalMemory,
            pCoreCount: pCores,
            eCoreCount: eCores,
            totalCoreCount: totalCores
        )
    }

    public static func uptimeSeconds() -> TimeInterval {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        var now = timeval()
        gettimeofday(&now, nil)
        let elapsed = Double(now.tv_sec - boottime.tv_sec) + Double(now.tv_usec - boottime.tv_usec) / 1_000_000.0
        return max(0, elapsed)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
