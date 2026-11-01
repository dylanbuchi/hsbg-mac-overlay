import AppKit
import Foundation
import Testing
@testable import HSBGMacOverlay

@MainActor @Suite struct TribeArtTests {
    private final class Calls { var checks = 0; var loads: [String] = [] }

    private func art(genuine: Bool, names: Set<String>, calls: Calls = Calls(), now: @escaping () -> Date = Date.init) -> TribeArt {
        TribeArt(source: TribeArtSource(
            isGenuine: { calls.checks += 1; return genuine },
            load: { name in calls.loads.append(name); return names.contains(name) ? NSImage(size: NSSize(width: 4, height: 4)) : nil }),
                 now: now)
    }

    @Test func assetNamesFollowTheCatalog() {
        #expect(TribeArt.assetName(for: "BEAST") == "tribe_beast")
        #expect(TribeArt.assetName(for: "MECHANICAL") == "tribe_mechanical")
        #expect(TribeArt.assetName(for: "ALL") == "tribe_all")
        #expect(TribeArt.assetName(for: "ABERRATION") == "tribe_aberration")
        #expect(TribeArt.assetName(for: "WHATEVER") == nil)
    }

    @Test func everyKnownTribeHasAName() {
        for key in TribeStyle.all.keys { #expect(TribeArt.assetName(for: key) != nil) }
    }

    @Test func loadsOnceAndCaches() {
        let calls = Calls()
        let art = art(genuine: true, names: ["tribe_beast"], calls: calls)
        #expect(art.image(for: "BEAST") != nil)
        #expect(art.image(for: "BEAST") != nil)
        #expect(calls.loads == ["tribe_beast"])
        #expect(calls.checks == 1)
    }

    @Test func nothingIsLoadedFromAForeignOrMissingApp() {
        let calls = Calls()
        let art = art(genuine: false, names: ["tribe_beast"], calls: calls)
        #expect(art.image(for: "BEAST") == nil)
        #expect(calls.loads.isEmpty)
    }

    @Test func aRejectedCheckIsRetriedAfterAMinute() {
        let calls = Calls()
        var clock = Date(timeIntervalSince1970: 1_000)
        let art = art(genuine: false, names: [], calls: calls, now: { clock })
        _ = art.image(for: "BEAST")
        _ = art.image(for: "DEMON")
        #expect(calls.checks == 1)
        clock += TribeArt.retryAfter + 1
        _ = art.image(for: "DEMON")
        #expect(calls.checks == 2)
    }

    @Test func aMissingAssetFallsBackWithoutRetryingEveryRedraw() {
        let calls = Calls()
        let art = art(genuine: true, names: ["tribe_beast"], calls: calls)
        #expect(art.image(for: "DEMON") == nil)
        #expect(art.image(for: "DEMON") == nil)
        #expect(calls.loads == ["tribe_demon"])
        #expect(art.image(for: "BEAST") != nil)
    }
}
