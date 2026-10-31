import Foundation

enum LeaderboardRegion: String, CaseIterable {
    case us = "US"
    case eu = "EU"
    case ap = "AP"
}

/// Where a leaderboard list can be downloaded. All sources serve the same `name rating` lines.
struct RatingSource: Sendable {
    let name: String
    let url: @Sendable (LeaderboardRegion) -> URL

    static let bgrank = RatingSource(name: "bgrank") { URL(string: "https://bgrank.fly.dev/\($0.rawValue)/")! }
    /// A GitHub Actions mirror of Blizzard's public leaderboard (same format), reachable where fly.dev is not.
    static let githubMirror = RatingSource(name: "GitHub mirror") {
        URL(string: "https://raw.githubusercontent.com/lowerman/bg-board-mirror/mirror/\($0.rawValue).txt")!
    }
}

struct RatingsResult: Equatable, Sendable {
    let ratings: [String: Int]
    let source: String
    /// Set when the list came from the disk cache instead of the network.
    let cachedAt: Date?

    var isCached: Bool { cachedAt != nil }

    func label(now: Date = Date()) -> String {
        guard let cachedAt else { return source }
        let minutes = max(0, Int(now.timeIntervalSince(cachedAt) / 60))
        return minutes < 90 ? "cache, \(minutes) min old" : "cache, \(minutes / 60) h old"
    }
}

struct LeaderboardClient: Sendable {
    typealias HTTPFetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    var region: LeaderboardRegion = .eu
    var sources: [RatingSource] = [.bgrank, .githubMirror]
    var cache: RatingsCache? = .standard
    var http: HTTPFetch = { try await URLSession.shared.data(for: $0) }

    /// Tries each source in order. A source that fails, answers with an error status or returns
    /// too few rows is skipped. If every source fails, a still-valid disk cache is returned
    /// (marked as cached); otherwise the error is thrown.
    func fetchRatings() async throws -> RatingsResult {
        for source in sources {
            if let ratings = try? await download(source), RatingsCache.isPlausible(ratings) {
                cache?.save(ratings, region: region, source: source.name)
                return RatingsResult(ratings: ratings, source: source.name, cachedAt: nil)
            }
        }
        if let cached = cache?.load(region: region) {
            return RatingsResult(ratings: cached.ratings, source: cached.source, cachedAt: cached.savedAt)
        }
        throw URLError(.cannotLoadFromNetwork)
    }

    private func download(_ source: RatingSource) async throws -> [String: Int] {
        var request = URLRequest(url: source.url(region))
        request.timeoutInterval = 10
        request.setValue("HSBGMacOverlay/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode), data.count <= 20 * 1024 * 1024 else {
            throw URLError(.badServerResponse)
        }
        return Self.parseRatings(String(decoding: data, as: UTF8.self))
    }

    /// Parses `name rating` lines. Display names are not unique on the leaderboard,
    /// so a name listed more than once is dropped rather than credited with
    /// someone else's rating.
    static func parseRatings(_ response: String) -> [String: Int] {
        var ratings: [String: Int] = [:]
        var ambiguous = Set<String>()
        let lines = response
            .replacingOccurrences(of: "<br />", with: "\n")
            .components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let rating = Int(parts[1]), !parts[0].isEmpty else { continue }
            let name = LeaderboardName.normalize(String(parts[0]))
            guard !name.isEmpty else { continue }
            if ambiguous.contains(name) {
                continue
            }
            if ratings[name] != nil {
                ratings[name] = nil
                ambiguous.insert(name)
            } else {
                ratings[name] = rating
            }
        }
        return ratings
    }
}

enum LeaderboardName {
    /// The leaderboard lists plain names; the log can carry `Name#1234`.
    static func normalize(_ name: String) -> String {
        (name.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
