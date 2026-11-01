import Foundation

struct BattlegroundsPlayer: Identifiable, Equatable, Sendable {
    let id: Int
    var name: String = ""
    var heroCardID: String?
    var tavernTier: Int?
    /// Maximum health (the hero's HEALTH tag), with the DAMAGE and ARMOR tags of the leaderboard hero.
    var health: Int?
    var damageTaken = 0
    var armor = 0
    /// Points of health and armor lost in the last combat (0 when not hurt); nil before the first combat.
    var lastCombatDamage: Int?
    /// Combats between this player and the local player, oldest first (the local player's view).
    var fightsWithYou: [FightWithYou] = []
    var placement: Int?
    var rating: Int?
    var isLocalPlayer: Bool = false
    /// Combat rounds without losing. The log cannot tell a win from a tie.
    var wins = 0
    var losses = 0
    /// Current run: positive for rounds without a loss, negative for losses in a row.
    var streak = 0
    var triples: Int?
    /// Game turns on which a triple was seen, oldest first. Only turns actually seen: a count that jumps by
    /// more than one (read late) adds none, so this can hold fewer turns than `triples`.
    var tripleTurns: [Int] = []
    /// Turn on which the current tavern tier was reached.
    var tierReachedTurn: Int?
    /// Tribe counts from this player's board the last time the local player fought them.
    var lastSeenTribes: [String: Int] = [:]
    var lastSeenTurn: Int?
    /// Minions on that board and the highest tavern tier among them.
    var lastBoardSize: Int?
    var lastBoardTier: Int?
    /// The minions of that board, left to right. `lastSeenTurn` is the turn it was captured.
    var lastBoardMinions: [BoardMinion] = []
    /// The leaderboard hero's entity id in Power.log; the key the game's own memory uses for this player.
    var heroEntityID: Int?
    /// Live minion-type counts read from game memory (tribe -> count, Amalgams already added to each tribe),
    /// nil when not available. Never mixed with `lastSeenTribes`, which is what the last fight showed.
    var liveTribes: [String: Int]?

    /// Rounds in a row without a loss (0 after a loss).
    var winStreak: Int { max(streak, 0) }
    /// Rounds lost in a row (0 after a round not lost).
    var lossStreak: Int { max(-streak, 0) }
}

/// One minion on a captured combat board: the card name (what the card art is looked up by).
struct BoardMinion: Equatable, Sendable, Hashable {
    let cardID: String
    let name: String
    let isGolden: Bool
}

extension BattlegroundsPlayer {
    /// Health left, armor not included; nil until the maximum is known.
    var currentHealth: Int? { health.map { $0 - damageTaken } }
}

/// One combat between the local player and an opponent that ended with a loser.
struct FightWithYou: Equatable, Sendable {
    /// True when the local player won. Draws are not recorded.
    let youWon: Bool
    let turn: Int
    /// Health and armor the loser lost, read from the loser's own hero.
    let damage: Int
}

struct BattlegroundsLobby: Equatable, Sendable {
    var isBattlegrounds = false
    var players: [BattlegroundsPlayer] = []
}

final class PowerLogParser {
    private struct Entity {
        let id: Int
        var name = ""
        var cardID = ""
        var tags: [String: String] = [:]
    }

    private var entities: [Int: Entity] = [:]
    private var players: [Int: BattlegroundsPlayer] = [:]
    private var playerIDByName: [String: Int] = [:]
    /// Names shared by several players cannot say which one a tag belongs to.
    private var ambiguousNames = Set<String>()
    private var playerEntityIDByPlayerID: [Int: Int] = [:]
    private var localPlayerEntityID: Int?
    private var cursorID: Int?
    private var cursorIndent = -1
    private(set) var localPlayerID: Int?
    private(set) var ghostPlayerID: Int?
    /// A Battlegrounds Solo match; Duos is reported separately and not labeled.
    private(set) var isBattlegrounds = false
    private(set) var isDuos = false
    private(set) var isGameOver = false
    /// From `BOARD_VISUAL_STATE` as the client plays it back (`PowerTaskList`), so it stays
    /// set until the combat animation ends. `GameState` clears it as soon as results arrive.
    private(set) var isInCombat = false

