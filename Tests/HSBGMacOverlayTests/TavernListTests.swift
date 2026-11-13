import XCTest
@testable import HSBGMacOverlay

final class TavernPoolTests: XCTestCase {
    /// A slice of HearthstoneJSON's cards.json, in its own field names (values trimmed, names real).
    private let sample = """
    [
     {"id":"BG20_100","name":"Razorfen Geomancer","type":"MINION","techLevel":1,"race":"QUILBOAR","races":["QUILBOAR"],
      "mechanics":["BATTLECRY"],"attack":2,"health":1,"cost":0,"isBattlegroundsPoolMinion":true,"set":"BATTLEGROUNDS"},
     {"id":"BG_X1","name":"Treasure Parrot","type":"MINION","techLevel":3,"races":["BEAST","PIRATE"],
      "mechanics":["TRIGGER_VISUAL","DEATHRATTLE","TAUNT"],"attack":3,"health":4,"isBattlegroundsPoolMinion":true},
     {"id":"BG_X2","name":"Duos Buddy","type":"MINION","techLevel":2,"races":["BEAST"],"isBattlegroundsPoolMinion":true,
      "isBattlegroundsDuosExclusive":true},
     {"id":"BG_X3","name":"Wealthy Bounty","type":"BATTLEGROUND_SPELL","techLevel":2,"cost":2,"isBattlegroundsPoolSpell":true,
      "battlegroundsAssociatedRaces":["PIRATE"],"mechanics":["DISCOVER"]},
     {"id":"BG_X4","name":"Not In Pool","type":"MINION","techLevel":1,"races":["MURLOC"]},
     {"id":"BG_X5","name":"Bad Tier","type":"MINION","techLevel":9,"isBattlegroundsPoolMinion":true},
     {"id":"HERO_01","name":"A hero","type":"HERO"},
     {"id":"BG_X6","name":"Old Single Race","type":"MINION","techLevel":1,"race":"MURLOC","isBattlegroundsPoolMinion":true}
    ]
    """

    func testKeepsSoloPoolMinionsAndSpellsOnly() throws {
        let cards = try TavernPool.parse(hearthstoneJSON: Data(sample.utf8))
        XCTAssertEqual(cards.map(\.name), ["Old Single Race", "Razorfen Geomancer", "Wealthy Bounty", "Treasure Parrot"])
    }

    func testKeepsWhatTheListDraws() throws {
        let cards = try TavernPool.parse(hearthstoneJSON: Data(sample.utf8))
        let parrot = try XCTUnwrap(cards.first { $0.name == "Treasure Parrot" })
        XCTAssertEqual(parrot.races, ["BEAST", "PIRATE"])
        XCTAssertEqual(parrot.mechanics, ["DEATHRATTLE", "TAUNT"])
        XCTAssertEqual(parrot.shownMechanics, [.deathrattle, .taunt])
        XCTAssertEqual(parrot.attack, 3)
        XCTAssertNil(parrot.cost)
        let bounty = try XCTUnwrap(cards.first { $0.name == "Wealthy Bounty" })
        XCTAssertTrue(bounty.isSpell)
        XCTAssertEqual(bounty.cost, 2)
        XCTAssertEqual(bounty.associatedRaces, ["PIRATE"])
        XCTAssertNil(bounty.attack)
        // `race` alone (older entries) still gives the type.
        XCTAssertEqual(cards.first { $0.name == "Old Single Race" }?.races, ["MURLOC"])
    }

    func testRejectsSomethingThatIsNotACardList() {
        XCTAssertThrowsError(try TavernPool.parse(hearthstoneJSON: Data("{\"error\":1}".utf8)))
    }

    func testOnlyAFullLookingPoolIsPlausible() throws {
        let cards = try TavernPool.parse(hearthstoneJSON: Data(sample.utf8))
        XCTAssertFalse(TavernPool.isPlausible(cards))
        XCTAssertTrue(TavernPool.isPlausible(TavernPoolSeed.cards))
        XCTAssertFalse(TavernPool.isPlausible(TavernPoolSeed.cards.filter { $0.tier != 6 }))
    }

