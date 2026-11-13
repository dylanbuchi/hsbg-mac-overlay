import XCTest
@testable import GameMemory

/// Builds a small fake Mono runtime in `FixtureMemory`, laid out with the offsets measured on the live
/// game (Hearthstone 37.0, Unity 6000.3, macOS arm64). Field offsets inside game objects
/// (m_playerInfoMap 56, SharedPlayerInfo.m_name 288) are the captured ones; every name is made up.
private final class FakeMono {
    let memory = FixtureMemory()
    let o = MonoOffsets.unity6000_3
    private var next: UInt64 = 0x1_0000_0000
    private var classesByImage: [UInt64: [UInt64]] = [:]
    private(set) var root: UInt64 = 0
    private(set) var csharp: UInt64 = 0

    init() {
        root = alloc(256)
        csharp = alloc(1400)
    }

    func alloc(_ size: Int) -> UInt64 {
        let address = next
        next += UInt64((size + 15) / 16 * 16) + 16
        memory.put(address, [UInt8](repeating: 0, count: size))
        return address
    }

    func cString(_ text: String) -> UInt64 {
        let address = alloc(text.utf8.count + 1)
        memory.put(address, cString: text)
        return address
    }

    func string(_ text: String) -> UInt64 {
        let units = Array(text.utf16)
        let address = alloc(20 + units.count * 2)
        memory.put(address &+ UInt64(o.stringLength), u32: UInt32(units.count))
        memory.put(address &+ UInt64(o.stringChars), units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        return address
    }

    /// A class with its fields, a vtable and (for statics) a static data block.
    func makeClass(_ name: String, namespace: String = "", image: UInt64? = nil,
                   fields: [(String, Int, Bool)], vtableSlots: Int = 4) -> (klass: UInt64, vtable: UInt64, statics: UInt64) {
        let klass = alloc(300)
        memory.put(klass &+ UInt64(o.className), u64: cString(name))
        memory.put(klass &+ UInt64(o.classNamespace), u64: cString(namespace))
        memory.put(klass &+ UInt64(o.classImage), u64: image ?? csharp)
        memory.put(klass &+ UInt64(o.classKind), [1])
        let array = alloc(max(fields.count, 1) * o.fieldSize)
        for (index, field) in fields.enumerated() {
            let entry = array &+ UInt64(index * o.fieldSize)
            let type = alloc(16)
            memory.put(type &+ UInt64(o.typeAttrs), [field.2 ? 0x16 : 0x01, 0x00])
            memory.put(entry, u64: type)
            memory.put(entry &+ UInt64(o.fieldName), u64: cString(field.0))
            memory.put(entry &+ UInt64(o.fieldOffset), u32: UInt32(field.1))
        }
        memory.put(klass &+ UInt64(o.classFields), u64: array)
        memory.put(klass &+ UInt64(o.classFieldCount), u32: UInt32(fields.count))
        memory.put(klass &+ UInt64(o.classVTableSize), u32: UInt32(vtableSlots))
        let vtable = alloc(o.vtableSlots + (vtableSlots + 1) * 8)
        memory.put(vtable, u64: klass)
        let statics = alloc(64)
        memory.put(vtable &+ UInt64(o.vtableSlots + vtableSlots * 8), u64: statics)
        let runtimeInfo = alloc(16)
        memory.put(runtimeInfo &+ UInt64(o.runtimeInfoDomainVTables), u64: vtable)
        memory.put(klass &+ UInt64(o.classRuntimeInfo), u64: runtimeInfo)
        classesByImage[image ?? csharp, default: []].append(klass)
        return (klass, vtable, statics)
    }

    func object(of vtable: UInt64, size: Int) -> UInt64 {
        let object = alloc(size)
        memory.put(object, u64: vtable)
        return object
    }

    func array(_ values: [UInt64], elementSize: Int) -> UInt64 {
        let address = alloc(o.arrayData + values.count * elementSize)
        memory.put(address &+ UInt64(o.arrayLength), u64: UInt64(values.count))
        for (index, value) in values.enumerated() {
            let at = address &+ UInt64(o.arrayData + index * elementSize)
            if elementSize == 4 { memory.put(at, u32: UInt32(truncatingIfNeeded: value)) } else { memory.put(at, u64: value) }
        }
        return address
    }

    /// Hearthstone's Map<int, V> (old Mono dictionary layout).
    lazy var mapClass = makeClass("Map`2", namespace: "Blizzard.T5", fields: [
        ("keySlots", 24, false), ("valueSlots", 32, false), ("count", 56, false), ("touchedSlots", 60, false),
    ])

    func map(_ pairs: [(Int, UInt64)]) -> UInt64 {
        let map = object(of: mapClass.vtable, size: 72)
        memory.put(map &+ 24, u64: array(pairs.map { UInt64(UInt32(bitPattern: Int32($0.0))) }, elementSize: 4))
        memory.put(map &+ 32, u64: array(pairs.map(\.1), elementSize: 8))
        memory.put(map &+ 56, u32: UInt32(pairs.count))
        memory.put(map &+ 60, u32: UInt32(pairs.count))
        return map
    }

    /// .NET Dictionary<K, ref>: _entries of {hashCode, next, key, value}; `freed` entries have next < -1.
    lazy var dictionaryClass = makeClass("Dictionary`2", namespace: "System.Collections.Generic", fields: [
        ("_entries", 24, false), ("_count", 56, false),
    ])

    func dictionary(_ pairs: [(key: UInt64, value: UInt64, freed: Bool)]) -> UInt64 {
        let dictionary = object(of: dictionaryClass.vtable, size: 64)
        let entries = alloc(o.arrayData + pairs.count * 24)
        memory.put(entries &+ UInt64(o.arrayLength), u64: UInt64(pairs.count))
        for (index, pair) in pairs.enumerated() {
            let entry = entries &+ UInt64(o.arrayData + index * 24)
            memory.put(entry &+ 4, u32: UInt32(bitPattern: pair.freed ? -3 : -1))
            memory.put(entry &+ 8, u64: pair.key)
            memory.put(entry &+ 16, u64: pair.value)
        }
        memory.put(dictionary &+ 24, u64: entries)
        memory.put(dictionary &+ 56, u32: UInt32(pairs.count))
        return dictionary
    }

    /// Wires the domain -> assemblies -> images -> class caches once all classes exist.
    func finish() {
        let images = [(name: "mscorlib", image: alloc(1400)), (name: "Assembly-CSharp", image: csharp)]
        var list: UInt64 = 0
        for entry in images.reversed() {
            let assembly = alloc(104)
            memory.put(assembly &+ UInt64(o.assemblyName), u64: cString(entry.name))
            memory.put(assembly &+ UInt64(o.assemblyImage), u64: entry.image)
            let node = alloc(16)
            memory.put(node, u64: assembly)
            memory.put(node &+ 8, u64: list)
            list = node
            // Two buckets, chained through next_class_cache.
            let classes = classesByImage[entry.image] ?? []
            let buckets = alloc(16)
            for (index, klass) in classes.enumerated() {
                let bucket = buckets &+ UInt64((index % 2) * 8)
                let head = memory.u64(bucket) ?? 0
                memory.put(klass &+ UInt64(o.classNextCache), u64: head)
                memory.put(bucket, u64: klass)
            }
            let table = entry.image &+ UInt64(o.imageClassCache)
            memory.put(table &+ UInt64(o.hashTableSize), u32: 2)
            memory.put(table &+ UInt64(o.hashTableTable), u64: buckets)
        }
        memory.put(root &+ UInt64(o.domainAssemblies), u64: list)
    }

    var walker: MonoWalker { MonoWalker(memory: memory, rootDomain: root) }
}

/// A lobby as captured on 2026-11-13 (game 1): 8 PLAYER_IDs, one AFK player without a name.
private func capturedLobby(names: [Int: String?], instance: Bool = true) -> FakeMono {
    let mono = FakeMono()
    let gameState = mono.makeClass("GameState", fields: [
        ("DEFAULT_SUBOPTION", 0, true), ("s_instance", 0, true), ("m_playerInfoMap", 56, false), ("m_gameEntity", 64, false),
    ])
    let info = mono.makeClass("SharedPlayerInfo", fields: [
        ("m_staticEntityDef", 56, false), ("m_accountId", 272, false), ("m_gameAccountId", 280, false),
        ("m_name", 288, false), ("m_playerHero", 296, false),
    ])
    _ = mono.mapClass
    let pairs: [(Int, UInt64)] = names.sorted { $0.key > $1.key }.map { id, name in
        let player = mono.object(of: info.vtable, size: 304)
        if let name { mono.memory.put(player &+ 288, u64: mono.string(name)) }
        return (id, player)
    }
    if instance {
        let state = mono.object(of: gameState.vtable, size: 72)
        mono.memory.put(state &+ 56, u64: mono.map(pairs))
        mono.memory.put(gameState.statics, u64: state)
    }
    return mono
}

final class GameMemoryTests: XCTestCase {
    private let lobby: [Int: String?] = [1: "Alpha", 2: "Bravo#2", 3: "Ünïcode名前", 4: nil,
                                         5: "You", 6: "Delta", 7: "echo", 8: "Fox"]