    /// The hero entity each player's leaderboard portrait shows; combat copies are ignored.
    private var leaderboardHeroByPlayerID: [Int: Int] = [:]
    // A combat round runs from BOARD_VISUAL_STATE=2 to the STEP=MAIN_CLEANUP after it;
    // the loser's hero takes its damage after the animation, inside that window.
    private var isRoundOpen = false
    private var hasCombatEnded = false
    private var roundParticipants = Set<Int>()
    private var roundLosers = Set<Int>()
    private var roundStart: [Int: Int] = [:]
    private var roundTurn = 0
    private var roundOpponentID: Int?
    private var hasSnapshotOpponentBoard = false
    /// Battlegrounds turn: the game entity's TURN counts each shop and combat phase.
    private(set) var turn = 0
    /// Counts CREATE_GAME lines, so callers can tell a new match began.
    private(set) var gamesStarted = 0

    /// Board state comes from `PowerTaskList` lines, which the client writes as it
    /// plays events back, so places and tiers change when the player sees them
    /// (combat results reach `GameState` up to a minute before the animation ends).
    /// `GameState` still supplies the game type, player names and game boundaries.
    func feed(_ line: String) {
        guard let separator = line.range(of: " - ") else { return }
        let source = line[..<separator.lowerBound]
        let body = String(line[separator.upperBound...])

        if source.contains("PowerTaskList.DebugPrintPower") {
            parsePower(body)
        } else if source.contains("GameState.DebugPrintGame") {
            parseGameDebug(body)
        } else if source.contains("GameState.DebugPrintPower") {
            parseGameStatePower(body)
        }
    }

    func feed<S: Sequence>(_ lines: S) where S.Element == String {
        lines.forEach(feed)
    }

    /// Leaderboard place of the next opponent, whose portrait the game pushes out
    /// of the rail; nil when unknown. The tag sits on the local player's entity.
    var nextOpponentPlace: Int? {
        guard let entityID = localPlayerEntityID,
              let tags = entities[entityID]?.tags,
              let opponentID = integer(tags["NEXT_OPPONENT_PLAYER_ID"]),
              opponentID > 0 else { return nil }
        return players[opponentID]?.placement
    }

    func snapshot() -> BattlegroundsLobby {
        let sortedPlayers = players.values.filter { $0.id != ghostPlayerID }.map { player -> BattlegroundsPlayer in
            var player = player
            player.heroEntityID = leaderboardHeroByPlayerID[player.id]
            return player
        }.sorted {
            ($0.placement ?? Int.max, $0.id) < ($1.placement ?? Int.max, $1.id)
        }
        return BattlegroundsLobby(isBattlegrounds: isBattlegrounds, players: sortedPlayers)
    }

