import AppKit
import XCTest
@testable import HSBGMacOverlay

private final class ArtClock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_800_000_000) }

private final class ArtServer: @unchecked Sendable {
    var requests: [URLRequest] = []
    var known: [String: String] = ["Sellemental": "/cards/production/thumbs/full/minions/elemental/64038-sellemental.webp",
                                   "Southsea Captain": "/cards/production/thumbs/full/minions/pirate/96771-southsea-captain.webp",
                                   "Lens Case": "/cards/production/thumbs/full/trinkets/130835-lens-case.webp"]
    /// Trinkets, which the overlay looks up by card database id.
    var knownIDs: [Int: String] = [130835: "Lens Case"]
    var status = 200
    var headers: [String: String] = [:]
    var imageData = TierImageTests.png()

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url!
        func reply(_ data: Data, _ code: Int) -> (Data, URLResponse) {
            (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!)
        }
        if status != 200 { return reply(Data(), status) }
        if url.path == "/api/v1/cards" {
            let asked = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "identifiers" }?.value?.split(separator: ",").map(String.init) ?? []
            let rows: [[String: Any]] = asked.compactMap { asked in
                if let id = Int(asked) { return knownIDs[id].map { ["id": id, "name": $0] } }
                return known[asked].map { ["name": asked, "image": $0] }
            }
            return reply(try JSONSerialization.data(withJSONObject: ["data": rows]), 200)
        }
        return reply(imageData, 200)
    }
}

@MainActor
final class CardArtTests: XCTestCase {
    private var directory: URL!
    private let clock = ArtClock()
    private let server = ArtServer()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("card-art-\(UUID().uuidString)")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    func testTrinketNamesAreLookedUpByIdOnceThenKeptOnDisk() async {
        let loader = makeLoader()
        XCTAssertNil(loader.trinketName(130835))
        await loader.ensureTrinkets([130835, 999999])
        XCTAssertEqual(loader.trinketName(130835), "Lens Case")
        XCTAssertNil(loader.trinketName(999999))
        XCTAssertNotNil(loader.image(for: "Lens Case"))
        let urls = server.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(urls[0].contains("identifiers=130835,999999"))

        // After a restart the name and art come from disk; only the unknown id is not asked again for ten minutes.
        let asked = server.requests.count
        let restarted = makeLoader()
        XCTAssertEqual(restarted.trinketName(130835), "Lens Case")
        await restarted.ensureTrinkets([130835])
        XCTAssertEqual(server.requests.count, asked)
        await loader.ensureTrinkets([999999])
        XCTAssertEqual(server.requests.count, asked)
    }

    func testBadTrinketNamesAreRejected() {
        XCTAssertEqual(CardArtCache.cleanName(" Lens Case "), "Lens Case")
        XCTAssertNil(CardArtCache.cleanName(""))
        XCTAssertNil(CardArtCache.cleanName("a,b"))
        XCTAssertNil(CardArtCache.cleanName("line\nbreak"))
        XCTAssertNil(CardArtCache.cleanName(String(repeating: "x", count: 81)))
    }

    private func makeLoader() -> CardArtLoader {
        let clock = clock, server = server
        return CardArtLoader(cache: CardArtCache(directory: directory, now: { clock.date }),
                             fetch: { try await server.fetch($0) }, now: { clock.date })
    }

    func testOneLookupForTheWholeBoardThenOneDownloadPerMinion() async {
        let loader = makeLoader()
        XCTAssertNil(loader.image(for: "Sellemental"))
        await loader.ensure(["Sellemental", "Southsea Captain", "Sellemental"])
        XCTAssertNotNil(loader.image(for: "Sellemental"))
        XCTAssertNotNil(loader.image(for: "Southsea Captain"))
        let urls = server.requests.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(urls.count, 3)
        XCTAssertTrue(urls[0].hasPrefix("https://hsbg.cards/api/v1/cards?"))
        XCTAssertTrue(urls[0].contains("identifiers=Sellemental,Southsea%20Captain"))
        XCTAssertEqual(Set(urls.dropFirst()), ["https://hsbg.cards/cards/production/thumbs/full/minions/elemental/64038-sellemental.webp",
                                               "https://hsbg.cards/cards/production/thumbs/full/minions/pirate/96771-southsea-captain.webp"])
        XCTAssertEqual(server.requests[0].timeoutInterval, CardArtLoader.timeout)
        XCTAssertTrue(server.requests[0].value(forHTTPHeaderField: "User-Agent")?.hasPrefix("HSBGMacOverlay/") ?? false)
    }

    func testCachedArtSurvivesARestartAndNothingIsAskedTwice() async {
        await makeLoader().ensure(["Sellemental"])
        let second = makeLoader()
        XCTAssertNotNil(second.image(for: "Sellemental"))
        await second.ensure(["Sellemental"])
        XCTAssertEqual(server.requests.count, 2)
    }

    func testArtIsRefreshedAfterTwoWeeks() async {
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        clock.date = clock.date.addingTimeInterval(15 * 24 * 3600)
        await loader.ensure(["Sellemental"])
        XCTAssertEqual(server.requests.count, 4)
    }

    func testOfflineOrErrorsFallBackAndBackOffForTenMinutes() async {
        server.status = 500
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        XCTAssertNil(loader.image(for: "Sellemental"))
        await loader.ensure(["Sellemental"])
        XCTAssertEqual(server.requests.count, 1)
        server.status = 200
        clock.date = clock.date.addingTimeInterval(11 * 60)
        await loader.ensure(["Sellemental"])
        XCTAssertNotNil(loader.image(for: "Sellemental"))
    }

