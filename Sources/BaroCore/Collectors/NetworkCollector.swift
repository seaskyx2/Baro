import Darwin
import Foundation

public final class NetworkCollector: @unchecked Sendable {
    private struct InterfaceTotals {
        let inBytes: UInt64
        let outBytes: UInt64
    }

    private let lock = NSLock()
    private var previousSample: (totals: [String: InterfaceTotals], timestamp: Date)?
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

    public func sample() -> NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let (fallbackTotals, ipv4Map, interfaceOrder) = readIPv4AndFallbackTotals()
        let sysctlTotals = read64BitInterfaceTotals()
        let currentTotals = sysctlTotals.isEmpty ? fallbackTotals : sysctlTotals.filter { isPhysicalInterface($0.key) }

        let now = Date()
        var downloadSpeed = 0.0
        var uploadSpeed = 0.0

        if let prev = previousSample {
            let dt = now.timeIntervalSince(prev.timestamp)
            if dt > 0.05 && dt < 30.0 {
                var totalDeltaIn: UInt64 = 0
                var totalDeltaOut: UInt64 = 0

                for (iface, curr) in currentTotals {
                    guard let old = prev.totals[iface] else { continue }
                    if curr.inBytes >= old.inBytes {
                        totalDeltaIn += curr.inBytes - old.inBytes
                    }
                    if curr.outBytes >= old.outBytes {
                        totalDeltaOut += curr.outBytes - old.outBytes
                    }
                }

                sessionDownloadBytes += totalDeltaIn
                sessionUploadBytes += totalDeltaOut
                downloadSpeed = Double(totalDeltaIn) / dt
                uploadSpeed = Double(totalDeltaOut) / dt
            }
        }

        previousSample = (currentTotals, now)

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

    /// 使用 sysctl NET_RT_IFLIST2 读取真 64 位 if_data64 字节计数器，彻底解决 4GB 回绕问题
    private func read64BitInterfaceTotals() -> [String: InterfaceTotals] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buffer, &len, nil, 0) == 0, len > 0 else {
            return [:]
        }

        var result: [String: InterfaceTotals] = [:]
        buffer.withUnsafeBytes { rawBuf in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr2>.stride
            let baseAddr = rawBuf.baseAddress!

            while offset + headerSize <= len {
                let msgPtr = baseAddr.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self)
                let msg = msgPtr.pointee
                let msgLen = Int(msg.ifm_msglen)
                guard msgLen > 0, offset + msgLen <= len else { break }

                if Int32(msg.ifm_type) == RTM_IFINFO2 {
                    let flags = msg.ifm_flags
                    let isUp = (flags & IFF_UP) != 0
                    let isRunning = (flags & IFF_RUNNING) != 0
                    let isLoopback = (flags & IFF_LOOPBACK) != 0

                    if isUp, isRunning, !isLoopback, (msg.ifm_addrs & RTA_IFP) != 0 {
                        let sdlOffset = offset + headerSize
                        if sdlOffset + MemoryLayout<sockaddr_dl>.stride <= offset + msgLen {
                            let sdlPtr = baseAddr.advanced(by: sdlOffset).assumingMemoryBound(to: sockaddr_dl.self)
                            let sdl = sdlPtr.pointee
                            if Int32(sdl.sdl_family) == AF_LINK, sdl.sdl_nlen > 0 {
                                let nameLen = Int(sdl.sdl_nlen)
                                let nameStart = sdlOffset + MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data)!
                                if nameStart + nameLen <= offset + msgLen {
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
                }

                offset += msgLen
            }
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
                if isPhysicalInterface(name), let addr = current.pointee.ifa_addr {
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

    private func isPhysicalInterface(_ name: String) -> Bool {
        for prefix in Self.excludedPrefixes where name.hasPrefix(prefix) {
            return false
        }
        return name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }
}
