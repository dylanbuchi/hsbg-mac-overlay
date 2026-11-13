// THROWAWAY spike CLI for the own read-only game reader (Sources/GameMemory). Not shipped.
//   spike/build-names.sh && spike/build/names_spike          # masked names (safe to paste/log)
//   spike/build/names_spike --show                           # full names, for your eyes only
//   spike/build/names_spike --dump                           # assemblies + GameState fields, no game data
import Darwin
import Foundation
import GameMemory

let args = Set(CommandLine.arguments.dropFirst())

func hearthstonePID() -> pid_t? {
    let pipe = Pipe(); let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "Hearthstone"]; task.standardOutput = pipe
    try? task.run(); task.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return out.split(separator: "\n").first.flatMap { pid_t($0) }
}

func mask(_ name: String) -> String {
    let base = name.split(separator: "#").first.map(String.init) ?? name
    var hash: UInt32 = 2166136261
    for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    return "\(base.prefix(1))… len \(base.count) id \(String(hash & 0xFFFF, radix: 16))"
}

/// Local player's PLAYER_ID and name from the newest Power.log (the game logs your own name).
func localFromPowerLog() -> (id: Int, name: String)? {
    let logs = URL(fileURLWithPath: "/Applications/Hearthstone/Logs")
    guard let dirs = try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil),
          let newest = dirs.filter({ $0.lastPathComponent.hasPrefix("Hearthstone_") }).max(by: { $0.lastPathComponent < $1.lastPathComponent }),
          let text = try? String(contentsOf: newest.appendingPathComponent("Power.log"), encoding: .utf8) else { return nil }
    var localID: Int?; var names: [Int: String] = [:]
    for line in text.split(separator: "\n") {
        if let r = line.range(of: "PlayerID="), let n = line.range(of: ", PlayerName=") {
            if let id = Int(line[r.upperBound..<n.lowerBound]) { names[id] = String(line[n.upperBound...]) }
        }
        if line.contains("Player EntityID="), let r = line.range(of: "PlayerID="), line.contains("GameAccountId=[hi=") , !line.contains("hi=0 ") {
            let rest = line[r.upperBound...]; localID = Int(rest.prefix { $0.isNumber })
        }
    }
    guard let id = localID, let name = names[id] else { return nil }
    return (id, name)
}

/// PLAYER_ID -> (hero card, latest leaderboard place) from the newest Power.log, to compare with the screen.
func placesFromPowerLog() -> [Int: (card: String, place: Int)] {
    let logs = URL(fileURLWithPath: "/Applications/Hearthstone/Logs")
    guard let dirs = try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil),
          let newest = dirs.filter({ $0.lastPathComponent.hasPrefix("Hearthstone_") }).max(by: { $0.lastPathComponent < $1.lastPathComponent }),
          let text = try? String(contentsOf: newest.appendingPathComponent("Power.log"), encoding: .utf8) else { return [:] }
    var current: (id: Int, card: String)?; var playerOf: [Int: Int] = [:]; var cardOf: [Int: String] = [:]; var placeOf: [Int: Int] = [:]
    func value(_ l: Substring, _ key: String) -> Substring? { l.range(of: key).map { l[$0.upperBound...].prefix { $0 != " " && $0 != "]" } } }
    for line in text.split(separator: "\n") where line.contains("GameState.DebugPrintPower") {
        if line.contains("FULL_ENTITY - Creating") || line.contains("SHOW_ENTITY") || line.contains("FULL_ENTITY - Updating") {
            if let id = value(line, "ID=").flatMap({ Int($0) }) ?? value(line, " id=").flatMap({ Int($0) }) {
                current = (id, String(value(line, "CardID=") ?? value(line, "cardId=") ?? "")); cardOf[id] = current!.card
            }
        } else if line.contains(" tag=") && !line.contains("TAG_CHANGE"), let c = current {
            if let v = value(line, "tag=PLAYER_ID value=").flatMap({ Int($0) }) { playerOf[c.id] = v }
            if let v = value(line, "tag=PLAYER_LEADERBOARD_PLACE value=").flatMap({ Int($0) }) { placeOf[c.id] = v }
        } else if line.contains("TAG_CHANGE"), let id = value(line, " id=").flatMap({ Int($0) }) {
            current = nil
            if let v = value(line, "tag=PLAYER_LEADERBOARD_PLACE value=").flatMap({ Int($0) }) { placeOf[id] = v; if let card = value(line, "cardId=") { cardOf[id] = String(card) } }
        } else { current = nil }
    }
    var result: [Int: (String, Int)] = [:]
    for (entity, player) in playerOf where (cardOf[entity] ?? "").contains("HERO") {
        if let place = placeOf[entity], (result[player].map { _ in entity > 0 } ?? true) { result[player] = (cardOf[entity] ?? "?", place) }
    }
    return result
}

