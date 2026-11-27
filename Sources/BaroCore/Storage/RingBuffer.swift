import Foundation

/// 固定容量的内存环形缓冲区（零磁盘写入，杜绝长期运行内存增长）
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element?]
    private var writeIndex: Int = 0
    private var countInternal: Int = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public var count: Int { countInternal }
    public var isEmpty: Bool { countInternal == 0 }

    public mutating func append(_ element: Element) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        if countInternal < capacity {
            countInternal += 1
        }
    }

    public var values: [Element] {
        guard countInternal > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(countInternal)
        let start = countInternal == capacity ? writeIndex : 0
        for offset in 0..<countInternal {
            let idx = (start + offset) % capacity
            if let value = storage[idx] {
                result.append(value)
            }
        }
        return result
    }

    public var latest: Element? {
        guard countInternal > 0 else { return nil }
        let idx = (writeIndex - 1 + capacity) % capacity
        return storage[idx]
    }

    public mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        writeIndex = 0
        countInternal = 0
    }
}
