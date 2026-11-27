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

        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let firstAddr = ifap else {
            return .empty
        }
        defer { freeifaddrs(firstAddr) }

        var currentTotals: [String: InterfaceTotals] = [:]
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
                        currentTotals[name] = InterfaceTotals(
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

    private func isPhysicalInterface(_ name: String) -> Bool {
        for prefix in Self.excludedPrefixes where name.hasPrefix(prefix) {
            return false
        }
        return name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }
}
