import Foundation

/// When to download MMR: each new match gets a fresh list, then every 15 minutes.
/// A failed download does not count as fetched for the match; it retries with a short backoff.
struct RatingSchedule {
    private(set) var lastAttempt: Date?
    /// The parser's game count when ratings were last fetched successfully.
    private(set) var fetchedGame = -1
    private(set) var failures = 0

    func shouldFetch(now: Date, currentGame: Int) -> Bool {
        let elapsed = now.timeIntervalSince(lastAttempt ?? .distantPast)
        return elapsed >= minimumGap(isNewGame: currentGame != fetchedGame)
    }

    func minimumGap(isNewGame: Bool) -> TimeInterval {
        if failures > 0 { return min(30 * pow(2, Double(failures - 1)), 120) }
        return isNewGame ? 2 * 60 : 15 * 60
    }

    mutating func succeeded(game: Int, at now: Date) {
        lastAttempt = now
        fetchedGame = game
        failures = 0
    }

    mutating func failed(at now: Date) {
        lastAttempt = now
        failures += 1
    }

    mutating func reset() {
        lastAttempt = nil
        failures = 0
    }
}