guard let pid = hearthstonePID() else { print("Hearthstone not running"); exit(2) }
print("pid \(pid) translated=\(TaskMemory.isTranslated(pid: pid))")
let memory: TaskMemory
do { memory = try TaskMemory(pid: pid) } catch { print("FAIL open: \(error)"); exit(3) }
let start = Date()
do {
    let walker = try MonoConnector.walker(for: memory)
    if args.contains("--dump") {
        for a in walker.assemblies() { print("assembly", a.name) }
        let gs = try walker.findClass("GameState")
        for f in walker.fields(of: gs) { print("GameState.\(f.name) off=\(f.offset) static=\(f.isStatic)") }
    }
    if args.contains("--entries") {
        let gs = try walker.staticPointer("s_instance", of: try walker.findClass("GameState"))
        let map = try walker.pointerField("m_playerInfoMap", in: gs)!
        for f in ["count", "touchedSlots", "emptySlot", "_count"] where walker.hasField(f, in: map) { print(f, try walker.intField(f, in: map) ?? -1) }
        for (key, info) in try BattlegroundsNames.entries(of: map, walker) {
            let n = try walker.pointerField("m_name", in: info).flatMap { walker.string(at: $0) }
            print("key \(key) nameLen \(n?.count ?? -1)")
            if key == 4 || key == 5, let k = walker.classOf(object: info) {
                print("  class", walker.className(k) ?? "?")
                for f in walker.fields(of: k) where !f.isStatic {
                    let p = walker.memory.u64(info &+ UInt64(f.offset)) ?? 0
                    let str = p > 0x1000 ? walker.string(at: p).map { "str len \($0.count)" } : nil
                    print("   \(f.name) off \(f.offset) i32=\(walker.memory.i32(info &+ UInt64(f.offset)) ?? 0) \(str ?? "")")
                }
            }
        }
        if let k = walker.classOf(object: try walker.pointerField("m_playerInfoMap", in: gs)!).flatMap({ _ in Optional(1) }) { _ = k }
    }
    if args.contains("--entries") {
        let shown = try BattlegroundsNames.lastDisplayedNames(walker)
        print("lastDisplayed ids", shown.keys.sorted())
    }
    let names = try BattlegroundsNames.read(walker)
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("read \(names.count) names in \(ms) ms")
    let places = placesFromPowerLog()
    for id in Set(names.keys).union(places.keys).sorted() {
        let where_ = places[id].map { "place \($0.place) \($0.card)" } ?? "place ?"
        let shown = names[id].map { args.contains("--show") ? $0 : mask($0) } ?? "(no name in memory)"
        print("PLAYER_ID \(id) [\(where_)]: \(shown)")
    }
    if let local = localFromPowerLog() {
        let mem = names[local.id] ?? ""
        let base = { (n: String) in n.split(separator: "#").first.map(String.init) ?? n }
        print("local player check (Power.log PLAYER_ID \(local.id)): exact=\(mem == local.name) base=\(base(mem) == base(local.name)) memHasTag=\(mem.contains("#")) logHasTag=\(local.name.contains("#"))")
    } else { print("local player check: no local player in Power.log") }
} catch { print("FAIL walk: \(error)"); exit(4) }
