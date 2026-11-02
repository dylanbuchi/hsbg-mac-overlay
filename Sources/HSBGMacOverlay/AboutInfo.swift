import AppKit

enum AboutInfo {
    static let repositoryURL = URL(string: "https://github.com/\(UpdateChecker.repository)")!

    static func versionLine(_ version: String = AppInfo.version) -> String {
        "Version \(version)"
    }

    /// The scrolling box of the standard About panel: the link first, so it shows without scrolling,
    /// then the credits. "Not affiliated", the copyright and the license are in the footer (Info.plist).
    static func credits() -> NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let font = NSFont.systemFont(ofSize: 11)
        let text = NSMutableAttributedString(
            string: "github.com/\(UpdateChecker.repository)",
            attributes: [.font: font, .link: repositoryURL, .paragraphStyle: centered]
        )
        text.append(NSAttributedString(
            string: """


            Card data and images courtesy of HS BG Cards (hsbg.cards), downloaded at runtime and cached on this Mac.
            Tribe pictures and tier shields come from your installed HSTracker and are never bundled.
            Hearthstone and its artwork © Blizzard Entertainment.
            """,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered]
        ))
        return text
    }
}
