//
//  LRUCache.swift
//  readBook
//
//  简单的 LRU 缓存：超出容量时淘汰最久未访问的条目。
//

struct LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var store: [Key: Value] = [:]
    /// 访问顺序，front 为最近访问。
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func value(for key: Key) -> Value? {
        guard let value = store[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ value: Value, for key: Key) {
        store[key] = value
        touch(key)
        while order.count > capacity {
            let evicted = order.removeLast()
            store.removeValue(forKey: evicted)
        }
    }

    mutating func removeAll() {
        store.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.insert(key, at: 0)
    }
}
