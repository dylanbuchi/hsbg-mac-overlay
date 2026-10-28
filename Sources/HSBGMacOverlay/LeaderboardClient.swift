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

    static func parseRatings(_ response: String) -> [String: Int] {
        response
            .replacingOccurrences(of: "<br />", with: "\n")
            .components(separatedBy: .newlines)
            .reduce(into: [:]) { ratings, line in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2,
                      let rating = Int(parts[1]),
                      !parts[0].isEmpty else { return }
                ratings[String(parts[0])] = rating
            }
    }
}
