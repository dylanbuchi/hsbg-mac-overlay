import AppKit

enum AboutInfo {
    static let repositoryURL = URL(string: "https://github.com/\(UpdateChecker.repository)")!

    static func versionLine(_ version: String = AppInfo.version) -> String {
        "Version \(version)"
    }

    static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "A free Battlegrounds overlay by Dylan Buchi.\nNot affiliated with Blizzard Entertainment or HearthSim.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(
            string: "github.com/\(UpdateChecker.repository)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: repositoryURL]
        ))
        return text
    }
}
