import Foundation

/// Reads the Battlegrounds player names the game itself shows, keyed by PLAYER_ID, from
/// `GameState.s_instance.m_playerInfoMap` (the same source Firestone uses; names are known
/// without hovering the leaderboard). Read-only.
public enum BattlegroundsNames {
    public static func read(_ walker: MonoWalker) throws -> [Int: String] {
        let gameStateClass = try walker.findClass("GameState")
        let gameState = try walker.staticPointer("s_instance", of: gameStateClass)
        guard let map = try walker.pointerField("m_playerInfoMap", in: gameState) else {
            throw WalkError("m_playerInfoMap is null")
        }
        var names: [Int: String] = [:]
        for (playerID, info) in try entries(of: map, walker) {
            guard let namePointer = try walker.pointerField("m_name", in: info),
                  let name = walker.string(at: namePointer), !name.isEmpty else { continue }
            names[playerID] = name
        }
        // Fallback, as in Firestone: the names the game last displayed (GameMgr service).
        if names.count < 8, let shown = try? lastDisplayedNames(walker) {
            for (playerID, name) in shown where names[playerID] == nil { names[playerID] = name }
        }
        return names
    }

    /// `GameMgr.m_lastDisplayedPlayerNames`, reached through the game's service locator.
    public static func lastDisplayedNames(_ walker: MonoWalker) throws -> [Int: String] {
        guard let gameMgr = try service("GameMgr", walker),
              let map = try walker.pointerField("m_lastDisplayedPlayerNames", in: gameMgr) else { return [:] }
        var names: [Int: String] = [:]
        for (playerID, value) in try entries(of: map, walker) {
            if let name = walker.string(at: value), !name.isEmpty { names[playerID] = name }
        }
        return names
    }

    /// A game service by type name: HearthstoneJobs.s_dependencyBuilder[0].m_serviceLocator.m_services.
    static func service(_ name: String, _ walker: MonoWalker) throws -> UInt64? {
        let jobs = try walker.findClass("HearthstoneJobs", namespace: "Hearthstone")
        let builders = try walker.staticPointer("s_dependencyBuilder", of: jobs)
        guard let items = try walker.pointerField("_items", in: builders),
              let first = walker.array(at: items).flatMap({ walker.memory.pointer($0.data) }),
              let locator = try walker.pointerField("m_serviceLocator", in: first),
              let services = try walker.pointerField("m_services", in: locator) else { return nil }
        for (_, info) in try entries(of: services, walker) {
            if let typeName = try walker.pointerField("<ServiceTypeName>k__BackingField", in: info),
               walker.string(at: typeName) == name {
                return try walker.pointerField("<Service>k__BackingField", in: info)
            }
        }
        return nil
    }

    /// (int key, object value) pairs of a dictionary. Handles Hearthstone's `Map<K,V>` (old Mono
    /// layout: keySlots / valueSlots / touchedSlots) and .NET's `Dictionary<K,V>` (_entries).
    public static func entries(of map: UInt64, _ walker: MonoWalker) throws -> [(Int, UInt64)] {
        let memory = walker.memory
        if walker.hasField("keySlots", in: map) {
            guard let keysObject = try walker.pointerField("keySlots", in: map),
                  let valuesObject = try walker.pointerField("valueSlots", in: map),
                  let keys = walker.array(at: keysObject), let values = walker.array(at: valuesObject) else {
                return []
            }
            let used = walker.hasField("touchedSlots", in: map)
                ? Int(try walker.intField("touchedSlots", in: map) ?? 0)
                : Int(try walker.intField("count", in: map) ?? 0)
            let limit = min(used, keys.count, values.count, 64)
            return (0..<max(limit, 0)).compactMap { index in
                guard let key = memory.i32(keys.data &+ UInt64(index * 4)),
                      let value = memory.pointer(values.data &+ UInt64(index * 8)) else { return nil }
                return (Int(key), value)
            }
        }
        if walker.hasField("_entries", in: map) {
            guard let entriesObject = try walker.pointerField("_entries", in: map),
                  let entries = walker.array(at: entriesObject) else { return [] }
            let used = Int(try walker.intField("_count", in: map) ?? 0)
            // Entry<int, ref>: hashCode(4) next(4) key(4) pad(4) value(8)
            return (0..<max(min(used, entries.count, 64), 0)).compactMap { index in
                let entry = entries.data &+ UInt64(index * 24)
                guard let next = memory.i32(entry + 4), next >= -1,
                      let key = memory.i32(entry + 8),
                      let value = memory.pointer(entry + 16) else { return nil }
                return (Int(key), value)
            }
        }
        throw WalkError("unknown dictionary layout")
    }
}

/// Connects to a running Hearthstone and finds Mono's root domain without calling into the game:
/// it reads the code of the exported `mono_get_root_domain` and decodes which global it returns.
public enum MonoConnector {
    public static let monoLibraryName = "libmonobdwgc-2.0.dylib"

    public static func walker(for memory: TaskMemory) throws -> MonoWalker {
        let arch: MachOSymbol.Arch = TaskMemory.isTranslated(pid: memory.pid) ? .x86_64 : nativeArch
        guard let library = memory.image(named: monoLibraryName) else {
            throw WalkError("Mono library not loaded yet")
        }
        guard let file = FileManager.default.contents(atPath: library.path) else {
            throw WalkError("Mono library file unreadable")
        }
        guard let symbol = MachOSymbol.lookup("_mono_get_root_domain", inFile: [UInt8](file), arch: arch) else {
            throw WalkError("mono_get_root_domain not found")
        }
        let getter = library.base + (symbol.value - symbol.textVMAddr)
        guard let code = memory.read(getter, 16),
              let global = MachOSymbol.globalLoadedBy(code: code, at: getter, arch: arch) else {
            throw WalkError("unexpected mono_get_root_domain code")
        }
        guard let domain = memory.pointer(global) else { throw WalkError("Mono root domain not ready") }
        return MonoWalker(memory: memory, rootDomain: domain)
    }

    static var nativeArch: MachOSymbol.Arch {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }
}