    func testReadsNamesByPlayerIDAndSkipsAPlayerWithoutOne() throws {
        let mono = capturedLobby(names: lobby)
        mono.finish()
        let names = try BattlegroundsNames.read(mono.walker)
        XCTAssertEqual(names, [1: "Alpha", 2: "Bravo#2", 3: "Ünïcode名前", 5: "You", 6: "Delta", 7: "echo", 8: "Fox"])
    }

    func testOutsideAMatchTheInstanceIsNull() {
        let mono = capturedLobby(names: lobby, instance: false)
        mono.finish()
        XCTAssertThrowsError(try BattlegroundsNames.read(mono.walker)) {
            XCTAssertEqual($0 as? WalkError, WalkError("s_instance is null"))
        }
    }

    func testFindsClassesAcrossCacheChainsAndAssemblies() throws {
        let mono = capturedLobby(names: lobby)
        for index in 0..<9 { _ = mono.makeClass("Filler\(index)", fields: []) }
        mono.finish()
        let walker = mono.walker
        XCTAssertEqual(walker.assemblies().map(\.name), ["mscorlib", "Assembly-CSharp"])
        XCTAssertEqual(walker.className(try walker.findClass("GameState")), "GameState")
        XCTAssertEqual(walker.classNamespace(try walker.findClass("Map`2", namespace: "Blizzard.T5")), "Blizzard.T5")
        XCTAssertThrowsError(try walker.findClass("Nope"))
        let fields = walker.fields(of: try walker.findClass("GameState"))
        XCTAssertEqual(fields.first { $0.name == "m_playerInfoMap" }, .init(name: "m_playerInfoMap", offset: 56, isStatic: false))
        XCTAssertEqual(fields.first { $0.name == "s_instance" }?.isStatic, true)
    }

