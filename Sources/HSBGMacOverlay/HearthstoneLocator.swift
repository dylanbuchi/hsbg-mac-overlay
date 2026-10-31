import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum HearthstoneLogLocator {
    static var newestPowerLog: URL? {
        newestPowerLog(in: AppLocations.logRoots(hearthstoneApp: AppLocations.runningHearthstoneURL()))
    }

    static func newestPowerLog(in roots: [URL]) -> URL? {
        let candidates = roots.flatMap { root -> [(URL, Date)] in
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return folders.compactMap { folder in
                guard folder.lastPathComponent.hasPrefix("Hearthstone_") else { return nil }
                let log = folder.appendingPathComponent("Power.log")
                guard let values = try? log.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate else { return nil }
                return (log, modified)
            }
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }
}

@MainActor
enum HearthstoneWindowLocator {
    static var cocoaFrame: NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            let owner = window[kCGWindowOwnerName as String] as? String
            guard owner == "Hearthstone",
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { continue }
            let boundsDictionary = bounds as CFDictionary
            var cgFrame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &cgFrame),
                  cgFrame.width > 600,
                  cgFrame.height > 400 else { continue }

            let screenHeight = NSScreen.screens.first?.frame.maxY ?? cgFrame.maxY
            let frame = NSRect(
                x: cgFrame.minX,
                y: screenHeight - cgFrame.maxY,
                width: cgFrame.width,
                height: cgFrame.height
            )
            // In a window, the leaderboard geometry is relative to the content
            // area below the title bar, as in HSTracker's SizeHelper.
            let isFullscreen = NSScreen.screens.contains { $0.frame == frame }
            guard !isFullscreen else { return frame }
            return NSRect(x: frame.minX, y: frame.minY,
                          width: frame.width, height: max(frame.height - titlebarHeight, 0))
        }
        return nil
    }

    private static let titlebarHeight: CGFloat = {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height
    }()
}
