import Foundation

/// One column of a tier's list: the minions of one tribe, the amalgams, the minions with no tribe, or spells.
struct TavernGroup: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case tribe(String)
        case amalgams
        case noTribe
        case spells
    }

    var kind: Kind
    var cards: [PoolCard]

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .tribe(let tribe): TribeNames.plural(tribe)
        case .amalgams: "All tribes"
        case .noTribe: "No tribe"
        case .spells: "Spells"
        }
    }

    /// The tribe whose colour and glyph head the column; nil for the others.
    var tribe: String? {
        switch kind {
        case .tribe(let tribe): tribe
        case .amalgams: "ALL"
        case .noTribe, .spells: nil
        }
    }
}

/// Everything shown when pointing at one tier.
struct TavernSheet: Equatable, Sendable {
    var tier: Int
    var groups: [TavernGroup]
    /// Tribes left out of this lobby, by name; empty when the lobby is unknown.
    var missingTribes: [String] = []

    var minionCount: Int {
        groups.filter { $0.kind != .spells }.reduce(into: Set<String>()) { ids, group in
            group.cards.forEach { ids.insert($0.id) }
        }.count
    }
}

/// Builds the per-tier lists for one lobby. Pure, so it runs off the main thread and is tested directly.
enum TavernList {
    /// The strip's tiers. The pool also lists tier 7 cards, which a normal lobby never offers.
    static let shownTiers = 1...6

    /// `lobbyTribes` nil means the lobby is unknown: every tribe is shown.
    static func sheets(pool: [PoolCard], lobbyTribes: Set<String>?) -> [TavernSheet] {
        let tiers = Set(pool.map(\.tier)).filter(shownTiers.contains).sorted()
        let missing = lobbyTribes.map { lobby in
            Set(LiveTribes.raceNames.values).subtracting(lobby).sorted { TribeNames.plural($0) < TribeNames.plural($1) }
        } ?? []
        return tiers.map { tier in
            TavernSheet(tier: tier, groups: groups(pool.filter { $0.tier == tier }, lobbyTribes: lobbyTribes),
                        missingTribes: missing)
        }
    }

    /// Whether a card can be offered in this lobby.
    static func isInLobby(_ card: PoolCard, lobbyTribes: Set<String>?) -> Bool {
        guard let lobbyTribes else { return true }
        if card.races.contains("ALL") { return true }
        if !card.races.isEmpty { return card.races.contains(where: lobbyTribes.contains) }
        return card.associatedRaces.isEmpty || card.associatedRaces.contains(where: lobbyTribes.contains)
    }

    /// Tribe columns in name order, then amalgams, minions with no tribe, and spells; empty columns are
    /// left out. A dual-type minion appears under each of its tribes that is in the lobby.
    static func groups(_ cards: [PoolCard], lobbyTribes: Set<String>?) -> [TavernGroup] {
        var byTribe: [String: [PoolCard]] = [:]
        var amalgams: [PoolCard] = []
        var noTribe: [PoolCard] = []
        var spells: [PoolCard] = []
        for card in cards where isInLobby(card, lobbyTribes: lobbyTribes) {
            if card.isSpell {
                spells.append(card)
            } else if card.races.contains("ALL") {
                amalgams.append(card)
            } else if card.races.isEmpty {
                noTribe.append(card)
            } else {
                for race in Set(card.races) where lobbyTribes?.contains(race) ?? true {
                    byTribe[race, default: []].append(card)
                }
            }
        }
        let byName: (PoolCard, PoolCard) -> Bool = { ($0.name, $0.id) < ($1.name, $1.id) }
        var result = byTribe.keys
            .sorted { TribeNames.plural($0) < TribeNames.plural($1) }
            .map { TavernGroup(kind: .tribe($0), cards: byTribe[$0, default: []].sorted(by: byName)) }
        if !amalgams.isEmpty { result.append(TavernGroup(kind: .amalgams, cards: amalgams.sorted(by: byName))) }
        if !noTribe.isEmpty { result.append(TavernGroup(kind: .noTribe, cards: noTribe.sorted(by: byName))) }
        if !spells.isEmpty { result.append(TavernGroup(kind: .spells, cards: spells.sorted(by: byName))) }
        return result
    }

    /// The lobby's tribes from the game's TAG_RACE ids; nil (show all) when the read looks wrong.
    static func lobbyTribes(fromRaceIDs ids: [Int]) -> Set<String>? {
        let ids = ids.filter { $0 != LiveTribes.allRaceID }
        let names = ids.compactMap { LiveTribes.raceNames[$0] }
        // A Solo lobby has a handful of tribes; anything else is a misread.
        guard names.count == ids.count, (3...10).contains(names.count), Set(names).count == names.count else { return nil }
        return Set(names)
    }
}
