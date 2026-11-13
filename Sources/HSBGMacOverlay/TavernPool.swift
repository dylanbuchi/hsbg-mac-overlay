import Foundation

/// The mechanics the tavern list marks on a minion, with the short tag drawn on the row.
enum PoolMechanic: String, CaseIterable, Sendable {
    case battlecry = "BATTLECRY"
    case deathrattle = "DEATHRATTLE"
    case divineShield = "DIVINE_SHIELD"
    case taunt = "TAUNT"
    case endOfTurn = "END_OF_TURN_TRIGGER"
    case reborn = "REBORN"

    var tag: String {
        switch self {
        case .battlecry: "BC"
        case .deathrattle: "DR"
        case .divineShield: "DS"
        case .taunt: "T"
        case .endOfTurn: "EoT"
        case .reborn: "R"
        }
    }

    var label: String {
        switch self {
        case .battlecry: "Battlecry"
        case .deathrattle: "Deathrattle"
        case .divineShield: "Divine Shield"
        case .taunt: "Taunt"
        case .endOfTurn: "End of turn"
        case .reborn: "Reborn"
        }
    }
}

/// One card of the Battlegrounds Solo tavern pool: a minion or a tavern spell. Only what the list draws.
struct PoolCard: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var tier: Int
    var isSpell: Bool
    /// Minion types (`ALL` for amalgams); empty for spells and minions without a type.
    var races: [String]
    /// Tribes a card belongs with although it has no type (for example a Pirate spell); in the pool only
    /// when one of them is in the lobby.
    var associatedRaces: [String]
    var mechanics: [String]
    var attack: Int?
    var health: Int?
    var cost: Int?

    var shownMechanics: [PoolMechanic] {
        PoolMechanic.allCases.filter { mechanics.contains($0.rawValue) }
    }
}

/// Turns HearthstoneJSON's full card list into the small Solo pool, and checks a pool is usable.
enum TavernPool {
    static let tiers = 1...7

    private struct RawCard: Decodable {
        var id: String?
        var name: String?
        var type: String?
        var techLevel: Int?
        var races: [String]?
        var race: String?
        var battlegroundsAssociatedRaces: [String]?
        var mechanics: [String]?
        var attack: Int?
        var health: Int?
        var cost: Int?
        var isBattlegroundsPoolMinion: Bool?
        var isBattlegroundsPoolSpell: Bool?
        var isBattlegroundsDuosExclusive: Bool?
    }

    /// Pool minions and pool spells of HearthstoneJSON's `cards.json`, without Duos-only cards, sorted by
    /// tier then name.
    static func parse(hearthstoneJSON data: Data) throws -> [PoolCard] {
        let raw = try JSONDecoder().decode([RawCard].self, from: data)
        var cards: [PoolCard] = []
        for card in raw {
            let isMinion = card.isBattlegroundsPoolMinion == true
            let isSpell = card.isBattlegroundsPoolSpell == true
            guard isMinion || isSpell, card.isBattlegroundsDuosExclusive != true,
                  let id = card.id, let name = card.name, !name.isEmpty,
                  let tier = card.techLevel, tiers.contains(tier) else { continue }
            let races = card.races ?? card.race.map { [$0] } ?? []
            cards.append(PoolCard(
                id: id, name: name, tier: tier, isSpell: !isMinion,
                races: isMinion ? races.filter { $0 != "INVALID" } : [],
                associatedRaces: card.battlegroundsAssociatedRaces ?? [],
                mechanics: (card.mechanics ?? []).filter { PoolMechanic(rawValue: $0) != nil },
                attack: isMinion ? card.attack : nil, health: isMinion ? card.health : nil,
                cost: isSpell && !isMinion ? card.cost : nil))
        }
        return sorted(cards)
    }

    static func sorted(_ cards: [PoolCard]) -> [PoolCard] {
        cards.sorted { ($0.tier, $0.name, $0.id) < ($1.tier, $1.name, $1.id) }
    }

    /// A pool good enough to show: enough minions, and some on each of tiers 1 to 6. Guards against a
    /// truncated download or a format change that would silently empty the list.
    static func isPlausible(_ cards: [PoolCard]) -> Bool {
        let minions = cards.filter { !$0.isSpell }
        guard minions.count >= 100, minions.count <= 1000, cards.count <= 2000 else { return false }
        let tiersSeen = Set(minions.map(\.tier))
        return (1...6).allSatisfy(tiersSeen.contains)
    }
}

/// The pool on disk: `tavern-pool.json` in Application Support (the filtered list and the server's ETag),
/// with the snapshot built into the app as the offline seed.
struct TavernPoolCache: Sendable {
    struct Stored: Codable, Equatable {
        var etag: String?
        var checkedAt: Date
        var cards: [PoolCard]
    }

    let fileURL: URL?

    static var standard: TavernPoolCache {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return TavernPoolCache(fileURL: support?.appendingPathComponent("HSBGMacOverlay/tavern-pool.json"))
    }

    func load() -> Stored? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? Self.decoder.decode(Stored.self, from: data),
              TavernPool.isPlausible(stored.cards) else { return nil }
        return stored
    }

    func save(_ stored: Stored) {
        guard let fileURL, let data = try? Self.encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Keeps the pool current: the cache (or the built-in seed) right away, and at most one conditional
/// download of HearthstoneJSON every 12 hours (`If-None-Match`, so an unchanged list costs a 304).
actor TavernPoolStore {
    typealias HTTPFetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let url = URL(string: "https://api.hearthstonejson.com/v1/latest/enUS/cards.json")!
    static let refreshInterval: TimeInterval = 12 * 3600
    static let maxDownload = 40 * 1024 * 1024

    private let cache: TavernPoolCache
    private let http: HTTPFetch
    private let seed: @Sendable () -> [PoolCard]
    private let now: @Sendable () -> Date
    private var stored: TavernPoolCache.Stored?
    private var loaded = false

    init(cache: TavernPoolCache = .standard,
         http: @escaping HTTPFetch = { try await URLSession.shared.data(for: $0) },
         seed: @escaping @Sendable () -> [PoolCard] = { TavernPoolSeed.cards },
         now: @escaping @Sendable () -> Date = Date.init) {
        self.cache = cache
        self.http = http
        self.seed = seed
        self.now = now
    }

    /// The best pool there is without waiting on the network.
    func cards() -> [PoolCard] {
        if !loaded {
            stored = cache.load()
            loaded = true
        }
        return stored?.cards ?? seed()
    }

    /// Downloads a newer pool when the last check is old enough. Returns the new cards when they changed;
    /// nil when nothing changed or anything failed (the current pool stays).
    func refreshIfDue() async -> [PoolCard]? {
        _ = cards()
        if let stored, now().timeIntervalSince(stored.checkedAt) < Self.refreshInterval { return nil }
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 20
        request.setValue("HSBGMacOverlay/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let etag = stored?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await http(request), let reply = response as? HTTPURLResponse else { return nil }
        if reply.statusCode == 304, var current = stored {
            current.checkedAt = now()
            save(current)
            return nil
        }
        guard (200..<300).contains(reply.statusCode), data.count <= Self.maxDownload,
              let cards = try? TavernPool.parse(hearthstoneJSON: data), TavernPool.isPlausible(cards) else { return nil }
        let changed = cards != (stored?.cards ?? seed())
        save(.init(etag: reply.value(forHTTPHeaderField: "ETag"), checkedAt: now(), cards: cards))
        return changed ? cards : nil
    }

    private func save(_ value: TavernPoolCache.Stored) {
        stored = value
        cache.save(value)
    }
}