    private func parseGameDebug(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("GameType=") {
            // Duos pairs teammates on the leaderboard, which the Solo layout cannot label.
            isDuos = trimmed.contains("BATTLEGROUNDS") && trimmed.contains("DUO")
            isBattlegrounds = trimmed.contains("BATTLEGROUNDS") && !isDuos
            return
        }

        guard let playerID = integer(after: "PlayerID=", in: trimmed),
              let nameRange = trimmed.range(of: "PlayerName=") else { return }
        let name = String(trimmed[nameRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let existing = playerIDByName[name], existing != playerID {
            ambiguousNames.insert(name)
        }
        playerIDByName[name] = playerID
        var player = players[playerID] ?? BattlegroundsPlayer(id: playerID)
        player.name = name
        player.isLocalPlayer = playerID == localPlayerID
        players[playerID] = player
    }

    private func parsePower(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let indent = body.prefix { $0 == " " || $0 == "\t" }.count

        if trimmed.hasPrefix("tag=") && indent > cursorIndent, let cursorID {
            if let tag = tagAndValue(trimmed) {
                updateEntity(cursorID: cursorID, tag: tag.name, value: tag.value, isLiveChange: false)
            }
            return
        }

        cursorID = nil
        cursorIndent = -1

        // The new game was already reset from GameState, which also brought its names.
        if trimmed == "CREATE_GAME" {
            return
        }

        if let player = playerRecord(trimmed) {
            var existing = players[player.playerID] ?? BattlegroundsPlayer(id: player.playerID)
            existing.isLocalPlayer = player.accountHi != 0
            players[player.playerID] = existing
            if player.accountHi != 0 {
                localPlayerID = player.playerID
                for id in players.keys {
                    players[id]?.isLocalPlayer = id == localPlayerID
                }
            } else {
                ghostPlayerID = player.playerID
            }
            if let entityID = player.entityID {
                playerEntityIDByPlayerID[player.playerID] = entityID
                if player.accountHi != 0 {
                    localPlayerEntityID = entityID
                }
                // The player's own tags follow on indented lines.
                entities[entityID] = entities[entityID] ?? Entity(id: entityID)
                cursorID = entityID
                cursorIndent = indent
            }
            return
        }

        if let entity = entityHeader(trimmed) {
            entities[entity.id] = entity.entity
            cursorID = entity.id
            cursorIndent = indent
            updatePlayer(from: entity.id, isLiveChange: false)
            return
        }

        if let tagChange = tagChange(trimmed) {
            if tagChange.reference == "GameEntity" {
                updateGameState(tag: tagChange.tag, value: tagChange.value)
            } else if let entityID = resolveEntityID(tagChange.reference) {
                updateEntity(cursorID: entityID, tag: tagChange.tag, value: tagChange.value, isLiveChange: true)
            }
        }
    }

    private func updateGameState(tag: String, value: String) {
        switch tag {
        case "STEP" where value == "FINAL_GAMEOVER":
            isGameOver = true
        case "STEP" where value == "MAIN_CLEANUP":
            if isRoundOpen && hasCombatEnded {
                finishRound()
            }
        case "TURN":
            if let value = Int(value) {
                turn = (value + 1) / 2
            }
        case "BOARD_VISUAL_STATE":
            isInCombat = value == "2"
            if isInCombat && !isRoundOpen {
                startRound()
            } else if !isInCombat && isRoundOpen {
                hasCombatEnded = true
            }
        default:
            break
        }
    }

    private func startRound() {
        isRoundOpen = true
        hasCombatEnded = false
        hasSnapshotOpponentBoard = false
        roundLosers.removeAll()
        roundOpponentID = nil
        roundTurn = turn
        // Only players still alive fight this round.
        roundParticipants = Set(leaderboardHeroByPlayerID.compactMap { playerID, entityID in
            guard playerID != ghostPlayerID, let tags = entities[entityID]?.tags else { return nil }
            let remaining = (integer(tags["HEALTH"]) ?? 0) - (integer(tags["DAMAGE"]) ?? 0) + (integer(tags["ARMOR"]) ?? 0)
            return remaining > 0 ? playerID : nil
        })
        roundStart = Dictionary(uniqueKeysWithValues: roundParticipants.compactMap { id in
            totalHealth(of: id).map { (id, $0) }
        })
    }

    /// Health plus armor on the player's leaderboard hero.
    private func totalHealth(of playerID: Int) -> Int? {
        guard let tags = leaderboardHeroByPlayerID[playerID].flatMap({ entities[$0]?.tags }),
              let health = integer(tags["HEALTH"]) else { return nil }
        return health - (integer(tags["DAMAGE"]) ?? 0) + (integer(tags["ARMOR"]) ?? 0)
    }

    /// The opponent's combat board is controlled by the stand-in player (the one
    /// without an account); its hero copy carries the real opponent's PLAYER_ID.
    /// Taken at the first attack: after start-of-combat effects, before deaths.
    private func snapshotOpponentBoard() {
        hasSnapshotOpponentBoard = true
        guard let side = ghostPlayerID.map(String.init) else { return }
        let inPlay = entities.values.filter { $0.tags["ZONE"] == "PLAY" && $0.tags["CONTROLLER"] == side }
        guard let hero = inPlay.filter({ $0.tags["CARDTYPE"] == "HERO" }).min(by: { $0.id < $1.id }),
              let opponentID = integer(hero.tags["PLAYER_ID"]), opponentID > 0,
              var player = players[opponentID] else { return }

        var tribes: [String: Int] = [:]
        var amalgams = 0
        for minion in inPlay where minion.tags["CARDTYPE"] == "MINION" {
            switch minion.tags["CARDRACE"] {
            case "ALL": amalgams += 1
            case let race? where race != "INVALID": tribes[race, default: 0] += 1
            default: break
            }
        }
        // Amalgams belong to every tribe.
        if tribes.isEmpty && amalgams > 0 {
            tribes["ALL"] = amalgams
        } else {
            for race in tribes.keys { tribes[race, default: 0] += amalgams }
        }
        roundOpponentID = opponentID
        player.lastSeenTribes = tribes
        player.lastSeenTurn = turn
        let minions = inPlay.filter { $0.tags["CARDTYPE"] == "MINION" }
        player.lastBoardSize = minions.count
        player.lastBoardMinions = minions
            .sorted { (integer($0.tags["ZONE_POSITION"]) ?? Int.max, $0.id) < (integer($1.tags["ZONE_POSITION"]) ?? Int.max, $1.id) }
            .compactMap { minion in
                let name = minion.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !name.uppercased().hasPrefix("UNKNOWN") else { return nil }
                return BoardMinion(cardID: minion.cardID, name: name, isGolden: minion.tags["PREMIUM"] == "1")
            }
        player.lastBoardTier = minions.compactMap { integer($0.tags["TECH_LEVEL"]) }.max()
        players[opponentID] = player
    }

    private func finishRound() {
        var lost: [Int: Int] = [:]
        for playerID in roundParticipants {
            guard var player = players[playerID] else { continue }
            if let before = roundStart[playerID], let after = totalHealth(of: playerID) {
                lost[playerID] = max(before - after, 0)
                player.lastCombatDamage = lost[playerID]
            }
            if roundLosers.contains(playerID) {
                player.losses += 1
                player.streak = min(player.streak, 0) - 1
            } else {
                player.wins += 1
                player.streak = max(player.streak, 0) + 1
            }
            players[playerID] = player
        }
        recordFightWithLocalPlayer(lost: lost)
        isRoundOpen = false
        hasCombatEnded = false
    }

    /// Only decisive fights between the local player and the opponent whose board was seen.
    private func recordFightWithLocalPlayer(lost: [Int: Int]) {
        guard let you = localPlayerID, let opponent = roundOpponentID, opponent != you,
              roundParticipants.contains(you), roundParticipants.contains(opponent),
              var other = players[opponent] else { return }
        let youLost = roundLosers.contains(you), theyLost = roundLosers.contains(opponent)
        guard youLost != theyLost else { return }
        let damage = lost[youLost ? you : opponent] ?? 0
        other.fightsWithYou.append(FightWithYou(youWon: theyLost, turn: roundTurn, damage: damage))
        players[opponent] = other
    }

    /// GameState lines run ahead of playback; only game boundaries are taken from them.
    private func parseGameStatePower(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "CREATE_GAME" {
            gamesStarted += 1
            entities.removeAll()
            players.removeAll()
            playerIDByName.removeAll()
            ambiguousNames.removeAll()
            playerEntityIDByPlayerID.removeAll()
            localPlayerEntityID = nil
            localPlayerID = nil
            ghostPlayerID = nil
            cursorID = nil
            cursorIndent = -1
            isBattlegrounds = false
            isDuos = false
            isGameOver = false
            isInCombat = false
            leaderboardHeroByPlayerID.removeAll()
            isRoundOpen = false
            hasCombatEnded = false
            roundParticipants.removeAll()
            roundLosers.removeAll()
            roundStart.removeAll()
            roundOpponentID = nil
            hasSnapshotOpponentBoard = false
            turn = 0
        } else if let change = tagChange(trimmed), change.reference == "GameEntity",
                  change.tag == "STEP", change.value == "FINAL_GAMEOVER" {
            isGameOver = true
        }
    }

    // The log prints tags it has no name for as numbers; keep one spelling.
    private static let tagNamesByNumber = ["1360": "NEXT_OPPONENT_PLAYER_ID"]

    /// `isLiveChange`: a TAG_CHANGE (something happening now) rather than a tag listed in an entity's
    /// creation block, which after a reconnect replays the whole state at once.
    private func updateEntity(cursorID: Int, tag: String, value: String, isLiveChange: Bool) {
        guard var entity = entities[cursorID] else { return }
        if isRoundOpen, tag == "DAMAGE" || tag == "ARMOR",
           let playerID = integer(entity.tags["PLAYER_ID"]),
           leaderboardHeroByPlayerID[playerID] == cursorID,
           let new = Int(value) {
            let old = integer(entity.tags[tag]) ?? 0
            // Losing a fight costs health, or armor first.
            if (tag == "DAMAGE" && new > old) || (tag == "ARMOR" && new < old) {
                roundLosers.insert(playerID)
            }
        }
        entity.tags[Self.tagNamesByNumber[tag] ?? tag] = value
        entities[cursorID] = entity
        updatePlayer(from: cursorID, isLiveChange: isLiveChange)
        if isRoundOpen && !hasSnapshotOpponentBoard && tag == "ATTACKING" && value == "1" {
            snapshotOpponentBoard()
        }
    }

    /// Turns (tier reached, triples) are only recorded for changes seen happening: a live change, or a step up
    /// from a value already known. A value first seen in a creation block (a reconnect rebuilding the game, or
    /// a log read late) keeps its turn unknown rather than taking the current turn.
    private func updatePlayer(from entityID: Int, isLiveChange: Bool) {
        guard let entity = entities[entityID],
              let playerID = integer(entity.tags["PLAYER_ID"]), playerID > 0 else { return }

        var player = players[playerID] ?? BattlegroundsPlayer(id: playerID)
        // A replacement hero entity starts at tech level 0; keep the last known tier.
        if let tier = integer(entity.tags["PLAYER_TECH_LEVEL"]), tier > 0 {
            if tier > (player.tavernTier ?? 0) {
                let isSeen = (isLiveChange || player.tavernTier != nil) && turn > 0
                player.tierReachedTurn = isSeen ? turn : nil
            }
            player.tavernTier = tier
        }
        if let placement = integer(entity.tags["PLAYER_LEADERBOARD_PLACE"]), placement > 0 {
            player.placement = placement
            if entity.tags["CARDTYPE"] == "HERO", !entity.cardID.isEmpty {
                player.heroCardID = entity.cardID
                leaderboardHeroByPlayerID[playerID] = entityID
            }
        }
        // Combat copies of a hero carry other values; health comes from the leaderboard hero only.
        if leaderboardHeroByPlayerID[playerID] == entityID {
            if let health = integer(entity.tags["HEALTH"]) { player.health = health }
            player.damageTaken = integer(entity.tags["DAMAGE"]) ?? 0
            player.armor = integer(entity.tags["ARMOR"]) ?? 0
        }
        if let triples = integer(entity.tags["PLAYER_TRIPLES"]), triples > (player.triples ?? 0) {
            if triples == (player.triples ?? 0) + 1, isLiveChange || player.triples != nil, turn > 0 {
                player.tripleTurns.append(turn)
            }
            player.triples = triples
        }
        player.isLocalPlayer = playerID == localPlayerID
        players[playerID] = player
    }

    private func resolveEntityID(_ reference: String) -> Int? {
        if let id = integer(reference) { return id }
        if let id = integer(after: "id=", in: reference) { return id }
        // Player entities are referenced by their name, e.g. `Entity=Name#1234`.
        guard !ambiguousNames.contains(reference) else { return nil }
        return playerIDByName[reference].flatMap { playerEntityIDByPlayerID[$0] }
    }

    /// `FULL_ENTITY - Creating ID=27 CardID=…` in GameState; in playback the same
    /// event reads `FULL_ENTITY - Updating [entityName=… id=27 …] CardID=…`.
    private func entityHeader(_ body: String) -> (id: Int, entity: Entity)? {
        guard ["FULL_ENTITY", "SHOW_ENTITY", "CHANGE_ENTITY"].contains(where: body.hasPrefix),
              let id = integer(after: "Creating ID=", in: body) ?? integer(after: " id=", in: body)
        else { return nil }
        var entity = entities[id] ?? Entity(id: id)
        if let cardRange = body.range(of: "CardID=") {
            entity.cardID = String(body[cardRange.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
        }
        if let name = text(after: "entityName=", before: " id=", in: body) {
            entity.name = name
        }
        return (id, entity)
    }

    private func playerRecord(_ body: String) -> (playerID: Int, entityID: Int?, accountHi: Int)? {
        guard body.hasPrefix("Player "),
              let playerID = integer(after: "PlayerID=", in: body),
              let accountHi = integer(after: "hi=", in: body) else { return nil }
        return (playerID, integer(after: "EntityID=", in: body), accountHi)
    }

    private func tagChange(_ body: String) -> (reference: String, tag: String, value: String)? {
        guard body.hasPrefix("TAG_CHANGE Entity="),
              let tagRange = body.range(of: " tag=") else { return nil }
        let reference = String(body[body.index(body.startIndex, offsetBy: 18)..<tagRange.lowerBound])
        let remainder = String(body[tagRange.upperBound...])
        guard let valueRange = remainder.range(of: " value=") else { return nil }
        let tag = String(remainder[..<valueRange.lowerBound])
        let value = String(remainder[valueRange.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
        return (reference, tag, value)
    }

    private func tagAndValue(_ body: String) -> (name: String, value: String)? {
        guard let valueRange = body.range(of: " value=") else { return nil }
        let name = String(body[body.index(body.startIndex, offsetBy: 4)..<valueRange.lowerBound])
        let value = String(body[valueRange.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
        return (name, value)
    }

    private func integer(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value)
    }

    private func integer(after marker: String, in value: String) -> Int? {
        guard let range = value.range(of: marker) else { return nil }
        let suffix = value[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private func text(after start: String, before end: String, in value: String) -> String? {
        guard let startRange = value.range(of: start),
              let endRange = value.range(of: end, range: startRange.upperBound..<value.endIndex) else { return nil }
        return String(value[startRange.upperBound..<endRange.lowerBound])
    }
}
