import Foundation

/// Reads the tribes in this Battlegrounds lobby (TAG_RACE ids) from
/// `GameState.s_instance.m_availableRacesInBattlegroundsExcludingAmalgam`, a `List<TAG_RACE>`. Read-only.
/// Verified live 2026-11-13 (Hearthstone on Unity 6000.3, arm64): a `List`1` at offset 16, five ids, 2 ms.
/// Anything implausible throws, so the caller falls back to showing every tribe.
public enum BattlegroundsAvailableRaces {
    public static let fieldNames = [
        "m_availableRacesInBattlegroundsExcludingAmalgam",
        "m_availableRacesInBattlegrounds",
    ]
    static let maxRaces = 16

    public static func read(_ walker: MonoWalker) throws -> [Int] {
        let gameState = try walker.staticPointer("s_instance", of: try walker.findClass("GameState"))
        guard let name = fieldNames.first(where: { walker.hasField($0, in: gameState) }) else {
            throw WalkError("no available-races field")
        }
        guard let list = try walker.pointerField(name, in: gameState) else { throw WalkError("\(name) is null") }
        return try intList(list, walker, limit: maxRaces)
    }

    /// Items of a `System.Collections.Generic.List<T>` of 4-byte values (ints or int enums).
    public static func intList(_ list: UInt64, _ walker: MonoWalker, limit: Int) throws -> [Int] {
        guard let size = try walker.intField("_size", in: list) else { throw WalkError("unreadable list") }
        guard size >= 0, size <= limit else { throw WalkError("implausible list size") }
        guard size > 0 else { return [] }
        guard let itemsObject = try walker.pointerField("_items", in: list),
              let items = walker.array(at: itemsObject), items.count >= size else { throw WalkError("no list items") }
        return try (0..<Int(size)).map {
            guard let value = walker.memory.i32(items.data &+ UInt64($0 * 4)) else { throw WalkError("unreadable item") }
            return Int(value)
        }
    }
}