    func testTheBuiltInSeedDecodes() {
        let seed = TavernPoolSeed.cards
        XCTAssertEqual(seed.filter { !$0.isSpell }.count, 273)
        XCTAssertGreaterThan(seed.filter(\.isSpell).count, 50)
        XCTAssertEqual(Set(seed.map(\.id)).count, seed.count)
        XCTAssertTrue(seed.allSatisfy { TavernPool.tiers.contains($0.tier) && !$0.name.isEmpty })
    }
}

final class TavernListTests: XCTestCase {
    private func minion(_ name: String, tier: Int = 1, _ races: [String] = [], associated: [String] = [],
                        mechanics: [String] = []) -> PoolCard {
        PoolCard(id: name, name: name, tier: tier, isSpell: false, races: races, associatedRaces: associated,
                 mechanics: mechanics, attack: 1, health: 1, cost: nil)
    }

    private func spell(_ name: String, tier: Int = 1, associated: [String] = []) -> PoolCard {
        PoolCard(id: name, name: name, tier: tier, isSpell: true, races: [], associatedRaces: associated,
                 mechanics: [], attack: nil, health: nil, cost: 1)
    }

    private lazy var pool: [PoolCard] = [
        minion("Zebra", ["BEAST"]), minion("Ape", ["BEAST"]), minion("Gearfin", ["MECHANICAL", "MURLOC"]),
        minion("Seer", ["DEMON", "NAGA"]), minion("Amalgam", ["ALL"]), minion("Plain"),
        minion("Graverobber", associated: ["UNDEAD"]), minion("Bubble", ["MURLOC"]),
        spell("Shiny Ring"), spell("Bounty", associated: ["PIRATE"]), minion("Big", tier: 4, ["BEAST"]),
    ]

    private func titles(_ groups: [TavernGroup]) -> [String] { groups.map(\.title) }
    private func names(_ group: TavernGroup?) -> [String] { group?.cards.map(\.name) ?? [] }

    func testUnknownLobbyShowsEveryTribeThenAmalgamsNoTribeAndSpells() {
        let groups = TavernList.groups(pool.filter { $0.tier == 1 }, lobbyTribes: nil)
        XCTAssertEqual(titles(groups), ["Beasts", "Demons", "Mechs", "Murlocs", "Nagas", "All tribes", "No tribe", "Spells"])
        XCTAssertEqual(names(groups.first), ["Ape", "Zebra"])
        XCTAssertEqual(names(groups.first { $0.kind == .noTribe }), ["Graverobber", "Plain"])
        XCTAssertEqual(names(groups.first { $0.kind == .spells }), ["Bounty", "Shiny Ring"])
    }

    func testOnlyTheLobbysTribesAndTheirCards() {
        let groups = TavernList.groups(pool.filter { $0.tier == 1 }, lobbyTribes: ["BEAST", "MURLOC", "DEMON"])
        XCTAssertEqual(titles(groups), ["Beasts", "Demons", "Murlocs", "All tribes", "No tribe", "Spells"])
        // A dual-type minion shows under its tribe that is in, not under the one that is out.
        XCTAssertEqual(names(groups.first { $0.kind == .tribe("MURLOC") }), ["Bubble", "Gearfin"])
        XCTAssertEqual(names(groups.first { $0.kind == .tribe("DEMON") }), ["Seer"])
        // A no-tribe minion or spell tied to a tribe that is out is not in the pool.
        XCTAssertEqual(names(groups.first { $0.kind == .noTribe }), ["Plain"])
        XCTAssertEqual(names(groups.first { $0.kind == .spells }), ["Shiny Ring"])
    }

