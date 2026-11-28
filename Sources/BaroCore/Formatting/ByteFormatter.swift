import Foundation

public enum ByteFormatter {
    /// 紧凑速率格式，专为菜单栏窄空间设计（如 `0B`, `128K`, `4.2M`，含四舍五入进位保护）
    public static func compactRate(_ bytesPerSec: Double) -> String {
        let value = max(0, bytesPerSec)
        if value < 999.5 {
            return "\(Int(value.rounded()))B"
        }
        let kb = value / 1_024
        if kb < 999.5 {
            return "\(max(1, Int(kb.rounded())))K"
        }
        let mb = kb / 1_024
        if mb < 99.95 {
            return String(format: "%.1fM", mb)
        }
        if mb < 999.5 {
            return "\(Int(mb.rounded()))M"
        }
        let gb = mb / 1_024
        return gb >= 99.95 ? "\(Int(gb.rounded()))G" : String(format: "%.1fG", gb)
    }

    /// 面板详细速率格式（如 `4.28 MB/s`）
    public static func detailedRate(_ bytesPerSec: Double) -> String {
        let value = max(0, bytesPerSec)
        if value < 999.5 {
            return "\(Int(value.rounded())) B/s"
        }
        let kb = value / 1_024
        if kb < 99.95 {
            return String(format: "%.1f KB/s", kb)
        }
        if kb < 999.5 {
            return "\(Int(kb.rounded())) KB/s"
        }
        let mb = kb / 1_024
        if mb < 99.995 {
            return String(format: "%.2f MB/s", mb)
        }
        if mb < 999.5 {
            return String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1_024
        return String(format: "%.2f GB/s", gb)
    }

    /// 内存容量格式（macOS RAM 使用 1024 进制）
    public static func memorySize(_ bytes: UInt64) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1_024.0
        if kb < 999.5 {
            return "\(Int(kb.rounded())) KB"
        }
        let mb = kb / 1_024.0
        if mb < 99.95 {
            return String(format: "%.1f MB", mb)
        }
        if mb < 999.5 {
            return "\(Int(mb.rounded())) MB"
        }
        let gb = mb / 1_024.0
        return gb >= 99.95 ? "\(Int(gb.rounded())) GB" : String(format: "%.1f GB", gb)
    }

    /// 磁盘与网络流量格式化（macOS Finder 口径使用 1000 进制显示磁盘容量）
    public static func diskSize(_ bytes: UInt64) -> String {
        if bytes < 1_000 { return "\(bytes) B" }
        let kb = Double(bytes) / 1_000.0
        if kb < 999.5 {
            return "\(Int(kb.rounded())) KB"
        }
        let mb = kb / 1_000.0
        if mb < 999.5 {
            return "\(Int(mb.rounded())) MB"
        }
        let gb = mb / 1_000.0
        if gb < 99.95 {
            return String(format: "%.1f GB", gb)
        }
        if gb < 999.5 {
            return "\(Int(gb.rounded())) GB"
        }
        let tb = gb / 1_000.0
        return String(format: "%.2f TB", tb)
    }

    /// 紧凑磁盘容量格式，专为菜单栏窄空间设计（1000 进制，如 `650M`, `38.4G`, `245G`, `1.42T`）
    public static func compactDiskSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0G" }
        let mb = Double(bytes) / 1_000_000.0
        if mb < 999.5 {
            return "\(max(1, Int(mb.rounded())))M"
        }
        let gb = mb / 1_000.0
        if gb < 99.95 {
            return String(format: "%.1fG", gb)
        }
        if gb < 999.5 {
            return "\(Int(gb.rounded()))G"
        }
        let tb = gb / 1_000.0
        return tb >= 9.995 ? String(format: "%.1fT", tb) : String(format: "%.2fT", tb)
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
