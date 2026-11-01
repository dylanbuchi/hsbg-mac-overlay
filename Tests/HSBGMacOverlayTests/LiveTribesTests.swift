import XCTest
@testable import HSBGMacOverlay

final class LiveTribesTests: XCTestCase {
    private func player(_ id: Int, entity: Int? = nil, live: [String: Int]? = nil,
                        seen: [String: Int] = [:], seenTurn: Int? = nil) -> BattlegroundsPlayer {
        var p = BattlegroundsPlayer(id: id, name: "P\(id)")
        p.heroEntityID = entity
        p.liveTribes = live
        p.lastSeenTribes = seen
        p.lastSeenTurn = seenTurn
        return p
    }

    // MARK: raw counts -> tribes

    func testRaceIdsMapToLogNames() {
        XCTAssertEqual(LiveTribes.tribes(from: [20: 3, 24: 2, 14: 1, 92: 4]),
                       ["BEAST": 3, "DRAGON": 2, "MURLOC": 1, "NAGA": 4])
    }

    func testAmalgamsCountForEveryPresentTribeAndNeverLeadAlone() {
        XCTAssertEqual(LiveTribes.tribes(from: [20: 3, 24: 1, 26: 2]), ["BEAST": 5, "DRAGON": 3])
        XCTAssertEqual(LiveTribes.tribes(from: [26: 4]), [:])
        XCTAssertNil(LiveTribes.tribes(from: [26: 4]).keys.first { $0 == "ALL" })
    }

    func testUnknownRacesAndZeroCountsAreDropped() {
        XCTAssertEqual(LiveTribes.tribes(from: [999: 5, 25: 2, 0: 1, 20: 0, 15: 2]), ["DEMON": 2])
    }

    func testRankedIsSortedStableAndLimited() {
        let ranked = LiveTribes.ranked(["BEAST": 3, "DRAGON": 3, "MURLOC": 5, "NAGA": 1], limit: 3)
        XCTAssertEqual(ranked.map(\.tribe), ["MURLOC", "BEAST", "DRAGON"])
        XCTAssertEqual(ranked.map(\.count), [5, 3, 3])
    }

    // MARK: mapping entity ids to players

    func testCountsAreMappedByEntityIdNotPosition() {
        var players = [player(1, entity: 50), player(2, entity: 60), player(3, entity: 70)]
        LiveTribes.apply([70: [20: 4], 50: [24: 2]], to: &players)
        XCTAssertEqual(players[0].liveTribes, ["DRAGON": 2])
        XCTAssertNil(players[1].liveTribes)
        XCTAssertEqual(players[2].liveTribes, ["BEAST": 4])
    }

    func testAChangedHeroEntityIsFollowedOnTheNextApply() {
        var players = [player(1, entity: 99)]
        LiveTribes.apply([99: [20: 2]], to: &players)
        XCTAssertEqual(players[0].liveTribes, ["BEAST": 2])
        players[0].heroEntityID = 4676                       // the game replaced the hero entity
        LiveTribes.apply([4676: [20: 3]], to: &players)
        XCTAssertEqual(players[0].liveTribes, ["BEAST": 3])
        LiveTribes.apply([99: [20: 2]], to: &players)         // old id no longer maps to anyone
        XCTAssertNil(players[0].liveTribes)
    }

    func testNoCountsClearsLiveData() {
        var players = [player(1, entity: 5, live: ["BEAST": 2])]
        LiveTribes.apply(nil, to: &players)
        XCTAssertNil(players[0].liveTribes)
    }

    func testPlayerWithoutEntityKeepsNoLiveData() {
        var players = [player(1, entity: nil)]
        LiveTribes.apply([5: [20: 2]], to: &players)
        XCTAssertNil(players[0].liveTribes)
    }