    func testDualTypeMinionShowsUnderBothTribesButCountsOnce() {
        let sheets = TavernList.sheets(pool: pool, lobbyTribes: ["DEMON", "NAGA"])
        let tier1 = sheets[0]
        XCTAssertEqual(names(tier1.groups.first { $0.kind == .tribe("DEMON") }), ["Seer"])
        XCTAssertEqual(names(tier1.groups.first { $0.kind == .tribe("NAGA") }), ["Seer"])
        XCTAssertEqual(tier1.minionCount, 3)   // Seer, Amalgam, Plain
        XCTAssertEqual(tier1.missingTribes.first, "ABERRATION")
        XCTAssertEqual(tier1.missingTribes.count, 9)
        XCTAssertFalse(tier1.missingTribes.contains("DEMON"))
        XCTAssertEqual(TavernList.sheets(pool: pool, lobbyTribes: nil)[0].missingTribes, [])
    }

    func testOneSheetPerTierPresentInOrder() {
        let sheets = TavernList.sheets(pool: pool, lobbyTribes: ["MURLOC"])
        XCTAssertEqual(sheets.map(\.tier), [1, 4])
        // Tier 4 has only a Beast, which is out: the sheet is empty rather than missing.
        XCTAssertEqual(sheets[1].groups, [])
    }

    func testLobbyTribesFromRaceIDsRejectMisreads() {
        XCTAssertEqual(TavernList.lobbyTribes(fromRaceIDs: [20, 24, 17, 23, 11]), ["BEAST", "DRAGON", "MECHANICAL", "PIRATE", "UNDEAD"])
        // The amalgam id is ignored if the game ever includes it.
        XCTAssertEqual(TavernList.lobbyTribes(fromRaceIDs: [20, 24, 26, 17, 23, 11])?.count, 5)
        XCTAssertNil(TavernList.lobbyTribes(fromRaceIDs: []))
        XCTAssertNil(TavernList.lobbyTribes(fromRaceIDs: [20, 24]))
        XCTAssertNil(TavernList.lobbyTribes(fromRaceIDs: [20, 24, 999, 17, 23]))
        XCTAssertNil(TavernList.lobbyTribes(fromRaceIDs: [20, 20, 24, 17, 23]))
    }

    func testRealPoolWithAFiveTribeLobby() {
        let sheets = TavernList.sheets(pool: TavernPoolSeed.cards, lobbyTribes: ["BEAST", "DRAGON", "MECHANICAL", "PIRATE", "UNDEAD"])
        XCTAssertEqual(sheets.map(\.tier), [1, 2, 3, 4, 5, 6, 7])
        for sheet in sheets {
            let tribes = sheet.groups.compactMap { group -> String? in
                if case .tribe(let tribe) = group.kind { return tribe } else { return nil }
            }
            XCTAssertTrue(Set(tribes).isSubset(of: ["BEAST", "DRAGON", "MECHANICAL", "PIRATE", "UNDEAD"]))
            XCTAssertFalse(sheet.groups.contains { $0.cards.isEmpty })
        }
    }
}

