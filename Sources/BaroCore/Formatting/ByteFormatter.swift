import Foundation

public enum ByteFormatter {
    /// 紧凑速率格式，专为菜单栏窄空间设计（如 `0B`, `128K`, `4.2M`）
    public static func compactRate(_ bytesPerSec: Double) -> String {
        let value = max(0, bytesPerSec)
        if value < 1_024 {
            return "\(Int(value.rounded()))B"
        }
        let kb = value / 1_024
        if kb < 1_024 {
            if kb >= 100 {
                return "\(Int(kb.rounded()))K"
            }
            return String(format: "%.0fK", kb)
        }
        let mb = kb / 1_024
        if mb < 1_024 {
            return mb >= 100 ? String(format: "%.0fM", mb) : String(format: "%.1fM", mb)
        }
        let gb = mb / 1_024
        return String(format: "%.1fG", gb)
    }

    /// 面板详细速率格式（如 `4.28 MB/s`）
    public static func detailedRate(_ bytesPerSec: Double) -> String {
        let value = max(0, bytesPerSec)
        if value < 1_024 {
            return "\(Int(value.rounded())) B/s"
        }
        let kb = value / 1_024
        if kb < 1_024 {
            return kb >= 100 ? String(format: "%.0f KB/s", kb) : String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1_024
        if mb < 1_024 {
            return mb >= 100 ? String(format: "%.1f MB/s", mb) : String(format: "%.2f MB/s", mb)
        }
        let gb = mb / 1_024
        return String(format: "%.2f GB/s", gb)
    }

    /// 内存容量格式（使用十进制/活动监视器一致的 GB/MB 或二进制按需统一）
    /// 在 macOS 上，RAM 容量是 2 的幂（16 GB = 16 * 1024^3 字节），故内存使用 1024 进制
    public static func memorySize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        let kb = Double(bytes) / 1_024.0
        if kb < 1_024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1_024.0
        if mb < 1_024 {
            return mb >= 100 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
        }
        let gb = mb / 1_024.0
        return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }

    /// 磁盘与网络流量格式化（macOS Finder 口径使用 1000 进制显示磁盘容量）
    public static func diskSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        let kb = Double(bytes) / 1_000.0
        if kb < 1_000 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1_000.0
        if mb < 1_000 {
            return String(format: "%.0f MB", mb)
        }
        let gb = mb / 1_000.0
        if gb < 1_000 {
            return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
        }
        let tb = gb / 1_000.0
        return String(format: "%.2f TB", tb)
    }

    /// 紧凑磁盘容量格式，专为菜单栏窄空间设计（1000 进制，与 Finder 口径一致，如 `850M`, `38.4G`, `245G`, `1.4T`）
    public static func compactDiskSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0G" }
        let mb = Double(bytes) / 1_000_000.0
        if mb < 1_000 {
            return "\(max(1, Int(mb.rounded())))M"
        }
        let gb = mb / 1_000.0
        if gb < 100 {
            return String(format: "%.1fG", gb)
        }
        if gb < 1_000 {
            return "\(Int(gb.rounded()))G"
        }
        let tb = gb / 1_000.0
        return tb >= 10 ? String(format: "%.1fT", tb) : String(format: "%.2fT", tb)
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func remainingTime(minutes: Int) -> String {
        let safe = max(0, minutes)
        let hours = safe / 60
        let mins = safe % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
