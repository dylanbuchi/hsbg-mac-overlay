import AppKit
import Foundation
import SwiftUI

/// Minion art for the card's mini board, downloaded on first use from hsbg.cards and kept on disk.
/// Nothing is bundled (Blizzard artwork rendered by that site); every failure falls back to a text chip.
struct CardArtCache: Sendable {
    static let maxBytes = 150_000
    /// The whole tavern pool (about 350 cards) plus boards and trinkets, about 64 KB each.
    static let maxFiles = 600
    /// Art changes with patches: a file older than this is downloaded again when its minion is shown.
    static let refreshAfter: TimeInterval = 14 * 24 * 3600

    let directory: URL
    var now: @Sendable () -> Date = { Date() }

    static var standard: CardArtCache? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return CardArtCache(directory: support.appendingPathComponent("HSBGMacOverlay/card-art", isDirectory: true))
    }

    /// Cards are looked up by name (the log's card ids are not known to the site), so files are named after it.
    static func key(for name: String) -> String {
        let folded = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(String(folded).prefix(80))
    }

    private func fileURL(_ name: String) -> URL { directory.appendingPathComponent(Self.key(for: name) + ".img") }

    /// A WebP or PNG of sane size that decodes to a real image.
    static func isValidImage(_ data: Data) -> Bool {
        guard data.count > 12, data.count <= maxBytes else { return false }
        let png = Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let webp = Array(data.prefix(4)) == Array("RIFF".utf8) && Array(data[8..<12]) == Array("WEBP".utf8)
        guard png || webp, let image = NSImage(data: data) else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    func image(for name: String) -> Data? {
        let url = fileURL(name)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= Self.maxBytes,
              let data = try? Data(contentsOf: url), Self.isValidImage(data) else { return nil }
        return data
    }

    func needsDownload(_ name: String) -> Bool {
        let url = fileURL(name)
        guard image(for: name) != nil,
              let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return true }
        let age = now().timeIntervalSince(modified)
        return age > Self.refreshAfter || age < -60
    }

    func store(_ data: Data, name: String) {
        guard Self.isValidImage(data) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(name)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        prune()
    }

    /// Trinket names by card database id, so a known trinket needs no lookup after a restart.
    private var trinketNamesURL: URL { directory.appendingPathComponent("trinket-names.json") }

    func trinketNames() -> [Int: String] {
        guard let data = try? Data(contentsOf: trinketNamesURL), data.count < 200_000,
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var names: [Int: String] = [:]
        for (key, name) in raw {
            if let id = Int(key), let name = Self.cleanName(name) { names[id] = name }
        }
        return names
    }

    func storeTrinketNames(_ names: [Int: String]) {
        let raw = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: trinketNamesURL, options: .atomic)
    }

    /// A card name as the site sends it, or nil when it does not look like one.
    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.contains(","),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    /// Keeps the folder under `maxFiles` images, dropping the oldest first.
    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
                .filter({ $0.pathExtension == "img" }),
              files.count > Self.maxFiles else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - Self.maxFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
final class CardArtLoader: ObservableObject {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = CardArtLoader()
    static let timeout: TimeInterval = 8
    static let retryAfterFailure: TimeInterval = 10 * 60
    /// Far under the site's 120 requests a minute per IP.
    static let maxRequestsPerMinute = 30
    static let host = "https://hsbg.cards"

    @Published private(set) var revision = 0

    private let cache: CardArtCache?
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private var images: [String: NSImage] = [:]
    private var failedAt: [String: Date] = [:]
    private var inFlight = Set<String>()
    private var requestTimes: [Date] = []
    private var blockedUntil: Date?
    /// Loaded from disk on first use.
    private var trinketNames: [Int: String]?
    /// Image paths learned ahead by card id for the tavern list, keyed like the cache.
    private var knownPaths: [String: String] = [:]
    private var learnedIDs = Set<Int>()

    init(cache: CardArtCache? = .standard,
         fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.fetch = fetch
        self.now = now
    }

    /// The art if it is on disk or in memory; nil means "draw a text chip".
    func image(for name: String) -> NSImage? {
        let key = CardArtCache.key(for: name)
        if let image = images[key] { return image }
        guard let data = cache?.image(for: name), let image = NSImage(data: data) else { return nil }
        images[key] = image
        return image
    }