final class TavernPoolStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tavern-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var cache: TavernPoolCache { TavernPoolCache(fileURL: directory.appendingPathComponent("tavern-pool.json")) }

    private static func response(_ status: Int, etag: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: TavernPoolStore.url, statusCode: status, httpVersion: nil,
                        headerFields: etag.map { ["ETag": $0] })!
    }

    /// The seed in HearthstoneJSON's own shape, so the store's download path parses real-looking data.
    private func fullJSON(dropping name: String? = nil) throws -> Data {
        let raw = TavernPoolSeed.cards.filter { $0.name != name }.map { card -> [String: Any] in
            var entry: [String: Any] = ["id": card.id, "name": card.name, "techLevel": card.tier, "mechanics": card.mechanics,
                                        "races": card.races, "battlegroundsAssociatedRaces": card.associatedRaces]
            entry[card.isSpell ? "isBattlegroundsPoolSpell" : "isBattlegroundsPoolMinion"] = true
            if let attack = card.attack { entry["attack"] = attack }
            if let health = card.health { entry["health"] = health }
            if let cost = card.cost { entry["cost"] = cost }
            return entry
        }
        return try JSONSerialization.data(withJSONObject: raw)
    }

    func testFirstRunUsesTheSeedThenSavesADownloadWithItsETag() async throws {
        let first = TavernPoolSeed.cards.first!.name
        let body = try fullJSON(dropping: first)
        let store = TavernPoolStore(cache: cache, http: { _ in (body, Self.response(200, etag: "\"v2\"")) })
        let before = await store.cards()
        XCTAssertEqual(before, TavernPoolSeed.cards)
        let updated = await store.refreshIfDue()
        XCTAssertEqual(updated?.count, TavernPoolSeed.cards.count - 1)
        XCTAssertEqual(cache.load()?.etag, "\"v2\"")
        XCTAssertEqual(cache.load()?.cards.count, TavernPoolSeed.cards.count - 1)
    }

    func testSendsTheETagAndA304KeepsThePool() async throws {
        let old = Date(timeIntervalSince1970: 1_000)
        cache.save(.init(etag: "\"v1\"", checkedAt: old, cards: TavernPoolSeed.cards))
        let sent = LockedBox<String?>(nil)
        let store = TavernPoolStore(cache: cache, http: { request in
            sent.value = request.value(forHTTPHeaderField: "If-None-Match")
            return (Data(), Self.response(304))
        }, now: { old.addingTimeInterval(13 * 3600) })
        let updated = await store.refreshIfDue()
        XCTAssertNil(updated)
        XCTAssertEqual(sent.value, "\"v1\"")
        XCTAssertEqual(cache.load()?.checkedAt, old.addingTimeInterval(13 * 3600))
    }

    func testNoRequestWhenCheckedRecently() async {
        let now = Date(timeIntervalSince1970: 5_000_000)
        cache.save(.init(etag: "\"v1\"", checkedAt: now.addingTimeInterval(-3600), cards: TavernPoolSeed.cards))
        let calls = LockedBox(0)
        let store = TavernPoolStore(cache: cache, http: { _ in
            calls.value += 1
            return (Data(), Self.response(500))
        }, now: { now })
        let updated = await store.refreshIfDue()
        XCTAssertNil(updated)
        XCTAssertEqual(calls.value, 0)
    }

    func testBadDownloadsKeepTheCurrentPool() async throws {
        let truncated = try JSONSerialization.data(withJSONObject: [["id": "X", "name": "Lone", "techLevel": 1,
                                                                      "isBattlegroundsPoolMinion": true]])
        for (body, status) in [(Data("oops".utf8), 200), (truncated, 200), (try fullJSON(), 503)] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("tavern-pool.json"))
            let store = TavernPoolStore(cache: cache, http: { _ in (body, Self.response(status)) })
            let updated = await store.refreshIfDue()
            XCTAssertNil(updated)
            let current = await store.cards()
            XCTAssertEqual(current, TavernPoolSeed.cards)
            XCTAssertEqual(cache.load()?.cards ?? TavernPoolSeed.cards, TavernPoolSeed.cards)
        }
    }

    func testAnAnswerWeCannotUseWaitsTheFullIntervalInsteadOfDownloadingEveryGame() async {
        let now = Date(timeIntervalSince1970: 5_000_000)
        let calls = LockedBox(0)
        let http: TavernPoolStore.HTTPFetch = { _ in
            calls.value += 1
            return (Data("a new format".utf8), Self.response(200))
        }
        _ = await TavernPoolStore(cache: cache, http: http, now: { now }).refreshIfDue()
        let next = await TavernPoolStore(cache: cache, http: http, now: { now.addingTimeInterval(3600) }).refreshIfDue()
        XCTAssertNil(next)
        XCTAssertEqual(calls.value, 1)
        XCTAssertNil(cache.load()?.etag, "no ETag kept from an answer we threw away")
    }

    func testAServerErrorIsRetriedAtTheNextGame() async {
        let calls = LockedBox(0)
        let http: TavernPoolStore.HTTPFetch = { _ in
            calls.value += 1
            return (Data(), Self.response(503))
        }
        _ = await TavernPoolStore(cache: cache, http: http).refreshIfDue()
        _ = await TavernPoolStore(cache: cache, http: http).refreshIfDue()
        XCTAssertEqual(calls.value, 2)
    }
}