    func testUnknownMinionStaysWithoutArtAndOthersStillLoad() async {
        let loader = makeLoader()
        await loader.ensure(["Sellemental", "Nonexistent Foo"])
        XCTAssertNotNil(loader.image(for: "Sellemental"))
        XCTAssertNil(loader.image(for: "Nonexistent Foo"))
    }

    func testRateLimitAnswerPausesAllRequests() async {
        server.status = 429
        server.headers = ["Retry-After": "120"]
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        server.status = 200
        clock.date = clock.date.addingTimeInterval(11 * 60)   // past the backoff and the 120 s Retry-After
        await loader.ensure(["Sellemental"])
        XCTAssertNotNil(loader.image(for: "Sellemental"))
        XCTAssertEqual(server.requests.count, 3)
    }

    func testRetryAfterIsHonouredBeforeTheBackoffEnds() async {
        server.status = 429
        server.headers = ["Retry-After": "3600"]
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        server.status = 200
        clock.date = clock.date.addingTimeInterval(11 * 60)
        await loader.ensure(["Sellemental"])
        XCTAssertNil(loader.image(for: "Sellemental"))
        XCTAssertEqual(server.requests.count, 1)
    }

    func testInvalidOrOversizedImagesAreRejected() async {
        server.imageData = Data(repeating: 0x41, count: 500)
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        XCTAssertNil(loader.image(for: "Sellemental"))
        XCTAssertFalse(CardArtCache.isValidImage(Data(repeating: 0, count: CardArtCache.maxBytes + 1)))
        XCTAssertTrue(CardArtCache.isValidImage(TierImageTests.png()))
    }

    func testAnImagePathOutsideTheSiteIsIgnored() async {
        server.known = ["Sellemental": "//evil.example/x.webp"]
        let loader = makeLoader()
        await loader.ensure(["Sellemental"])
        XCTAssertNil(loader.image(for: "Sellemental"))
        XCTAssertEqual(server.requests.count, 1)
    }

    func testFilesAreNamedFromTheCardNameAndTheFolderIsCapped() {
        XCTAssertEqual(CardArtCache.key(for: "Mama Bear's Den"), "mama-bear-s-den")
        let cache = CardArtCache(directory: directory)
        for index in 0..<(CardArtCache.maxFiles + 5) { cache.store(TierImageTests.png(), name: "Card \(index)") }
        let count = (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
        XCTAssertLessThanOrEqual(count, CardArtCache.maxFiles)
    }
}

final class BoardMinionParserTests: XCTestCase {
    func testBoardKeepsNamesInPositionOrderWithGoldenFlagAndTurn() {
        let parser = PowerLogParser()
        let playback = "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() -"
        func minion(_ id: Int, _ name: String, pos: Int, golden: Bool = false) -> [String] {
            ["\(playback)     FULL_ENTITY - Updating [entityName=\(name) id=\(id) zone=PLAY zonePos=\(pos) cardId=C\(id) player=16] CardID=C\(id)",
             "\(playback)         tag=CARDTYPE value=MINION", "\(playback)         tag=ZONE value=PLAY",
             "\(playback)         tag=CONTROLLER value=16", "\(playback)         tag=ZONE_POSITION value=\(pos)",
             "\(playback)         tag=CARDRACE value=PIRATE"] + (golden ? ["\(playback)         tag=PREMIUM value=1"] : [])
        }
        let game = "\(playback)     TAG_CHANGE Entity=GameEntity"
        var lines = ["D 12:00:00.0000000 GameState.DebugPrintGame() - GameType=GT_BATTLEGROUNDS",
                     "\(playback)     Player EntityID=24 PlayerID=16 GameAccountId=[hi=0 lo=0]",
                     "\(game) tag=TURN value=13 ", "\(game) tag=BOARD_VISUAL_STATE value=2 ",
                     "\(playback)     FULL_ENTITY - Updating [entityName=H id=500 zone=PLAY zonePos=0 cardId=H player=16] CardID=H",
                     "\(playback)         tag=CARDTYPE value=HERO", "\(playback)         tag=ZONE value=PLAY",
                     "\(playback)         tag=CONTROLLER value=16", "\(playback)         tag=PLAYER_ID value=3"]
        lines += minion(502, "Southsea Captain", pos: 2, golden: true)
        lines += minion(501, "Sellemental", pos: 1)
        lines += minion(503, "UNKNOWN ENTITY [cardType=INVALID]", pos: 3)
        lines.append("\(playback)     TAG_CHANGE Entity=[entityName=Sellemental id=501 zone=PLAY zonePos=1 cardId=C501 player=16] tag=ATTACKING value=1 ")
        parser.feed(lines)
        let opponent = parser.snapshot().players.first { $0.id == 3 }
        XCTAssertEqual(opponent?.lastBoardMinions.map(\.name), ["Sellemental", "Southsea Captain"])
        XCTAssertEqual(opponent?.lastBoardMinions.map(\.isGolden), [false, true])
        XCTAssertEqual(opponent?.lastSeenTurn, 7)
    }

    func testCardContentCarriesTheBoardAndSeenTurnOnlyOnceFought() {
        var p = BattlegroundsPlayer(id: 3, name: "A#1")
        XCTAssertNil(NextOpponentContent(player: p, lobby: [p], currentTurn: 9).seenTurn)
        p.lastSeenTribes = ["PIRATE": 2]
        p.lastSeenTurn = 7
        p.lastBoardMinions = [BoardMinion(cardID: "C", name: "Sellemental", isGolden: false)]
        let content = NextOpponentContent(player: p, lobby: [p], currentTurn: 9)
        XCTAssertEqual(content.seenTurn, 7)
        XCTAssertEqual(content.boardMinions.count, 1)
    }
}
