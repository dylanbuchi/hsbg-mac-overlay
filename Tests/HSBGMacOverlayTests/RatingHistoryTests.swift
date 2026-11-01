import XCTest
@testable import HSBGMacOverlay

final class RatingHistoryTests: XCTestCase {
    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    private func list(_ offset: Int = 0, extra: [String: Int] = [:]) -> [String: Int] {
        var ratings = Dictionary(uniqueKeysWithValues: (0..<60).map { ("player\($0)", 9000 + $0 + offset) })
        ratings.merge(extra) { _, new in new }
        return ratings
    }

    private func makeHistory(_ clock: Clock) throws -> RatingHistory {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hist-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return RatingHistory(directory: dir, now: { clock.now })
    }

    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    func testFirstRunHasNoBaseline() throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        XCTAssertNil(history.baseline(region: .eu))
        history.record(list(), region: .eu)
        // The only snapshot is brand new: no change is shown yet.
        let baseline = try XCTUnwrap(history.baseline(region: .eu))
        XCTAssertNil(RatingChange.make(current: 9100, name: "player5", baseline: baseline, now: clock.now))
    }

    func testBaselineIsTheOldestSnapshotWithinTwentyFourHours() throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        let start = clock.now
        for step in [0.0, 5, 10, 20, 30] {   // 30 h before the end falls outside the 24 h window
            clock.now = start.addingTimeInterval(hours(step))
            history.record(list(Int(step)), region: .eu)
        }
        clock.now = start.addingTimeInterval(hours(32))
        let baseline = try XCTUnwrap(history.baseline(region: .eu))
        // Snapshots at 10 h (22 h old) is the oldest inside 24 h; 0 h and 5 h are older.
        XCTAssertEqual(baseline.savedAt, start.addingTimeInterval(hours(10)))
        XCTAssertEqual(baseline.ratings["player0"], 9010)
    }

    func testAtMostOneSnapshotEveryHalfHour() throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        let start = clock.now
        history.record(list(1), region: .eu)
        clock.now = start.addingTimeInterval(10 * 60)
        history.record(list(2), region: .eu)        // too soon: dropped
        clock.now = start.addingTimeInterval(hours(2))
        let baseline = try XCTUnwrap(history.baseline(region: .eu))
        XCTAssertEqual(baseline.ratings["player0"], 9001)
    }

    func testPruningDropsOldSnapshotsAndThinsTheRest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func snap(_ ageHours: Double) -> RatingHistory.Snapshot {
            .init(time: now.addingTimeInterval(-hours(ageHours)), ratings: ["a": 1])
        }
        let ages: [Double] = [0, 0.5, 1, 1.5, 2, 5, 6, 7, 30, 40]
        let kept = RatingHistory.pruned(ages.map(snap), now: now).map { now.timeIntervalSince($0.time) / 3600 }
        // 40 h is gone; after 2 h only one snapshot per 3 h survives.
        XCTAssertEqual(kept, [30, 5, 2, 1.5, 1, 0.5, 0])
    }

    func testMissingPlayerAndSmallChangesShowNothing() throws {
        let clock = Clock()
        let baseline = RatingBaseline(ratings: ["Alice": 9000, "bob": 9500], savedAt: clock.now.addingTimeInterval(-hours(6)))
        XCTAssertNil(RatingChange.make(current: 9300, name: "Carol#1", baseline: baseline, now: clock.now))
        XCTAssertNil(RatingChange.make(current: nil, name: "Alice", baseline: baseline, now: clock.now))
        XCTAssertNil(RatingChange.make(current: 9000, name: "Alice", baseline: baseline, now: clock.now))
        XCTAssertEqual(RatingChange.make(current: 9045, name: "Alice#2345", baseline: baseline, now: clock.now),
                       RatingChange(delta: 45, window: "since 6 h"))
        XCTAssertEqual(RatingChange.make(current: 9411, name: "bob", baseline: baseline, now: clock.now)?.delta, -89)
    }

    func testBaselineYoungerThanAnHourIsIgnored() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = RatingBaseline(ratings: ["Alice": 9000], savedAt: now.addingTimeInterval(-1800))
        XCTAssertNil(RatingChange.make(current: 9100, name: "Alice", baseline: baseline, now: now))
    }

    func testRegionsAreSeparateAndCorruptFilesAreIgnored() throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        history.record(list(), region: .eu)
        clock.now = clock.now.addingTimeInterval(hours(3))
        XCTAssertNotNil(history.baseline(region: .eu))
        XCTAssertNil(history.baseline(region: .us))
        try Data("not json".utf8).write(to: history.directory.appendingPathComponent("rating-history-US.json"))
        XCTAssertNil(history.baseline(region: .us))
        history.record(list(), region: .us)     // recovers by overwriting
        XCTAssertNotNil(history.baseline(region: .us))
    }

    func testImplausibleListsAreNotRecorded() throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        history.record(["a": 9000], region: .eu)
        clock.now = clock.now.addingTimeInterval(hours(3))
        XCTAssertNil(history.baseline(region: .eu))
    }

    func testClientRecordsAfterASuccessfulDownloadAndReturnsTheOlderBaseline() async throws {
        let clock = Clock()
        let history = try makeHistory(clock)
        let body = (0..<60).map { "player\($0) \(9000 + $0)" }.joined(separator: "\n")
        let client = LeaderboardClient(region: .eu, sources: [.bgrank], cache: nil, history: history, http: { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let first = try await client.fetchRatings()
        XCTAssertNil(first.baseline)
        clock.now = clock.now.addingTimeInterval(hours(3))
        let second = try await client.fetchRatings()
        XCTAssertNotNil(second.baseline)
        XCTAssertEqual(second.baseline?.ratings["player3"], 9003)
    }
}