/// A mutable value shared with a `@Sendable` closure in tests.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

final class TavernStripGeometryTests: XCTestCase {
    private let canvas = CGSize(width: 1920, height: 1080)

    func testTilesStandInARowAtTheTopOfTheSpaceRightOfTheBoard() {
        let tiles = TavernStripGeometry.tiles(tiers: [1, 2, 3, 4, 5, 6, 7], canvas: canvas)
        XCTAssertEqual(tiles.map(\.tier), [1, 2, 3, 4, 5, 6, 7])
        let boardRight = LeaderboardLayout.scaledX(1, width: canvas.width, height: canvas.height)
        XCTAssertTrue(tiles.allSatisfy { $0.frame.minX > boardRight && $0.frame.maxX <= canvas.width })
        XCTAssertTrue(tiles.allSatisfy { $0.frame.minY == tiles[0].frame.minY && $0.frame.maxY < canvas.height * 0.1 })
        XCTAssertTrue(zip(tiles, tiles.dropFirst()).allSatisfy { $0.frame.maxX < $1.frame.minX })
    }

    func testANarrowWindowKeepsTheStripInside() {
        let square = CGSize(width: 1000, height: 1000)
        let tiles = TavernStripGeometry.tiles(tiers: [1, 2, 3, 4, 5, 6, 7], canvas: square)
        XCTAssertTrue(tiles.allSatisfy { $0.frame.maxX <= square.width && $0.frame.minX > 0 && $0.frame.width >= 20 })
    }

    func testHitsOnlyInsideATile() {
        let tiles = TavernStripGeometry.tiles(tiers: [1, 2, 3], canvas: canvas)
        XCTAssertEqual(TavernStripGeometry.hitTier(at: CGPoint(x: tiles[1].frame.midX, y: tiles[1].frame.midY), in: tiles), 2)
        // The gap between two tiles is nothing, so sliding across never flashes a wrong tier.
        XCTAssertNil(TavernStripGeometry.hitTier(at: CGPoint(x: tiles[0].frame.maxX + 1, y: tiles[0].frame.midY), in: tiles))
        XCTAssertNil(TavernStripGeometry.hitTier(at: CGPoint(x: 10, y: 500), in: tiles))
    }

    func testListHangsUnderTheStripRightAligned() {
        let strip = CGRect(x: 1700, y: 30, width: 200, height: 45)
        let spot = TavernStripGeometry.placement(strip: strip, size: CGSize(width: 220, height: 600), canvas: canvas)
        XCTAssertEqual(spot.maxX, strip.maxX)
        XCTAssertGreaterThan(spot.minY, strip.maxY)
        // Two columns grow to the left, over the board edge, never off the window.
        let wide = TavernStripGeometry.placement(strip: strip, size: CGSize(width: 460, height: 600), canvas: canvas)
        XCTAssertEqual(wide.maxX, strip.maxX)
        let tall = TavernStripGeometry.placement(strip: strip, size: CGSize(width: 220, height: 2000), canvas: canvas)
        XCTAssertGreaterThanOrEqual(tall.minY, 0)
        XCTAssertLessThanOrEqual(TavernStripGeometry.maxListHeight(strip: strip, canvas: canvas), canvas.height - strip.maxY)
    }