    func testFallsBackToTheNamesTheGameLastDisplayed() throws {
        let mono = capturedLobby(names: [1: "Alpha", 2: nil])
        // HearthstoneJobs.s_dependencyBuilder[0].m_serviceLocator.m_services["GameMgr"].m_lastDisplayedPlayerNames
        let jobs = mono.makeClass("HearthstoneJobs", namespace: "Hearthstone", fields: [("s_dependencyBuilder", 8, true)])
        let list = mono.makeClass("List`1", namespace: "System.Collections.Generic", fields: [("_items", 16, false)])
        let builder = mono.makeClass("DependencyBuilder", fields: [("m_serviceLocator", 16, false)])
        let locator = mono.makeClass("ServiceLocator", fields: [("m_services", 24, false)])
        let serviceInfo = mono.makeClass("ServiceInfo", fields: [
            ("<ServiceTypeName>k__BackingField", 16, false), ("<Service>k__BackingField", 24, false),
        ])
        let gameMgr = mono.makeClass("GameMgr", fields: [("m_lastDisplayedPlayerNames", 96, false)])

        func service(_ name: String, _ instance: UInt64) -> UInt64 {
            let info = mono.object(of: serviceInfo.vtable, size: 32)
            mono.memory.put(info &+ 16, u64: mono.string(name))
            mono.memory.put(info &+ 24, u64: instance)
            return info
        }
        let manager = mono.object(of: gameMgr.vtable, size: 104)
        mono.memory.put(manager &+ 96, u64: mono.map([(2, mono.string("Bravo")), (1, mono.string("Stale"))]))
        let services = mono.dictionary([
            (1, service("GameMgr", 0xDEAD_0000), true),  // freed slot: must be skipped
            (2, service("NetCache", 0), false),
            (3, service("GameMgr", manager), false),
        ])
        let locatorObject = mono.object(of: locator.vtable, size: 32)
        mono.memory.put(locatorObject &+ 24, u64: services)
        let builderObject = mono.object(of: builder.vtable, size: 24)
        mono.memory.put(builderObject &+ 16, u64: locatorObject)
        let listObject = mono.object(of: list.vtable, size: 24)
        mono.memory.put(listObject &+ 16, u64: mono.array([builderObject], elementSize: 8))
        mono.memory.put(jobs.statics &+ 8, u64: listObject)
        mono.finish()

        // m_playerInfoMap wins where it has a name; the fallback only fills the gap.
        XCTAssertEqual(try BattlegroundsNames.read(mono.walker), [1: "Alpha", 2: "Bravo"])
    }