    func testParserExposesTheLeaderboardHeroEntityAndFollowsAReplacement() {
        let parser = PowerLogParser()
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        func hero(_ id: Int, player: Int, place: Int) -> [String] {
            ["\(playback)     FULL_ENTITY - Updating [entityName=Hero\(id) id=\(id) zone=SETASIDE zonePos=0 cardId=BG_HERO_\(id) player=16] CardID=BG_HERO_\(id)",
             "\(playback)         tag=CARDTYPE value=HERO",
             "\(playback)         tag=PLAYER_ID value=\(player)",
             "\(playback)         tag=PLAYER_LEADERBOARD_PLACE value=\(place)"]
        }
        parser.feed(["D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS"]
            + hero(99, player: 2, place: 2))
        XCTAssertEqual(parser.snapshot().players.first { $0.id == 2 }?.heroEntityID, 99)
        parser.feed(hero(4676, player: 2, place: 2))
        XCTAssertEqual(parser.snapshot().players.first { $0.id == 2 }?.heroEntityID, 4676)
    }

    // MARK: portrait and card: live versus last seen, never mixed

    func testPortraitPrefersLiveAndIgnoresStaleness() {
        let p = player(1, live: ["BEAST": 4, "DRAGON": 2], seen: ["MURLOC": 3], seenTurn: 1)
        let shown = TribeSummary.portrait(for: p, currentTurn: 9)
        XCTAssertEqual(shown.tribes, [TribeCount(tribe: "BEAST", count: 4)])
        XCTAssertFalse(shown.isStale)
    }

    func testPortraitFallsBackToTheLastSeenBoard() {
        let p = player(1, live: nil, seen: ["MURLOC": 3], seenTurn: 1)
        let shown = TribeSummary.portrait(for: p, currentTurn: 9)
        XCTAssertEqual(shown.tribes, [TribeCount(tribe: "MURLOC", count: 3)])
        XCTAssertTrue(shown.isStale)
    }

    func testEmptyLiveDataFallsBackToo() {
        let p = player(1, live: [:], seen: ["MURLOC": 3], seenTurn: 8)
        XCTAssertEqual(TribeSummary.portrait(for: p, currentTurn: 9).tribes.map(\.tribe), ["MURLOC"])
    }

    func testCardRowIsLiveWithTopThree() {
        let p = player(1, live: ["BEAST": 4, "DRAGON": 6, "MURLOC": 1, "NAGA": 2], seen: ["MURLOC": 3], seenTurn: 8)
        let row = TribesRow.make(for: p, currentTurn: 9)
        XCTAssertEqual(row?.tribes.map(\.tribe), ["DRAGON", "BEAST", "NAGA"])
        XCTAssertEqual(row?.isLive, true)
        XCTAssertNil(row?.seenTurn)
    }

    func testCardRowFallsBackLabelledWithTheSeenTurn() {
        let p = player(1, seen: ["MURLOC": 3, "BEAST": 1], seenTurn: 5)
        let row = TribesRow.make(for: p, currentTurn: 9)
        XCTAssertEqual(row?.isLive, false)
        XCTAssertEqual(row?.seenTurn, 5)
        XCTAssertEqual(row?.isStale, true)
        XCTAssertEqual(row?.tribes.map(\.tribe), ["MURLOC"], "a single Beast is left out")
    }

    func testCardRowLeavesOutSingleMinions() {
        let mixed = player(1, live: ["BEAST": 1, "DRAGON": 2, "MURLOC": 1])
        XCTAssertEqual(TribesRow.make(for: mixed, currentTurn: 3)?.tribes.map(\.tribe), ["DRAGON"])
        // Live counts that are all singles: no row, and no fallback to an older board either.
        let singles = player(1, live: ["BEAST": 1, "MURLOC": 1], seen: ["PIRATE": 4], seenTurn: 2)
        XCTAssertNil(TribesRow.make(for: singles, currentTurn: 3))
        XCTAssertNil(TribesRow.make(for: player(1, seen: ["PIRATE": 1], seenTurn: 2), currentTurn: 3))
    }

    func testCardRowIsAbsentWithNoData() {
        XCTAssertNil(TribesRow.make(for: player(1), currentTurn: 3))
        XCTAssertNil(TribesRow.make(for: player(1, live: [:]), currentTurn: 3))
    }

    func testCardContentCarriesTheRow() {
        let p = player(1, live: ["BEAST": 2])
        let content = NextOpponentContent(player: p, lobby: [p], currentTurn: 3)
        XCTAssertEqual(content.tribesRow?.isLive, true)
        // The last board text stays about the last real board.
        XCTAssertEqual(content.lastBoard, NextOpponentContent.notFought)
    }