    func testColumnsAreAtLeastReadable() {
        let square = CGSize(width: 1000, height: 1000)
        XCTAssertGreaterThanOrEqual(TavernStripGeometry.columnWidth(canvas: square, scale: 1), 210)
        let space = TavernStripGeometry.rightSpace(canvas: canvas)
        XCTAssertEqual(TavernStripGeometry.columnWidth(canvas: canvas, scale: 1), max(space.upperBound - space.lowerBound, 210), accuracy: 1)
    }

    func testTheCardGoesLeftOfTheListWhenThereIsRoom() {
        let size = CGSize(width: 168, height: 260)
        let row = CGRect(x: 700, y: 500, width: 150, height: 16)
        let roomy = TavernStripGeometry.cardPlacement(row: row, list: CGRect(x: 600, y: 300, width: 1000, height: 400), size: size, canvas: canvas)
        XCTAssertLessThanOrEqual(roomy.maxX, 600)
        XCTAssertEqual(roomy.midY, row.midY, accuracy: 1)
        let full = TavernStripGeometry.cardPlacement(row: row, list: CGRect(x: 0, y: 300, width: 1600, height: 400), size: size, canvas: canvas)
        XCTAssertEqual(full.minX, row.maxX + TavernStripGeometry.gap)
    }

    func testAClickOpensSwitchesAndClosesATier() {
        XCTAssertEqual(TavernStripGeometry.tierAfterClick(on: 1, open: nil), 1)
        XCTAssertEqual(TavernStripGeometry.tierAfterClick(on: 3, open: 1), 3)
        XCTAssertNil(TavernStripGeometry.tierAfterClick(on: 3, open: 3))
    }

    func testYourTierOpensAtEachShopAndWhenYouLevelUp() {
        let tiers = [1, 2, 3, 4, 5, 6]
        XCTAssertEqual(TavernStripGeometry.tierToFollow(current: 2, followed: nil, isNewShop: true, tiers: tiers), 2)
        // Same shop, same tier: leave it, so closing it or opening another tier sticks.
        XCTAssertNil(TavernStripGeometry.tierToFollow(current: 2, followed: 2, isNewShop: false, tiers: tiers))
        XCTAssertEqual(TavernStripGeometry.tierToFollow(current: 3, followed: 2, isNewShop: false, tiers: tiers), 3)
        XCTAssertEqual(TavernStripGeometry.tierToFollow(current: 3, followed: 3, isNewShop: true, tiers: tiers), 3)
        XCTAssertNil(TavernStripGeometry.tierToFollow(current: nil, followed: nil, isNewShop: true, tiers: tiers))
        XCTAssertNil(TavernStripGeometry.tierToFollow(current: 7, followed: 6, isNewShop: true, tiers: tiers))
        XCTAssertEqual(TavernStripGeometry.tierToFollow(current: 7, followed: 6, isNewShop: false, tiers: tiers + [7]), 7)
    }

    func testOpeningYourTierIsOffByDefault() {
        let defaults = UserDefaults(suiteName: "tavern-follow-\(UUID().uuidString)")!
        XCTAssertFalse(SettingsModel.opensOwnTavernTier(defaults))
        defaults.set(true, forKey: SettingsKey.opensOwnTavernTier)
        XCTAssertTrue(SettingsModel.opensOwnTavernTier(defaults))
    }

    func testOnlyTiersAboveYoursAreAhead() {
        XCTAssertTrue(TavernStripGeometry.isAhead(4, of: 3))
        XCTAssertFalse(TavernStripGeometry.isAhead(3, of: 3))
        XCTAssertFalse(TavernStripGeometry.isAhead(1, of: 3))
        XCTAssertFalse(TavernStripGeometry.isAhead(6, of: nil))
        XCTAssertFalse(TavernStripGeometry.isAhead(6, of: 0))
    }