    /// Looks up the minions of one board in a single request, then downloads the missing images.
    /// Never throws: any problem leaves the chips in place and is not retried for ten minutes.
    func ensure(_ names: [String]) async {
        guard let cache else { return }
        // A name lookup is comma-separated, so a name with a comma needs a path learned by id.
        let wanted = Array(Set(names.filter { name in
            !name.isEmpty && (!name.contains(",") || knownPaths[CardArtCache.key(for: name)] != nil)
        })).sorted().filter { name in
            let key = CardArtCache.key(for: name)
            if inFlight.contains(key) || !cache.needsDownload(name) { return false }
            if let failed = failedAt[key], now().timeIntervalSince(failed) < Self.retryAfterFailure { return false }
            return true
        }
        guard !wanted.isEmpty, canRequest() else { return }
        let keys = wanted.map(CardArtCache.key(for:))
        inFlight.formUnion(keys)
        defer { inFlight.subtract(keys) }

        var paths: [String: String] = [:]
        let unknown = wanted.filter { knownPaths[CardArtCache.key(for: $0)] == nil }
        if !unknown.isEmpty {
            guard let found = await lookup(unknown) else {
                unknown.forEach { failedAt[CardArtCache.key(for: $0)] = now() }
                return
            }
            for name in unknown { paths[CardArtCache.key(for: name)] = found[name.lowercased()] }
        }
        for name in wanted { paths[CardArtCache.key(for: name)] = paths[CardArtCache.key(for: name)] ?? knownPaths[CardArtCache.key(for: name)] }
        for name in wanted {
            let key = CardArtCache.key(for: name)
            // Out of requests for this minute: not a failure, the next hover tries again.
            guard canRequest() else { break }
            guard let path = paths[key], let data = await download(path),
                  CardArtCache.isValidImage(data), let image = NSImage(data: data) else {
                failedAt[key] = now()
                continue
            }
            cache.store(data, name: name)
            images[key] = image
            failedAt[key] = nil
            revision += 1
        }
    }

