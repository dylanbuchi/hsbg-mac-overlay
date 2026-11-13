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

/// One choice in the filter: a keyword the card has, or a synergy its text talks about.
enum TavernFilterKey: String, CaseIterable, Hashable, Sendable {
    case battlecry, deathrattle, divineShield, taunt, reborn, windfury, venomous, magnetic, avenge, rally
    case startOfCombat, endOfTurn, chooseOne, spellcraft, activate
    case discover, gold, spells, bloodGems, refresh

    static let keywords: [TavernFilterKey] = [.battlecry, .deathrattle, .divineShield, .taunt, .reborn, .windfury,
                                              .venomous, .magnetic, .avenge, .rally, .startOfCombat, .endOfTurn,
                                              .chooseOne, .spellcraft, .activate]
    static let synergies: [TavernFilterKey] = [.discover, .gold, .spells, .bloodGems, .refresh]

    var label: String {
        switch self {
        case .battlecry: "Battlecry"
        case .deathrattle: "Deathrattle"
        case .divineShield: "Divine Shield"
        case .taunt: "Taunt"
        case .reborn: "Reborn"
        case .windfury: "Windfury"
        case .venomous: "Venomous"
        case .magnetic: "Magnetic"
        case .avenge: "Avenge"
        case .rally: "Rally"
        case .startOfCombat: "Start of Combat"
        case .endOfTurn: "End of turn"
        case .chooseOne: "Choose One"
        case .spellcraft: "Spellcraft"
        case .activate: "Activate"
        case .discover: "Discover"
        case .gold: "Gold"
        case .spells: "Spell synergy"
        case .bloodGems: "Blood Gems"
        case .refresh: "Refresh"
        }
    }

    /// HearthstoneJSON mechanic for a keyword the card itself has.
    private var mechanic: String? {
        switch self {
        case .battlecry: "BATTLECRY"
        case .deathrattle: "DEATHRATTLE"
        case .divineShield: "DIVINE_SHIELD"
        case .taunt: "TAUNT"
        case .reborn: "REBORN"
        case .windfury: "WINDFURY"
        case .venomous: "VENOMOUS"
        case .magnetic: "MAGNETIC"
        case .avenge: "AVENGE"
        case .rally: "BACON_RALLY"
        case .startOfCombat: "START_OF_COMBAT"
        case .endOfTurn: "END_OF_TURN_TRIGGER"
        case .chooseOne: "CHOOSE_ONE"
        case .spellcraft: "BACON_SPELLCRAFT_ID"
        case .discover: "DISCOVER"
        case .activate, .gold, .spells, .bloodGems, .refresh: nil
        }
    }

    func matches(_ card: PoolCard) -> Bool {
        if let mechanic, card.mechanics.contains(mechanic) { return true }
        let text = { TavernFilterKey.plainText(card.text) }
        switch self {
        case .activate: return card.referencedTags.contains("BACON_ACTIVATE_TOOLTIP")
        case .discover: return card.referencedTags.contains("DISCOVER") || text().contains("discover")
        case .gold: return text().range(of: #"\bgold\b"#, options: .regularExpression) != nil
        case .spells: return text().range(of: #"\bspells?\b"#, options: .regularExpression) != nil
        case .bloodGems: return card.referencedTags.contains("BACON_BLOOD_GEM_TOOLTIP") || text().contains("blood gem")
        case .refresh: return card.referencedTags.contains("BACON_REFRESH_TOOLTIP") || text().contains("refresh")
        default: return false
        }
    }

    /// Card text without markup (`<b>`, `[x]`, `$`, `#`, line breaks), lowercased.
    static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]*>|\[x\]|[$#]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .lowercased()
    }
}

/// What the filter keeps: card types (tribes, amalgams, no tribe, spells) and keywords or synergies. Empty
/// sets keep everything; within a set any choice matches.
struct TavernFilter: Equatable, Hashable, Sendable {
    var kinds: Set<TavernGroup.Kind> = []
    var keys: Set<TavernFilterKey> = []

    var isActive: Bool { !kinds.isEmpty || !keys.isEmpty }

    mutating func toggle(_ kind: TavernGroup.Kind) {
        if kinds.remove(kind) == nil { kinds.insert(kind) }
    }

    mutating func toggle(_ key: TavernFilterKey) {
        if keys.remove(key) == nil { keys.insert(key) }
    }

    func apply(to sheet: TavernSheet) -> TavernSheet {
        guard isActive else { return sheet }
        var result = sheet
        result.groups = sheet.groups.compactMap { group in
            guard kinds.isEmpty || kinds.contains(group.kind) else { return nil }
            let cards = keys.isEmpty ? group.cards : group.cards.filter { card in keys.contains { $0.matches(card) } }
            return cards.isEmpty ? nil : TavernGroup(kind: group.kind, cards: cards)
        }
        return result
    }

    /// The choices, in the order the filter shows them, e.g. "Beasts, Discover".
    var summary: String {
        let order: [TavernGroup.Kind] = kinds.sorted { TavernFilter.rank($0) < TavernFilter.rank($1) }
        return (order.map { TavernGroup(kind: $0, cards: []).title }
                + TavernFilterKey.allCases.filter(keys.contains).map(\.label)).joined(separator: ", ")
    }

    private static func rank(_ kind: TavernGroup.Kind) -> String {
        switch kind {
        case .tribe(let tribe): "0" + TribeNames.plural(tribe)
        case .amalgams: "1"
        case .noTribe: "2"
        case .spells: "3"
        }
    }

    /// The card types and keys worth offering for these sheets (only what appears), with how many cards
    /// each key matches across all tiers within the chosen card types.
    func choices(for sheets: [TavernSheet]) -> (kinds: [TavernGroup.Kind], keys: [(TavernFilterKey, Int)]) {
        let kinds = Set(sheets.flatMap { $0.groups.map(\.kind) })
        var cards: [String: PoolCard] = [:]
        for sheet in sheets {
            for group in sheet.groups where self.kinds.isEmpty || self.kinds.contains(group.kind) {
                group.cards.forEach { cards[$0.id] = $0 }
            }
        }
        let keys = TavernFilterKey.allCases.map { key in (key, cards.values.filter(key.matches).count) }
            .filter { $0.1 > 0 }
        return (kinds.sorted { Self.rank($0) < Self.rank($1) }, keys)
    }
}