    func testGroupsFillColumnsTopToBottomWithoutSplitting() {
        let columns = TavernStripGeometry.columns([100, 200, 150, 300, 50], height: { CGFloat($0) }, spacing: 10, maxHeight: 400)
        XCTAssertEqual(columns, [[100, 200], [150], [300, 50]])
        // A group taller than the window still gets its own column instead of vanishing.
        XCTAssertEqual(TavernStripGeometry.columns([500, 20], height: { CGFloat($0) }, spacing: 10, maxHeight: 400), [[500], [20]])
    }

    func testTwoColumnsAreBalancedInsteadOfOneFullAndOneNearlyEmpty() {
        // Tier 4 as seen live: tribes of 5, 4, 8, 5, 5 and 6 rows, then 12 spells (header + rows, 36 pt a row).
        let groups = [6, 5, 9, 6, 6, 7, 13].map { CGFloat($0 * 36) }
        let columns = TavernStripGeometry.columns(groups, height: { $0 }, spacing: 10, maxHeight: 1700)
        XCTAssertEqual(columns.count, 2)
        let heights = columns.map { $0.reduce(0, +) + CGFloat($0.count - 1) * 10 }
        XCTAssertLessThan(abs(heights[0] - heights[1]), 250, "\(heights)")
        XCTAssertEqual(columns.flatMap { $0 }, groups, "order kept")
        // One column when everything fits.
        XCTAssertEqual(TavernStripGeometry.columns([100, 100], height: { $0 }, spacing: 10, maxHeight: 400).count, 1)
    }

    func testTheSettingIsOnByDefault() {
        let defaults = UserDefaults(suiteName: "tavern-\(UUID().uuidString)")!
        XCTAssertTrue(SettingsModel.showsTavernList(defaults))
        defaults.set(false, forKey: SettingsKey.showsTavernList)
        XCTAssertFalse(SettingsModel.showsTavernList(defaults))
    }
}

final class TavernFilterTests: XCTestCase {
    private func card(_ name: String, _ races: [String] = [], mechanics: [String] = [], refs: [String] = [],
                      text: String = "", isSpell: Bool = false) -> PoolCard {
        PoolCard(id: name, name: name, tier: 1, isSpell: isSpell, races: races, associatedRaces: [], mechanics: mechanics,
                 referencedTags: refs, text: text)
    }

    private var sheet: TavernSheet {
        let cards = [
            card("Hound", ["BEAST"], mechanics: ["DEATHRATTLE"]),
            card("Seeker", ["BEAST"], text: "<b>Battlecry:</b> <b>Discover</b> a Beast."),
            card("Pirate", ["PIRATE"], text: "[x]Gain 1 $Gold."),
            card("Lonely", [], mechanics: ["BACON_RALLY"]),
            card("Coin", text: "Gain 2 Gold.", isSpell: true),
        ]
        return TavernSheet(tier: 1, groups: TavernList.groups(cards, lobbyTribes: ["BEAST", "PIRATE"]))
    }

    func testKeysReadMechanicsTagsAndText() {
        XCTAssertTrue(TavernFilterKey.deathrattle.matches(card("a", mechanics: ["DEATHRATTLE"])))
        XCTAssertTrue(TavernFilterKey.rally.matches(card("a", mechanics: ["BACON_RALLY"])))
        XCTAssertTrue(TavernFilterKey.discover.matches(card("a", text: "<b>Discover</b> a minion")))
        XCTAssertTrue(TavernFilterKey.bloodGems.matches(card("a", refs: ["BACON_BLOOD_GEM_TOOLTIP"])))
        XCTAssertTrue(TavernFilterKey.gold.matches(card("a", text: "[x]Gain 1 $Gold.")))
        XCTAssertFalse(TavernFilterKey.gold.matches(card("a", text: "Make a minion Golden.")))
        XCTAssertTrue(TavernFilterKey.spells.matches(card("a", text: "After you cast a spell, gain +1/+1.")))
        XCTAssertFalse(TavernFilterKey.spells.matches(card("a", text: "<b>Spellcraft:</b> give +2/+2.")))
        XCTAssertFalse(TavernFilterKey.taunt.matches(card("a", refs: ["TAUNT"], text: "Give a minion <b>Taunt</b>.")))
    }

