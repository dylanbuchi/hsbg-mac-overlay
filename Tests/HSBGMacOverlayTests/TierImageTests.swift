import AppKit
import XCTest
@testable import HSBGMacOverlay

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

private final class FakeServer: @unchecked Sendable {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> (Data, Int, [String: String]) = { _ in (TierImageTests.png(), 200, ["ETag": "\"v1\""]) }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let (data, status, headers) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

@MainActor
final class TierImageTests: XCTestCase {
    nonisolated static func png(side: Int = 8) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private var directory: URL!
    private let clock = Clock()
    private let server = FakeServer()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tier-images-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeLoader() -> TierImageLoader {
        let clock = clock
        let cache = TierImageCache(directory: directory, now: { clock.date })
        let server = server
        return TierImageLoader(cache: cache, fetch: { try await server.fetch($0) }, now: { clock.date })
    }

    func testMissThenHitDownloadsOnceAndSendsOneGetToTheTierUrl() async {
        let loader = makeLoader()
        XCTAssertNil(loader.image(for: 3))
        await loader.ensure(3)
        XCTAssertNotNil(loader.image(for: 3))
        XCTAssertEqual(server.requests.map { $0.url?.absoluteString }, ["https://hsbg.cards/tiers/Tier3.png"])
        XCTAssertEqual(server.requests[0].timeoutInterval, TierImageLoader.timeout)
        await loader.ensure(3)
        XCTAssertEqual(server.requests.count, 1)
    }

    func testCachedImageSurvivesARestartWithoutAnyRequest() async {
        await makeLoader().ensure(2)
        let second = makeLoader()
        XCTAssertNotNil(second.image(for: 2))
        await second.ensure(2)
        XCTAssertEqual(server.requests.count, 1)
    }

    func testOfflineFailureFallsBackAndDoesNotRetryStorm() async {
        server.handler = { _ in throw URLError(.notConnectedToInternet) }
        let loader = makeLoader()
        await loader.ensure(4)
        XCTAssertNil(loader.image(for: 4))
        await loader.ensure(4)
        XCTAssertEqual(server.requests.count, 1)
        clock.date.addTimeInterval(TierImageLoader.retryAfterFailure + 1)
        await loader.ensure(4)
        XCTAssertEqual(server.requests.count, 2)
    }

    func testInvalidDataIsRejectedAndNeverCached() async {
        for bad: Data in [Data("<html>nope</html>".utf8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]),
                          Data(repeating: 0, count: 10)] {
            server.handler = { _ in (bad, 200, [:]) }
            let loader = makeLoader()
            await loader.ensure(1)
            XCTAssertNil(loader.image(for: 1))
        }
        XCTAssertNil(TierImageCache(directory: directory).image(for: 1))
    }

    func testOversizedPNGIsRejected() {
        var data = Self.png()
        data.append(Data(repeating: 0, count: TierImageCache.maxBytes))
        XCTAssertFalse(TierImageCache.isValidPNG(data))
        XCTAssertTrue(TierImageCache.isValidPNG(Self.png()))
    }

    func testErrorStatusFallsBack() async {
        server.handler = { _ in (Data(), 404, [:]) }
        let loader = makeLoader()
        await loader.ensure(5)
        XCTAssertNil(loader.image(for: 5))
    }

    func testRevalidatesAtMostDailyWithETagAndKeepsTheImageOn304() async {
        let loader = makeLoader()
        await loader.ensure(6)
        clock.date.addTimeInterval(23 * 3600)
        await loader.ensure(6)
        XCTAssertEqual(server.requests.count, 1)

        clock.date.addTimeInterval(2 * 3600)
        server.handler = { _ in (Data(), 304, [:]) }
        await loader.ensure(6)
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertNotNil(loader.image(for: 6))

        // The 304 restarted the clock.
        clock.date.addTimeInterval(3600)
        await loader.ensure(6)
        XCTAssertEqual(server.requests.count, 2)
    }

    func testFailedRevalidationKeepsTheCachedImage() async {
        let loader = makeLoader()
        await loader.ensure(2)
        clock.date.addTimeInterval(25 * 3600)
        server.handler = { _ in throw URLError(.timedOut) }
        await loader.ensure(2)
        XCTAssertNotNil(loader.image(for: 2))
    }

    func testOnlyTiersOneToSixAreRequested() async {
        let loader = makeLoader()
        await loader.ensure(0)
        await loader.ensure(7)
        XCTAssertTrue(server.requests.isEmpty)
        XCTAssertNil(loader.image(for: 7))
    }
}