    /// Learns where these cards' art is, by card database id (up to 100 per request), so a card the mouse
    /// stops on later costs a single download. Cards with art on disk are skipped; ids already asked are not
    /// asked again this session.
    func learnArtPaths(_ cards: [(id: Int, name: String)]) async {
        guard let cache else { return }
        let todo = cards.filter { !learnedIDs.contains($0.id) && cache.needsDownload($0.name) }
        let names = Dictionary(todo.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let ids = names.keys.sorted()
        for start in stride(from: 0, to: ids.count, by: 100) {
            guard canRequest() else { return }
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            var components = URLComponents(string: Self.host + "/api/v1/cards")
            components?.queryItems = [URLQueryItem(name: "identifiers", value: batch.map(String.init).joined(separator: ",")),
                                      URLQueryItem(name: "fields", value: "id,image")]
            guard let url = components?.url, let (data, response) = await send(url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = object["data"] as? [[String: Any]] else { return }
            learnedIDs.formUnion(batch)
            for row in rows {
                guard let id = (row["id"] as? NSNumber)?.intValue, let name = names[id], let image = row["image"] as? String,
                      Self.isSitePath(image) else { continue }
                knownPaths[CardArtCache.key(for: name)] = image
            }
        }
    }

    /// Only images on the site itself are fetched, whatever an answer says.
    static func isSitePath(_ image: String) -> Bool {
        image.hasPrefix("/cards/") && !image.contains("..") && image.hasSuffix(".webp")
    }

    /// The trinket's name once it is known (on disk or looked up this session); nil means "not known yet".
    func trinketName(_ id: Int) -> String? {
        if trinketNames == nil { trinketNames = cache?.trinketNames() ?? [:] }
        return trinketNames?[id]
    }

    /// Looks up the names of unknown trinkets in one request (the site takes card database ids), keeps them
    /// on disk, then fetches their art like a minion's. Failures are not retried for ten minutes.
    func ensureTrinkets(_ ids: [Int]) async {
        guard let cache else { return }
        let unknown = Array(Set(ids.filter { $0 > 0 && trinketName($0) == nil })).sorted().filter { id in
            let key = "trinket:\(id)"
            if inFlight.contains(key) { return false }
            if let failed = failedAt[key], now().timeIntervalSince(failed) < Self.retryAfterFailure { return false }
            return true
        }
        if !unknown.isEmpty, canRequest() {
            let keys = unknown.map { "trinket:\($0)" }
            inFlight.formUnion(keys)
            let found = await lookupNames(unknown)
            inFlight.subtract(keys)
            for id in unknown {
                if let name = found?[id] {
                    trinketNames?[id] = name
                    failedAt["trinket:\(id)"] = nil
                } else {
                    failedAt["trinket:\(id)"] = now()
                }
            }
            if let found, !found.isEmpty {
                cache.storeTrinketNames(trinketNames ?? [:])
                revision += 1
            }
        }
        await ensure(ids.compactMap(trinketName))
    }

    /// Card database id to name, from one `identifiers=` request.
    private func lookupNames(_ ids: [Int]) async -> [Int: String]? {
        var components = URLComponents(string: Self.host + "/api/v1/cards")
        components?.queryItems = [URLQueryItem(name: "identifiers", value: ids.map(String.init).joined(separator: ",")),
                                  URLQueryItem(name: "fields", value: "id,name")]
        guard let url = components?.url, let (data, response) = await send(url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else { return nil }
        let wanted = Set(ids)
        var names: [Int: String] = [:]
        for row in rows {
            guard let id = (row["id"] as? NSNumber)?.intValue, wanted.contains(id),
                  let name = (row["name"] as? String).flatMap(CardArtCache.cleanName) else { continue }
            names[id] = name
        }
        return names
    }

    /// Lowercased card name to image path, from one `identifiers=` request.
    private func lookup(_ names: [String]) async -> [String: String]? {
        var components = URLComponents(string: Self.host + "/api/v1/cards")
        components?.queryItems = [URLQueryItem(name: "identifiers", value: names.joined(separator: ",")),
                                  URLQueryItem(name: "fields", value: "name,image")]
        guard let url = components?.url, let (data, response) = await send(url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else { return nil }
        var paths: [String: String] = [:]
        for row in rows {
            guard let name = row["name"] as? String, let image = row["image"] as? String, Self.isSitePath(image) else { continue }
            paths[name.trimmingCharacters(in: .whitespaces).lowercased()] = image
        }
        return paths
    }

    private func download(_ path: String) async -> Data? {
        guard canRequest(), let url = URL(string: Self.host + path),
              let (data, response) = await send(url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func send(_ url: URL) async -> (Data, URLResponse)? {
        requestTimes.append(now())
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        request.setValue("HSBGMacOverlay/\(AppInfo.version) (+\(AboutInfo.repositoryURL.absoluteString))",
                         forHTTPHeaderField: "User-Agent")
        guard let result = try? await fetch(request) else { return nil }
        if let http = result.1 as? HTTPURLResponse, http.statusCode == 429 {
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
            blockedUntil = now().addingTimeInterval(min(max(wait, 1), 3600))
        }
        return result
    }

    private func canRequest() -> Bool {
        let current = now()
        if let blockedUntil, current < blockedUntil { return false }
        requestTimes.removeAll { current.timeIntervalSince($0) > 60 }
        return requestTimes.count < Self.maxRequestsPerMinute
    }
}

/// Up to seven small minion cards, left to right; a text chip stands in for art that is not available.
struct MiniBoard: View {
    let minions: [BoardMinion]
    @ObservedObject var loader: CardArtLoader
    static let height: CGFloat = MinionZoomGeometry.tileSize.height
    static let maxMinions = 7

    var body: some View {
        let shown = Array(minions.prefix(Self.maxMinions))
        HStack(spacing: MinionZoomGeometry.tileSpacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, minion in
                tile(minion)
            }
        }
        .task(id: shown.map(\.name)) { await loader.ensure(shown.map(\.name)) }
    }

    @ViewBuilder
    private func tile(_ minion: BoardMinion) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            if let image = loader.image(for: minion.name) {
                // The card render is taller than wide: show its top, where the portrait is.
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: MinionZoomGeometry.tileSize.width, height: Self.height, alignment: .top)
                    .clipped()
            } else {
                Text(verbatim: minion.name)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(EdgeInkPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .padding(1)
                    .frame(width: MinionZoomGeometry.tileSize.width, height: Self.height)
                    .background(Color.white.opacity(0.1))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(minion.isGolden ? EdgeInkPalette.leaderGold : Color.white.opacity(0.18), lineWidth: 1))
        .accessibilityLabel(minion.isGolden ? "Golden \(minion.name)" : minion.name)
    }
}
