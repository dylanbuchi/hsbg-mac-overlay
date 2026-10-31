import Foundation

struct ReleaseInfo: Equatable, Sendable {
    let version: String
    let url: URL
}

/// One anonymous GET to GitHub's latest-release endpoint at launch. Nothing about the
/// user or the game is sent; every failure (offline, rate limit, bad data) is silent.
enum UpdateChecker {
    static let repository = "dylanbuchi/hsbg-mac-overlay"

    static func fetchLatest(session: URLSession = .shared) async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("HSBGMacOverlay/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// Accepts only a release page of this repository, so a bad response cannot send the user elsewhere.
    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable { let tag_name: String; let html_url: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let url = URL(string: payload.html_url),
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/\(repository)/") else { return nil }
        return ReleaseInfo(version: payload.tag_name, url: url)
    }

    /// Compares dotted numbers after an optional leading `v`; anything non-numeric is never "newer".
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let latest = components(latest), let current = components(current) else { return false }
        for index in 0..<max(latest.count, current.count) {
            let a = index < latest.count ? latest[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        return parts.contains(where: { $0 == nil }) || parts.isEmpty ? nil : parts.compactMap { $0 }
    }
}
