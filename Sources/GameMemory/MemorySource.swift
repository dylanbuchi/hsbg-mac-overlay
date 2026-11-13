import Foundation

/// Read-only access to another process's memory. The live implementation (`TaskMemory`) only ever
/// copies bytes out of the game; tests use `FixtureMemory`. There is deliberately no write method.
public protocol MemorySource: AnyObject {
    /// `count` bytes at `address`, or nil when any of them is not readable.
    func read(_ address: UInt64, _ count: Int) -> [UInt8]?
}

extension MemorySource {
    public func u8(_ address: UInt64) -> UInt8? { read(address, 1)?[0] }

    public func u16(_ address: UInt64) -> UInt16? {
        read(address, 2).map { UInt16($0[0]) | UInt16($0[1]) << 8 }
    }

    public func u32(_ address: UInt64) -> UInt32? {
        read(address, 4).map { bytes in bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) } }
    }

    public func i32(_ address: UInt64) -> Int32? { u32(address).map { Int32(bitPattern: $0) } }

    public func u64(_ address: UInt64) -> UInt64? {
        read(address, 8).map { bytes in bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) } }
    }

    /// A non-null pointer, or nil (null pointers count as unreadable: no caller wants to follow one).
    public func pointer(_ address: UInt64) -> UInt64? {
        guard let value = u64(address), value != 0 else { return nil }
        return value
    }

    /// NUL-terminated UTF-8 string, capped so a bad pointer cannot make us read megabytes.
    public func cString(_ address: UInt64, max: Int = 256) -> String? {
        var bytes: [UInt8] = []
        var cursor = address
        while bytes.count < max {
            // Read in small chunks: a long read can straddle into an unmapped page.
            guard let chunk = read(cursor, 16) ?? read(cursor, 1) else { return nil }
            if let end = chunk.firstIndex(of: 0) {
                bytes += chunk[..<end]
                return String(decoding: bytes, as: UTF8.self)
            }
            bytes += chunk
            cursor &+= UInt64(chunk.count)
        }
        return nil
    }
}

/// A sparse memory image built from (address, bytes) blocks. Used by tests and by captured,
/// anonymized fixtures.
public final class FixtureMemory: MemorySource {
    private var blocks: [(start: UInt64, bytes: [UInt8])] = []

    public init() {}

    public func put(_ address: UInt64, _ bytes: [UInt8]) {
        blocks.append((address, bytes))
    }

    public func put(_ address: UInt64, u64 value: UInt64) {
        put(address, (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }

    public func put(_ address: UInt64, u32 value: UInt32) {
        put(address, (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }

    public func put(_ address: UInt64, cString: String) {
        put(address, Array(cString.utf8) + [0])
    }

    public func read(_ address: UInt64, _ count: Int) -> [UInt8]? {
        // Later blocks win, so a test can overwrite part of an earlier one.
        var out = [UInt8](repeating: 0, count: count)
        var filled = [Bool](repeating: false, count: count)
        for block in blocks.reversed() {
            let end = block.start &+ UInt64(block.bytes.count)
            guard address < end, address &+ UInt64(count) > block.start else { continue }
            for index in 0..<count where !filled[index] {
                let at = address &+ UInt64(index)
                if at >= block.start, at < end {
                    out[index] = block.bytes[Int(at - block.start)]
                    filled[index] = true
                }
            }
        }
        return filled.allSatisfy { $0 } ? out : nil
    }
}
