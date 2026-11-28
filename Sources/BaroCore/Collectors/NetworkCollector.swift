import Darwin
import Foundation

public final class NetworkCollector: @unchecked Sendable {
    public struct InterfaceTotals: Sendable, Equatable {
        public let inBytes: UInt64
        public let outBytes: UInt64

        public init(inBytes: UInt64, outBytes: UInt64) {
            self.inBytes = inBytes
            self.outBytes = outBytes
        }
    }

    private let lock = NSLock()
    private var previousSample: (totals: [String: InterfaceTotals], timestamp: Date, is64Bit: Bool)?
    private var sessionDownloadBytes: UInt64 = 0
    private var sessionUploadBytes: UInt64 = 0

    private static let excludedPrefixes = [
        "lo", "utun", "awdl", "llw", "anpi", "ap", "bridge", "gif", "stf", "XHC", "vmenet"
    ]

    public init() {}

    public func resetBaseline() {
        lock.lock()
        previousSample = nil
        lock.unlock()
    }

    /// 严格同位宽计数器差分：拒绝在 64 位 `sysctl` 与 32 位 `getifaddrs` 之间跨位宽相减，杜绝 `N × 4 GiB/s` 假尖峰
    public static func computeSafeTrafficDelta(
        currentTotals: [String: InterfaceTotals],
        currentIs64Bit: Bool,
        previousTotals: [String: InterfaceTotals],
        previousIs64Bit: Bool
    ) -> (deltaIn: UInt64, deltaOut: UInt64)? {
        guard currentIs64Bit == previousIs64Bit else { return nil }
        var totalDeltaIn: UInt64 = 0
        var totalDeltaOut: UInt64 = 0

        for (iface, curr) in currentTotals {
            guard let old = previousTotals[iface] else { continue }
            if curr.inBytes >= old.inBytes {
                totalDeltaIn += curr.inBytes - old.inBytes
            }
            if curr.outBytes >= old.outBytes {
                totalDeltaOut += curr.outBytes - old.outBytes
            }
        }
        return (totalDeltaIn, totalDeltaOut)
    }

    public func sample() -> NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let (fallbackTotals, ipv4Map, interfaceOrder) = readIPv4AndFallbackTotals()
        let sysctlTotals = read64BitInterfaceTotals()
        let has64Bit = !sysctlTotals.isEmpty
        let currentTotals = has64Bit ? sysctlTotals.filter { Self.isPhysicalInterface($0.key) } : fallbackTotals

        let now = Date()
        var downloadSpeed = 0.0
        var uploadSpeed = 0.0

        if let prev = previousSample {
            let dt = now.timeIntervalSince(prev.timestamp)
            if dt > 0.05 && dt < 30.0,
               let delta = Self.computeSafeTrafficDelta(
                   currentTotals: currentTotals,
                   currentIs64Bit: has64Bit,
                   previousTotals: prev.totals,
                   previousIs64Bit: prev.is64Bit
               ) {
                sessionDownloadBytes += delta.deltaIn
                sessionUploadBytes += delta.deltaOut
                downloadSpeed = Double(delta.deltaIn) / dt
                uploadSpeed = Double(delta.deltaOut) / dt
            }
        }

        previousSample = (currentTotals, now, has64Bit)

        let primaryInterface = interfaceOrder.first(where: { ipv4Map[$0] != nil })
            ?? interfaceOrder.first(where: { $0.hasPrefix("en") })
            ?? interfaceOrder.first
            ?? "--"
        let localIP = ipv4Map[primaryInterface] ?? ipv4Map.values.first ?? "--"
        let isConnected = !ipv4Map.isEmpty