    func testRejectsAbsurdLengthsInsteadOfReadingMegabytes() {
        let mono = FakeMono()
        let bad = mono.alloc(32)
        mono.memory.put(bad &+ 16, u32: 5_000_000)
        mono.finish()
        XCTAssertNil(mono.walker.string(at: bad))
        XCTAssertNil(mono.memory.read(0, 8), "address 0 is never read")
    }

    // MARK: offsets and symbols

    func testMacOffsetsAreTheOnesValidatedLive() {
        // Firestone's Windows table, with what differed on macOS arm64 (2026-11-13): the domain list is
        // 16 bytes further, and MonoClass fields after the bitfields are 8 bytes earlier (clang packing).
        let o = MonoOffsets.unity6000_3
        XCTAssertEqual(o.domainAssemblies, 176)
        XCTAssertEqual([o.assemblyImage, o.imageClassCache, o.hashTableSize, o.hashTableTable], [96, 1232, 24, 32])
        XCTAssertEqual([o.classParent, o.classImage, o.className, o.classNamespace, o.classVTableSize],
                       [40, 56, 64, 72, 84])
        XCTAssertEqual([o.classFields, o.classRuntimeInfo, o.classGenericClass, o.classFieldCount, o.classNextCache],
                       [144, 200, 232, 248, 256])
        XCTAssertEqual([o.runtimeInfoDomainVTables, o.vtableSlots, o.stringChars, o.arrayData], [8, 72, 20, 32])
    }

    private func le(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }

    func testDecodesTheArm64RootDomainGetter() {
        // Hearthstone 37.0's libmonobdwgc: 0x11853c adrp x8, 498 pages; ldr x0, [x8, #0xe80]; ret
        let adrp: UInt32 = 0x9000_0000 | (UInt32(498 & 3) << 29) | (UInt32(498 >> 2) << 5) | 8
        let ldr: UInt32 = 0xF940_0000 | (UInt32(0xE80 / 8) << 10) | (8 << 5)
        let code = le(adrp) + le(ldr) + le(0xD65F_03C0)
        XCTAssertEqual(MachOSymbol.globalLoadedBy(code: code, at: 0x11_853C, arch: .arm64), 0x30_AE80)
        // A negative page offset, and a load through another register than adrp's, are both handled.
        let back: UInt32 = 0x9000_0000 | (UInt32(0x1FFFFF & 3) << 29) | (UInt32(0x1FFFFF >> 2) << 5) | 9
        XCTAssertEqual(MachOSymbol.globalLoadedBy(code: le(back) + le(0xF940_0000 | (9 << 5)), at: 0x5000, arch: .arm64), 0x4000)
        XCTAssertNil(MachOSymbol.globalLoadedBy(code: le(adrp) + le(0xF940_0000 | (9 << 5)), at: 0x5000, arch: .arm64))
        XCTAssertNil(MachOSymbol.globalLoadedBy(code: le(0xD65F_03C0) + le(ldr), at: 0, arch: .arm64))
    }

    func testDecodesTheX86RootDomainGetterWithItsPrologue() {
        // push rbp; mov rbp, rsp; mov rax, [rip + 0x100]; pop rbp; ret
        let code: [UInt8] = [0x55, 0x48, 0x89, 0xE5, 0x48, 0x8B, 0x05] + le(0x100) + [0x5D, 0xC3]
        XCTAssertEqual(MachOSymbol.globalLoadedBy(code: code, at: 0x1000, arch: .x86_64), 0x1000 + 11 + 0x100)
        XCTAssertEqual(MachOSymbol.globalLoadedBy(code: Array(code[4...]), at: 0x1000, arch: .x86_64), 0x1000 + 7 + 0x100)
        XCTAssertNil(MachOSymbol.globalLoadedBy(code: [0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90], at: 0, arch: .x86_64))
    }