    func testNoFilterKeepsEverything() {
        XCTAssertEqual(TavernFilter().apply(to: sheet), sheet)
        XCTAssertFalse(TavernFilter().isActive)
    }

    func testCardTypesKeepOnlyTheirGroups() {
        var filter = TavernFilter()
        filter.toggle(.tribe("BEAST"))
        XCTAssertEqual(filter.apply(to: sheet).groups.map(\.kind), [.tribe("BEAST")])
        filter.toggle(TavernGroup.Kind.spells)
        XCTAssertEqual(filter.apply(to: sheet).groups.map(\.kind), [.tribe("BEAST"), .spells])
        filter.toggle(.tribe("BEAST"))
        XCTAssertEqual(filter.apply(to: sheet).groups.map(\.kind), [.spells])
    }

    func testKeysKeepAnyMatchAndDropEmptyGroups() {
        let filter = TavernFilter(keys: [.gold, .discover])
        let groups = filter.apply(to: sheet).groups
        XCTAssertEqual(groups.map(\.kind), [.tribe("BEAST"), .tribe("PIRATE"), .spells])
        XCTAssertEqual(groups.first?.cards.map(\.name), ["Seeker"])
        let both = TavernFilter(kinds: [.tribe("PIRATE")], keys: [.gold])
        XCTAssertEqual(both.apply(to: sheet).groups.flatMap(\.cards).map(\.name), ["Pirate"])
        XCTAssertEqual(both.summary, "Pirates, Gold")
    }

    func testChoicesOnlyOfferWhatExistsWithCounts() {
        let choices = TavernFilter().choices(for: [sheet])
        XCTAssertEqual(choices.kinds, [.tribe("BEAST"), .tribe("PIRATE"), .noTribe, .spells])
        let counts = Dictionary(uniqueKeysWithValues: choices.keys.map { ($0.0, $0.1) })
        XCTAssertEqual(counts[.gold], 2)
        XCTAssertEqual(counts[.discover], 1)
        XCTAssertNil(counts[.taunt])
        // Counts follow the chosen card types; the types themselves stay offered.
        let beasts = TavernFilter(kinds: [.tribe("BEAST")]).choices(for: [sheet])
        XCTAssertEqual(beasts.kinds.count, 4)
        XCTAssertNil(beasts.keys.first { $0.0 == .gold })
    }

    func testTheFilterButtonSitsLeftOfTierOneInsideTheWindow() {
        let canvas = CGSize(width: 1920, height: 1080)
        let tiles = TavernStripGeometry.tiles(tiers: [1, 2, 3, 4, 5, 6, 7], canvas: canvas)
        let button = TavernStripGeometry.filterFrame(tiles: tiles)!
        XCTAssertLessThan(button.maxX, tiles[0].frame.minX)
        XCTAssertEqual(button.minY, tiles[0].frame.minY)
        XCTAssertGreaterThan(button.minX, LeaderboardLayout.scaledX(1, width: canvas.width, height: canvas.height))
        XCTAssertEqual(TavernStripGeometry.stripFrame(tiles: tiles)?.minX, button.minX)
        XCTAssertNil(TavernStripGeometry.hitTier(at: CGPoint(x: button.midX, y: button.midY), in: tiles))
    }

    func testTheSeedKeepsFilterData() {
        XCTAssertTrue(TavernPoolSeed.cards.contains { $0.mechanics.contains("BACON_RALLY") })
        XCTAssertTrue(TavernPoolSeed.cards.contains { TavernFilterKey.discover.matches($0) })
        XCTAssertFalse(TavernPoolSeed.cards.contains { $0.mechanics.contains("TRIGGER_VISUAL") })
    }
}