    func testTribeRowAddsHeightOnlyWhenShown() {
        let canvas = CGSize(width: 1920, height: 1080)
        let without = NextOpponentLayout(canvas: canvas, trackerPanel: nil)
        var with = without
        with.hasTribesRow = true
        XCTAssertGreaterThan(with.height / with.scale, without.height / without.scale)
        XCTAssertEqual(NextOpponentLayout.designHeight(rows: .init(showsTierPace: true, showsStatus: true))
                       + NextOpponentLayout.tribesRowHeight + NextOpponentLayout.spacing,
                       NextOpponentLayout.designHeight(rows: .init(showsTierPace: true, showsStatus: true, showsTribes: true)))
    }

    // MARK: polling gate, failures, settings

    func testGateReadsOnlyInALiveSoloMatchAtTheInterval() {
        var gate = TribePollGate()
        let now = Date()
        XCTAssertTrue(gate.shouldRead(enabled: true, isBattlegrounds: true, isGameOver: false, hasMirror: true, now: now))
        XCTAssertFalse(gate.shouldRead(enabled: false, isBattlegrounds: true, isGameOver: false, hasMirror: true, now: now))
        XCTAssertFalse(gate.shouldRead(enabled: true, isBattlegrounds: false, isGameOver: false, hasMirror: true, now: now))
        XCTAssertFalse(gate.shouldRead(enabled: true, isBattlegrounds: true, isGameOver: true, hasMirror: true, now: now))
        XCTAssertFalse(gate.shouldRead(enabled: true, isBattlegrounds: true, isGameOver: false, hasMirror: false, now: now))
        gate.started(at: now)
        XCTAssertFalse(gate.shouldRead(enabled: true, isBattlegrounds: true, isGameOver: false, hasMirror: true,
                                       now: now.addingTimeInterval(2)))
        XCTAssertTrue(gate.shouldRead(enabled: true, isBattlegrounds: true, isGameOver: false, hasMirror: true,
                                      now: now.addingTimeInterval(3)))
    }

    func testLiveDataIsDroppedOnlyAfterSeveralFailuresInARow() {
        var gate = TribePollGate()
        XCTAssertFalse(gate.finished(success: false))
        XCTAssertFalse(gate.finished(success: false))
        XCTAssertFalse(gate.finished(success: true))      // a success resets the count
        XCTAssertFalse(gate.finished(success: false))
        XCTAssertFalse(gate.finished(success: false))
        XCTAssertTrue(gate.finished(success: false))
    }

    func testSettingIsOnByDefaultAndPersists() async {
        let name = "LiveTribesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SettingsModel.readsTribesFromMemory(defaults))
        defaults.set(false, forKey: SettingsKey.readsTribesFromMemory)
        XCTAssertFalse(SettingsModel.readsTribesFromMemory(defaults))
    }

    func testPollerReadsTribesThroughTheInjectedFake() async {
        let poller = LogPoller(locate: { nil }, readMirror: { (nil, "fake") },
                               readTribes: { .counts([5: [20: 2]]) })
        let result = await poller.tribes()
        XCTAssertEqual(result, .counts([5: [20: 2]]))
        let failing = LogPoller(locate: { nil }, readMirror: { (nil, "fake") },
                                readTribes: { .unavailable("layout changed") })
        let failed = await failing.tribes()
        XCTAssertEqual(failed, .unavailable("layout changed"))
    }
}

final class TribesTitleTests: XCTestCase {
    func testOverlineNamesTheSource() {
        let tribes = [TribeCount(tribe: "BEAST", count: 3)]
        XCTAssertEqual(NextOpponentCard.tribesTitle(TribesRow(tribes: tribes, isLive: true, seenTurn: nil, isStale: false)),
                       "TRIBES · LIVE")
        XCTAssertEqual(NextOpponentCard.tribesTitle(TribesRow(tribes: tribes, isLive: false, seenTurn: 7, isStale: false)),
                       "TRIBES · SEEN TURN 7")
    }
}

final class TribeBadgeCountTests: XCTestCase {
    func testCountShowsFromTwoUp() {
        XCTAssertNil(TribeBadges.countText(0))
        XCTAssertNil(TribeBadges.countText(1))
        XCTAssertEqual(TribeBadges.countText(2), "2")
        XCTAssertEqual(TribeBadges.countText(7), "7")
    }
}