    /// A minimal 64-bit Mach-O: __TEXT segment, a symbol table with one local and one exported symbol.
    private func machO(cpu: UInt32, symbolValue: UInt64) -> [UInt8] {
        func u32(_ v: UInt32) -> [UInt8] { le(v) }
        func u64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        let strings: [UInt8] = [0] + Array("_local".utf8) + [0] + Array("_mono_get_root_domain".utf8) + [0]
        let segment = u32(0x19) + u32(72) + Array("__TEXT".utf8) + [UInt8](repeating: 0, count: 10)
            + u64(0x1000) + u64(0x1000) + u64(0) + u64(0x1000) + u32(5) + u32(5) + u32(0) + u32(0)
        let headerSize = 32 + 72 + 24
        let symoff = headerSize, stroff = symoff + 32
        let symtab = u32(0x2) + u32(24) + u32(UInt32(symoff)) + u32(2) + u32(UInt32(stroff)) + u32(UInt32(strings.count))
        let header = u32(0xFEED_FACF) + u32(cpu) + u32(0) + u32(6) + u32(2) + u32(96) + u32(0) + u32(0)
        let local = u32(1) + [0x0E, 1] + [0, 0] + u64(0x2000)                 // N_SECT, not external
        let exported = u32(8) + [0x0F, 1] + [0, 0] + u64(symbolValue)         // N_SECT | N_EXT
        return header + segment + symtab + local + exported + strings
    }