        return NetworkSnapshot(
            downloadBytesPerSec: downloadSpeed,
            uploadBytesPerSec: uploadSpeed,
            sessionDownloadBytes: sessionDownloadBytes,
            sessionUploadBytes: sessionUploadBytes,
            primaryInterface: primaryInterface,
            localIPAddress: localIP,
            isConnected: isConnected
        )
    }

    /// 使用 sysctl NET_RT_IFLIST2 读取真 64 位 if_data64 字节计数器（带缓冲余量与 ENOMEM 重试）
    private func read64BitInterfaceTotals() -> [String: InterfaceTotals] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var estimatedLen = 0
        guard sysctl(&mib, 6, nil, &estimatedLen, nil, 0) == 0, estimatedLen > 0 else {
            return [:]
        }

        var allocLen = estimatedLen + max(4_096, estimatedLen / 4)
        for _ in 0..<3 {
            var buffer = [UInt8](repeating: 0, count: allocLen)
            var actualLen = allocLen
            if sysctl(&mib, 6, &buffer, &actualLen, nil, 0) == 0, actualLen > 0 {
                return buffer.withUnsafeBytes { rawBuf in
                    Self.parseInterfaceList2Buffer(rawBuf, validLen: min(actualLen, buffer.count))
                }
            }
            guard errno == ENOMEM else {
                return [:]
            }
            allocLen *= 2
        }
        return [:]
    }

    /// 安全解析 NET_RT_IFLIST2 路由消息流：先按 4 字节通用头检查 msglen 与 msgtype，杜绝短消息跨界读取与未对齐访问
    public static func parseInterfaceList2Buffer(_ rawBuf: UnsafeRawBufferPointer, validLen: Int) -> [String: InterfaceTotals] {
        var result: [String: InterfaceTotals] = [:]
        let safeLen = min(validLen, rawBuf.count)
        let ifMsgSize = MemoryLayout<if_msghdr2>.size
        let sdlDataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) ?? 8

        var offset = 0
        while offset + 4 <= safeLen {
            let rawMsgLen = rawBuf.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            let msgLen = Int(rawMsgLen)
            guard msgLen >= 4, offset + msgLen <= safeLen else { break }

            let msgType = Int32(rawBuf[offset + 3])
            if msgType == RTM_IFINFO2 && msgLen >= ifMsgSize {
                let msg = rawBuf.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let flags = msg.ifm_flags
                let isUp = (flags & IFF_UP) != 0
                let isRunning = (flags & IFF_RUNNING) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0

                if isUp, isRunning, !isLoopback, (msg.ifm_addrs & RTA_IFP) != 0 {
                    let sdlOffset = offset + ifMsgSize
                    if sdlOffset + sdlDataOffset <= offset + msgLen {
                        let sdlFamily = Int32(rawBuf[sdlOffset + 1])
                        let nameLen = Int(rawBuf[sdlOffset + 5])
                        let nameStart = sdlOffset + sdlDataOffset
                        if sdlFamily == AF_LINK, nameLen > 0, nameStart + nameLen <= offset + msgLen {
                            let nameBytes = rawBuf[nameStart..<(nameStart + nameLen)]
                            let name = String(decoding: nameBytes, as: UTF8.self)
                            if isPhysicalInterface(name) {
                                result[name] = InterfaceTotals(
                                    inBytes: msg.ifm_data.ifi_ibytes,
                                    outBytes: msg.ifm_data.ifi_obytes
                                )
                            }
                        }
                    }
                }
            }

            offset += msgLen
        }
        return result
    }

    private func readIPv4AndFallbackTotals() -> (totals: [String: InterfaceTotals], ipv4Map: [String: String], order: [String]) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let firstAddr = ifap else {
            return ([:], [:], [])
        }
        defer { freeifaddrs(firstAddr) }

        var fallbackTotals: [String: InterfaceTotals] = [:]
        var ipv4Map: [String: String] = [:]
        var interfaceOrder: [String] = []

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, isRunning, !isLoopback, let namePtr = current.pointee.ifa_name {
                let name = String(cString: namePtr)
                if Self.isPhysicalInterface(name), let addr = current.pointee.ifa_addr {
                    let family = Int32(addr.pointee.sa_family)
                    if family == AF_LINK, let dataPtr = current.pointee.ifa_data {
                        let ifData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                        fallbackTotals[name] = InterfaceTotals(
                            inBytes: UInt64(ifData.ifi_ibytes),
                            outBytes: UInt64(ifData.ifi_obytes)
                        )
                        if !interfaceOrder.contains(name) {
                            interfaceOrder.append(name)
                        }
                    } else if family == AF_INET {
                        var ipBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        let len = socklen_t(addr.pointee.sa_len)
                        if getnameinfo(addr, len, &ipBuffer, socklen_t(ipBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let bytes = ipBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                            let ip = String(decoding: bytes, as: UTF8.self)
                            if !ip.hasPrefix("169.254.") {
                                ipv4Map[name] = ip
                            }
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        return (fallbackTotals, ipv4Map, interfaceOrder)
    }

    public static func isPhysicalInterface(_ name: String) -> Bool {
        for prefix in Self.excludedPrefixes where name.hasPrefix(prefix) {
            return false
        }
        return name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }
}
