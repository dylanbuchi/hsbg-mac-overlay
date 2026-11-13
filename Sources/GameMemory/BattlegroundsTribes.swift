import Foundation

/// Reads the tribe counts the game shows on each leaderboard tile, keyed by the hero's ENTITY_ID (the
/// id Power.log uses): `PlayerLeaderboardManager.s_instance.m_teams[].m_playerLeaderboardCards[]`,
/// hero entity tags for the id, and `m_overlay.m_raceCounts` for TAG_RACE -> count. Read-only.
public enum BattlegroundsTribes {
    static let entityIDTag: Int32 = 53       // GAME_TAG.ENTITY_ID
    static let maxTeams = 16, maxCards = 16, maxTags = 4096, maxSlots = 256

    public static func read(_ walker: MonoWalker) throws -> [Int: [Int: Int]] {
        let manager = try walker.staticPointer("s_instance", of: try walker.findClass("PlayerLeaderboardManager"))
        guard let teams = try walker.pointerField("m_teams", in: manager) else { throw WalkError("m_teams is null") }
        var result: [Int: [Int: Int]] = [:]
        for team in try list(teams, walker, limit: maxTeams) {
            guard let cards = try walker.pointerField("m_playerLeaderboardCards", in: team) else { continue }
            for card in try list(cards, walker, limit: maxCards) {
                guard let hero = try walker.pointerField("m_playerHeroEntity", in: card),
                      let entityID = try tag(entityIDTag, of: hero, walker), entityID > 0 else { continue }
                var races: [Int: Int] = [:]
                if let overlay = try walker.pointerField("m_overlay", in: card),
                   let counts = try walker.pointerField("m_raceCounts", in: overlay) {
                    races = try raceCounts(counts, walker)
                }
                result[Int(entityID)] = races
            }
        }
        return result
    }

    /// Items of a `System.Collections.Generic.List<T>` of references.
    public static func list(_ list: UInt64, _ walker: MonoWalker, limit: Int) throws -> [UInt64] {
        guard let size = try walker.intField("_size", in: list) else { throw WalkError("unreadable list") }
        guard size >= 0, size <= limit else { throw WalkError("implausible list size") }
        guard size > 0 else { return [] }
        guard let itemsObject = try walker.pointerField("_items", in: list),
              let items = walker.array(at: itemsObject), items.count >= size else { throw WalkError("no list items") }
        return (0..<Int(size)).compactMap { walker.memory.pointer(items.data &+ UInt64($0 * 8)) }
    }

    /// One tag of an entity: `Entity.m_tags.m_values`, a `Dictionary<int, int>`.
    static func tag(_ key: Int32, of entity: UInt64, _ walker: MonoWalker) throws -> Int32? {
        guard let tags = try walker.pointerField("m_tags", in: entity),
              let values = try walker.pointerField("m_values", in: tags),
              let count = try walker.intField("_count", in: values) else { return nil }
        guard count >= 0, count <= maxTags else { throw WalkError("implausible tag count") }
        guard let entriesObject = try walker.pointerField("_entries", in: values),
              let entries = walker.array(at: entriesObject) else { return nil }
        // Entry<int, int>: hashCode(4) next(4) key(4) value(4); next < -1 marks a freed slot.
        let memory = walker.memory
        for index in 0..<min(Int(count), entries.count) {
            let entry = entries.data &+ UInt64(index * 16)
            guard let next = memory.i32(entry &+ 4), next >= -1, memory.i32(entry &+ 8) == key else { continue }
            return memory.i32(entry &+ 12)
        }
        return nil
    }

    /// `Map<TAG_RACE, int>` in the old Mono layout: linkSlots {HashCode, Next} + valueSlots, with the
    /// top bit of HashCode marking a used slot. An enum key's hash is its value.
    static func raceCounts(_ map: UInt64, _ walker: MonoWalker) throws -> [Int: Int] {
        guard let touched = try walker.intField("touchedSlots", in: map) else { return [:] }
        guard touched >= 0, touched <= maxSlots else { throw WalkError("implausible race slots") }
        guard touched > 0 else { return [:] }
        guard let linksObject = try walker.pointerField("linkSlots", in: map),
              let valuesObject = try walker.pointerField("valueSlots", in: map),
              let links = walker.array(at: linksObject), let values = walker.array(at: valuesObject) else { return [:] }
        let memory = walker.memory
        var races: [Int: Int] = [:]
        for index in 0..<min(Int(touched), links.count, values.count) {
            guard let hash = memory.u32(links.data &+ UInt64(index * 8)), hash & 0x8000_0000 != 0,
                  let count = memory.i32(values.data &+ UInt64(index * 4)) else { continue }
            guard count >= 0, count <= 1000 else { throw WalkError("implausible race count") }
            races[Int(hash & 0x7FFF_FFFF)] = Int(count)
        }
        return races
    }
}