    func testFindsTheExportedSymbolInThinAndUniversalFiles() {
        let arm = machO(cpu: 0x0100_000C, symbolValue: 0x11_853C)
        let found = MachOSymbol.lookup("_mono_get_root_domain", inFile: arm, arch: .arm64)
        XCTAssertEqual(found?.value, 0x11_853C)
        XCTAssertEqual(found?.textVMAddr, 0x1000)
        XCTAssertNil(MachOSymbol.lookup("_local", inFile: arm, arch: .arm64), "only exported symbols")
        XCTAssertNil(MachOSymbol.lookup("_mono_get_root_domain", inFile: arm, arch: .x86_64))

        let intel = machO(cpu: 0x0100_0007, symbolValue: 0x14_5D65)
        func be(_ v: UInt32) -> [UInt8] { le(v).reversed() }
        let armOffset = 0x1000, intelOffset = 0x2000
        var fat = be(0xCAFE_BABE) + be(2)
            + be(0x0100_0007) + be(3) + be(UInt32(intelOffset)) + be(UInt32(intel.count)) + be(12)
            + be(0x0100_000C) + be(0) + be(UInt32(armOffset)) + be(UInt32(arm.count)) + be(14)
        fat += [UInt8](repeating: 0, count: armOffset - fat.count) + arm
        fat += [UInt8](repeating: 0, count: intelOffset - fat.count) + intel
        XCTAssertEqual(MachOSymbol.lookup("_mono_get_root_domain", inFile: fat, arch: .arm64)?.value, 0x11_853C)
        XCTAssertEqual(MachOSymbol.lookup("_mono_get_root_domain", inFile: fat, arch: .x86_64)?.value, 0x14_5D65)
        XCTAssertNil(MachOSymbol.lookup("_mono_get_root_domain", inFile: Array(fat.prefix(40)), arch: .arm64))
    }
}

/// The leaderboard tile path as captured on 2026-11-13 (macOS arm64): List`1 _items 16 / _size 24,
/// PlayerLeaderboardSoloTeam.m_playerLeaderboardCards 112, PlayerLeaderboardCard m_overlay 112 /
/// m_playerHeroEntity 152, Entity.m_tags 16, TagMap.m_values 16, Dictionary`2 _entries 24 / _count 64,
/// PlayerLeaderboardPlayerOverlay.m_raceCounts 168, Map`2 linkSlots 24 / valueSlots 40 / touchedSlots 56.
private struct FakeTile {
    var entityID: Int32?
    var races: [(race: UInt32, count: Int32, used: Bool)]
}

private func capturedLeaderboard(_ tiles: [FakeTile], instance: Bool = true) -> FakeMono {
    let mono = FakeMono()
    let manager = mono.makeClass("PlayerLeaderboardManager", fields: [("s_instance", 0, true), ("m_teams", 136, false)])
    let list = mono.makeClass("List`1", namespace: "System.Collections.Generic", fields: [("_items", 16, false), ("_size", 24, false)])
    let team = mono.makeClass("PlayerLeaderboardSoloTeam", fields: [("m_playerLeaderboardCards", 112, false)])
    let card = mono.makeClass("PlayerLeaderboardCard", fields: [("m_overlay", 112, false), ("m_playerHeroEntity", 152, false)])
    let entity = mono.makeClass("Entity", fields: [("m_tags", 16, false)])
    let tagMap = mono.makeClass("TagMap", fields: [("m_values", 16, false)])
    let dictionary = mono.makeClass("Dictionary`2", namespace: "System.Collections.Generic",
                                    fields: [("_entries", 24, false), ("_count", 64, false)])
    let overlay = mono.makeClass("PlayerLeaderboardPlayerOverlay", fields: [("m_raceCounts", 168, false)])
    let raceMap = mono.makeClass("Map`2", namespace: "Blizzard.T5.Core",
                                 fields: [("linkSlots", 24, false), ("valueSlots", 40, false), ("touchedSlots", 56, false)])

    func makeList(_ items: [UInt64]) -> UInt64 {
        let object = mono.object(of: list.vtable, size: 32)
        mono.memory.put(object &+ 16, u64: mono.array(items, elementSize: 8))
        mono.memory.put(object &+ 24, u32: UInt32(items.count))
        return object
    }

    func makeCard(_ tile: FakeTile) -> UInt64 {
        let object = mono.object(of: card.vtable, size: 160)
        let hero = mono.object(of: entity.vtable, size: 24)
        let tags = mono.object(of: tagMap.vtable, size: 24)
        let values = mono.object(of: dictionary.vtable, size: 72)
        // Entry<int, int>: hashCode next key value. A freed entry carrying ENTITY_ID must be skipped.
        let pairs: [(key: Int32, value: Int32, next: Int32)] = [(49, 1, -1), (53, 999, -3)]
            + (tile.entityID.map { [(53, $0, -1)] } ?? []) + [(380, 7, -1)]
        let entries = mono.alloc(mono.o.arrayData + pairs.count * 16)
        mono.memory.put(entries &+ UInt64(mono.o.arrayLength), u64: UInt64(pairs.count))
        for (index, pair) in pairs.enumerated() {
            let entry = entries &+ UInt64(mono.o.arrayData + index * 16)
            mono.memory.put(entry &+ 4, u32: UInt32(bitPattern: pair.next))
            mono.memory.put(entry &+ 8, u32: UInt32(bitPattern: pair.key))
            mono.memory.put(entry &+ 12, u32: UInt32(bitPattern: pair.value))
        }
        mono.memory.put(values &+ 24, u64: entries)
        mono.memory.put(values &+ 64, u32: UInt32(pairs.count))
        mono.memory.put(tags &+ 16, u64: values)
        mono.memory.put(hero &+ 16, u64: tags)
        mono.memory.put(object &+ 152, u64: hero)

        let tileOverlay = mono.object(of: overlay.vtable, size: 176)
        let map = mono.object(of: raceMap.vtable, size: 64)
        let links = mono.alloc(mono.o.arrayData + tile.races.count * 8)
        mono.memory.put(links &+ UInt64(mono.o.arrayLength), u64: UInt64(tile.races.count))
        for (index, race) in tile.races.enumerated() {
            mono.memory.put(links &+ UInt64(mono.o.arrayData + index * 8), u32: race.race | (race.used ? 0x8000_0000 : 0))
        }
        mono.memory.put(map &+ 24, u64: links)
        mono.memory.put(map &+ 40, u64: mono.array(tile.races.map { UInt64(UInt32(bitPattern: $0.count)) }, elementSize: 4))
        mono.memory.put(map &+ 56, u32: UInt32(tile.races.count))
        mono.memory.put(tileOverlay &+ 168, u64: map)
        mono.memory.put(object &+ 112, u64: tileOverlay)
        return object
    }

    if instance {
        let teams = tiles.map { tile -> UInt64 in
            let object = mono.object(of: team.vtable, size: 120)
            mono.memory.put(object &+ 112, u64: makeList([makeCard(tile)]))
            return object
        }
        let instanceObject = mono.object(of: manager.vtable, size: 144)
        mono.memory.put(instanceObject &+ 136, u64: makeList(teams))
        mono.memory.put(manager.statics, u64: instanceObject)
    }
    mono.finish()
    return mono
}

final class BattlegroundsTribesTests: XCTestCase {
    func testReadsRaceCountsByHeroEntityID() throws {
        let tribes = try BattlegroundsTribes.read(capturedLeaderboard([
            FakeTile(entityID: 102, races: [(26, 1, true), (126, 1, true)]),
            FakeTile(entityID: 133, races: [(43, 1, true), (20, 4, false)]),   // a removed slot is skipped
            FakeTile(entityID: 166, races: []),
        ]).walker)
        XCTAssertEqual(tribes, [102: [26: 1, 126: 1], 133: [43: 1], 166: [:]])
    }

