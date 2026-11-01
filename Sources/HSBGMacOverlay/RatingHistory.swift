import Foundation

/// An older leaderboard list to compare today's ratings with.
struct RatingBaseline: Equatable, Sendable {
    let ratings: [String: Int]
    let savedAt: Date
}

/// Rating change of one player since a baseline: the card shows it, the portraits do not.
struct RatingChange: Equatable {
    let delta: Int
    /// "since 6 h".
    let window: String

    /// Nil when there is no baseline older than `minimumAge`, the player was not in it, or nothing changed.
    static func make(current: Int?, name: String, baseline: RatingBaseline?, now: Date) -> RatingChange? {
        guard let current, let baseline,
              let before = baseline.ratings[LeaderboardName.normalize(name)] else { return nil }
        let age = now.timeIntervalSince(baseline.savedAt)
        guard age >= RatingHistory.minimumAge, current != before else { return nil }
        let hours = max(1, Int((age / 3600).rounded()))
        return RatingChange(delta: current - before, window: "since \(hours) h")
    }
}

/// Compact snapshots of the downloaded leaderboard, kept on disk for about a day and a half so the
/// card can show how a player's rating moved. One file per region, written atomically.
struct RatingHistory: Sendable {
    static let keepFor: TimeInterval = 36 * 3600
    static let baselineWindow: TimeInterval = 24 * 3600
    static let minimumAge: TimeInterval = 3600
    /// At most one snapshot per half hour; older ones are thinned further to bound the file size.
    static let minimumGap: TimeInterval = 30 * 60
    static let thinnedGap: TimeInterval = 3 * 3600
    static let recentSpan: TimeInterval = 2 * 3600
    static let maxFileBytes = 12 * 1024 * 1024

    struct Snapshot: Codable, Equatable, Sendable {
        var time: Date
        var ratings: [String: Int]
    }

    private struct File: Codable {
        var version = 1
        var region: String
        var snapshots: [Snapshot]
    }

    let directory: URL
    var now: @Sendable () -> Date = { Date() }

    static var standard: RatingHistory? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return RatingHistory(directory: support.appendingPathComponent("HSBGMacOverlay", isDirectory: true))
    }

    private func fileURL(_ region: LeaderboardRegion) -> URL {
        directory.appendingPathComponent("rating-history-\(region.rawValue).json")
    }

    /// Adds a snapshot unless the latest one is under half an hour old, then prunes.
    func record(_ ratings: [String: Int], region: LeaderboardRegion) {
        guard RatingsCache.isPlausible(ratings) else { return }
        let current = now()
        var snapshots = load(region)
        if let latest = snapshots.last, current.timeIntervalSince(latest.time) < Self.minimumGap,
           latest.time <= current { return }
        snapshots.append(Snapshot(time: current, ratings: ratings))
        snapshots = Self.pruned(snapshots, now: current)
        write(snapshots, region: region)
    }

    /// The oldest snapshot from the last 24 hours, which the card compares with.
    func baseline(region: LeaderboardRegion) -> RatingBaseline? {
        let current = now()
        let oldest = load(region)
            .filter { $0.time <= current && current.timeIntervalSince($0.time) <= Self.baselineWindow }
            .min { $0.time < $1.time }
        return oldest.map { RatingBaseline(ratings: $0.ratings, savedAt: $0.time) }
    }

    /// Drops snapshots older than 36 h, thins old ones to one per 3 h, and keeps the file under its cap.
    static func pruned(_ snapshots: [Snapshot], now: Date) -> [Snapshot] {
        let fresh = snapshots.filter { $0.time <= now && now.timeIntervalSince($0.time) <= keepFor }
            .sorted { $0.time > $1.time }
        var kept: [Snapshot] = []
        for snapshot in fresh {
            guard let last = kept.last else { kept.append(snapshot); continue }
            let age = now.timeIntervalSince(snapshot.time)
            let gap = age <= recentSpan ? minimumGap : thinnedGap
            if last.time.timeIntervalSince(snapshot.time) >= gap { kept.append(snapshot) }
        }
        return kept.sorted { $0.time < $1.time }
    }

    private func load(_ region: LeaderboardRegion) -> [Snapshot] {
        let url = fileURL(region)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= Self.maxFileBytes,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let file = try? decoder.decode(File.self, from: data),
              file.version == 1, file.region == region.rawValue else { return [] }
        return file.snapshots.filter { RatingsCache.isPlausible($0.ratings) }.sorted { $0.time < $1.time }
    }

    private func write(_ snapshots: [Snapshot], region: LeaderboardRegion) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var kept = snapshots
        while true {
            guard let data = try? encoder.encode(File(region: region.rawValue, snapshots: kept)) else { return }
            if data.count <= Self.maxFileBytes || kept.count <= 1 {
                guard data.count <= Self.maxFileBytes else { return }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: fileURL(region), options: .atomic)
                return
            }
            kept.removeFirst()
        }
    }
}
