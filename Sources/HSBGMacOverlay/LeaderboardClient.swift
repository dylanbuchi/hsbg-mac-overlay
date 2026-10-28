import Foundation

enum LeaderboardRegion: String, CaseIterable {
    case us = "US"
    case eu = "EU"
    case ap = "AP"
}

struct LeaderboardClient {
    var region: LeaderboardRegion = .eu

    func fetchRatings() async throws -> [String: Int] {
        let url = URL(string: "https://bgrank.fly.dev/\(region.rawValue)/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("HSBGMacOverlay/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
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
            let name = String(parts[0])
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