    func testATileWithoutAHeroIDIsSkipped() throws {
        let tribes = try BattlegroundsTribes.read(capturedLeaderboard([
            FakeTile(entityID: nil, races: [(18, 2, true)]), FakeTile(entityID: 224, races: [(18, 1, true)]),
        ]).walker)
        XCTAssertEqual(tribes, [224: [18: 1]])
    }

    func testOutsideAMatchTheManagerIsNull() {
        XCTAssertThrowsError(try BattlegroundsTribes.read(capturedLeaderboard([], instance: false).walker)) {
            XCTAssertEqual($0 as? WalkError, WalkError("s_instance is null"))
        }
    }

    func testAbsurdCountsAreRejectedNotShown() {
        XCTAssertThrowsError(try BattlegroundsTribes.read(capturedLeaderboard([
            FakeTile(entityID: 102, races: [(18, 5000, true)]),
        ]).walker))
    }
}

/// GameState with `m_availableRacesInBattlegroundsExcludingAmalgam` as a List<TAG_RACE>. The field offset is
/// made up: the live one is not captured yet (spike --races).
private func lobbyRaces(_ races: [Int32], size: Int32? = nil, field: String = "m_availableRacesInBattlegroundsExcludingAmalgam",
                        instance: Bool = true) -> FakeMono {
    let mono = FakeMono()
    let gameState = mono.makeClass("GameState", fields: [("s_instance", 0, true), ("m_playerInfoMap", 56, false), (field, 80, false)])
    let list = mono.makeClass("List`1", namespace: "System.Collections.Generic", fields: [("_items", 16, false), ("_size", 24, false)])
    if instance {
        let state = mono.object(of: gameState.vtable, size: 96)
        let object = mono.object(of: list.vtable, size: 32)
        mono.memory.put(object &+ 16, u64: mono.array(races.map { UInt64(UInt32(bitPattern: $0)) }, elementSize: 4))
        mono.memory.put(object &+ 24, u32: UInt32(bitPattern: size ?? Int32(races.count)))
        mono.memory.put(state &+ 80, u64: object)
        mono.memory.put(gameState.statics, u64: state)
    }
    mono.finish()
    return mono
}

final class BattlegroundsAvailableRacesTests: XCTestCase {
    func testReadsTheLobbyRaceIDsInOrder() throws {
        XCTAssertEqual(try BattlegroundsAvailableRaces.read(lobbyRaces([20, 24, 17, 23, 11]).walker), [20, 24, 17, 23, 11])
    }

    func testAcceptsTheFieldWithoutTheAmalgamSuffix() throws {
        XCTAssertEqual(try BattlegroundsAvailableRaces.read(lobbyRaces([14, 15], field: "m_availableRacesInBattlegrounds").walker), [14, 15])
    }

    func testAnUnknownLayoutOrAbsurdSizeThrows() {
        XCTAssertThrowsError(try BattlegroundsAvailableRaces.read(lobbyRaces([20], field: "m_somethingElse").walker))
        XCTAssertThrowsError(try BattlegroundsAvailableRaces.read(lobbyRaces([20, 24], size: 500).walker))
        XCTAssertThrowsError(try BattlegroundsAvailableRaces.read(lobbyRaces([20, 24], size: 3).walker))
        XCTAssertThrowsError(try BattlegroundsAvailableRaces.read(lobbyRaces([], instance: false).walker))
    }
}
