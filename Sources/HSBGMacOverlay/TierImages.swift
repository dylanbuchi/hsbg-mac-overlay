import AppKit
import Foundation
import SwiftUI

/// Tavern tier badge images (tier 1 to 6), downloaded on first use from hsbg.cards and kept on disk.
/// Nothing is bundled: they are Blizzard artwork served from an undocumented site path, so every
/// failure falls back to the vector `TierBadge`.
struct TierImageCache: Sendable {
    static let maxBytes = 200_000
    /// The server allows a day (cache-control max-age=86400); we ask again at most that often.
    static let revalidateAfter: TimeInterval = 24 * 60 * 60

    struct Meta: Codable, Equatable, Sendable {
        var etag: String?
        var checkedAt: Date
    }

    let directory: URL
    var now: @Sendable () -> Date = { Date() }

    static var standard: TierImageCache? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return TierImageCache(directory: support.appendingPathComponent("HSBGMacOverlay/tier-images", isDirectory: true))
    }

    private func imageURL(_ tier: Int) -> URL { directory.appendingPathComponent("tier-\(tier).png") }
    private func metaURL(_ tier: Int) -> URL { directory.appendingPathComponent("tier-\(tier).json") }

    /// A real PNG of sane size: magic bytes, at most 200 KB, and decodable.
    static func isValidPNG(_ data: Data) -> Bool {
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count > magic.count, data.count <= maxBytes, Array(data.prefix(8)) == magic,
              let image = NSImage(data: data) else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    func image(for tier: Int) -> Data? {
        let url = imageURL(tier)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size <= Self.maxBytes,
              let data = try? Data(contentsOf: url), Self.isValidPNG(data) else { return nil }
        return data
    }

    func meta(for tier: Int) -> Meta? {
        guard let data = try? Data(contentsOf: metaURL(tier)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Meta.self, from: data)
    }

    /// True when there is no image yet or it was last checked more than a day ago.
    func needsCheck(tier: Int) -> Bool {
        guard image(for: tier) != nil, let meta = meta(for: tier) else { return true }
        let age = now().timeIntervalSince(meta.checkedAt)
        return age > Self.revalidateAfter || age < -60
    }

    func store(_ data: Data, etag: String?, tier: Int) {
        guard Self.isValidPNG(data) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: imageURL(tier), options: .atomic)
        writeMeta(Meta(etag: etag, checkedAt: now()), tier: tier)
    }

    /// The server said "not modified": the image stays, the clock restarts.
    func touch(tier: Int) {
        writeMeta(Meta(etag: meta(for: tier)?.etag, checkedAt: now()), tier: tier)
    }

    private func writeMeta(_ meta: Meta, tier: Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(meta) else { return }
        try? data.write(to: metaURL(tier), options: .atomic)
    }
}

@MainActor
final class TierImageLoader: ObservableObject {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = TierImageLoader()
    static let timeout: TimeInterval = 8
    /// After a failure the same tier is not asked again for this long (no retry storms).
    static let retryAfterFailure: TimeInterval = 10 * 60

    /// Bumped when an image arrives, so views redraw.
    @Published private(set) var revision = 0

    private let cache: TierImageCache?
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private var images: [Int: NSImage] = [:]
    private var failedAt: [Int: Date] = [:]
    private var inFlight = Set<Int>()

    init(cache: TierImageCache? = .standard,
         fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.fetch = fetch
        self.now = now
    }

    static func url(for tier: Int) -> URL? {
        (1...6).contains(tier) ? URL(string: "https://hsbg.cards/tiers/Tier\(tier).png") : nil
    }

    /// The badge if one is on disk or in memory; nil means "draw the vector fallback".
    func image(for tier: Int) -> NSImage? {
        if let image = images[tier] { return image }
        guard (1...6).contains(tier), let data = cache?.image(for: tier), let image = NSImage(data: data) else { return nil }
        images[tier] = image
        return image
    }

    /// Downloads or revalidates the badge when needed. Never throws: any problem keeps what we have.
    func ensure(_ tier: Int) async {
        guard let url = Self.url(for: tier), let cache, !inFlight.contains(tier) else { return }
        guard cache.needsCheck(tier: tier) else { return }
        if let failed = failedAt[tier], now().timeIntervalSince(failed) < Self.retryAfterFailure { return }
        inFlight.insert(tier)
        defer { inFlight.remove(tier) }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("HSBGMacOverlay/\(AppInfo.version) (+\(AboutInfo.repositoryURL.absoluteString))",
                         forHTTPHeaderField: "User-Agent")
        if cache.image(for: tier) != nil, let etag = cache.meta(for: tier)?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch http.statusCode {
            case 304 where cache.image(for: tier) != nil:
                cache.touch(tier: tier)
                failedAt[tier] = nil
            case 200 where TierImageCache.isValidPNG(data):
                cache.store(data, etag: http.value(forHTTPHeaderField: "ETag"), tier: tier)
                images[tier] = NSImage(data: data)
                failedAt[tier] = nil
                revision += 1
            default:
                failedAt[tier] = now()
            }
        } catch {
            failedAt[tier] = now()
        }
    }
}

/// The tavern tier badge for the card: the game's art when available, else the vector badge.
struct TierPaceBadge: View {
    let tier: Int
    @ObservedObject var loader: TierImageLoader
    static let height: CGFloat = 28

    var body: some View {
        Group {
            if let image = loader.image(for: tier) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: Self.height)
            } else {
                TierBadge(tier: tier, tile: Self.height / 0.22)
            }
        }
        .task(id: tier) { await loader.ensure(tier) }
        .accessibilityLabel("Tavern tier \(tier)")
    }
}
