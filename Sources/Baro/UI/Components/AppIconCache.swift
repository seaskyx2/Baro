import AppKit

/// 轻量应用图标缓存：将 App 图标缩放到 32×32 并内存复用，避免每次刷新重复解码 .icns
@MainActor
public final class AppIconCache {
    public static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private let maxEntries = 64

    private init() {}

    public func icon(forAppPath path: String) -> NSImage {
        if let hit = cache[path] {
            return hit
        }

        let raw = NSWorkspace.shared.icon(forFile: path)
        let targetSize = NSSize(width: 32, height: 32)
        let scaled = NSImage(size: targetSize)
        scaled.lockFocus()
        raw.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: raw.size),
            operation: .copy,
            fraction: 1.0
        )
        scaled.unlockFocus()

        if order.count >= maxEntries, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[path] = scaled
        order.append(path)
        return scaled
    }
}
