import AppKit

enum AboutInfo {
    static let repositoryURL = URL(string: "https://github.com/\(UpdateChecker.repository)")!

    static func versionLine(_ version: String = AppInfo.version) -> String {
        "Version \(version)"
    }

    static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: """
            A free Battlegrounds overlay by Dylan Buchi.
            Card data and images courtesy of HS BG Cards (hsbg.cards), downloaded at runtime and cached on this Mac.
            Tribe pictures and tier shields are loaded from your installed HSTracker, never bundled.
            Hearthstone and its artwork are © Blizzard Entertainment.
            Not affiliated with Blizzard Entertainment, HearthSim or HS BG Cards.

            """,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "github.com/\(UpdateChecker.repository)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: repositoryURL]
        ))
        return text
    }
}
