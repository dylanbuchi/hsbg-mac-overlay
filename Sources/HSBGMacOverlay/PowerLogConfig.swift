import Foundation

/// Hearthstone only writes the verbose Power.log when `log.config` asks for it.
enum PowerLogConfig {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Blizzard/Hearthstone/log.config")
    }

    static let block = """
    [Power]
    LogLevel=1
    FilePrinting=true
    ConsolePrinting=false
    Verbose=true
    """

    private static let required = ["loglevel": "1", "fileprinting": "true", "verbose": "true"]

    /// True unless a `[Power]` section already carries the settings the overlay needs.
    static func needsFix(_ contents: String?) -> Bool {
        guard let contents else { return true }
        return !required.allSatisfy { powerSettings(in: contents)[$0.key] == $0.value }
    }

    /// Replaces an existing `[Power]` section, or appends one; other sections are kept.
    static func fixed(_ contents: String?) -> String {
        let lines = (contents ?? "").components(separatedBy: .newlines)
        var output: [String] = []
        var inPower = false
        var replaced = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inPower = trimmed.lowercased() == "[power]"
                if inPower {
                    if !replaced { output.append(contentsOf: block.components(separatedBy: "\n")) }
                    replaced = true
                    continue
                }
            }
            if !inPower { output.append(line) }
        }
        if !replaced {
            while output.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { output.removeLast() }
            if !output.isEmpty { output.append("") }
            output.append(contentsOf: block.components(separatedBy: "\n"))
        }
        return output.joined(separator: "\n") + "\n"
    }

    private static func powerSettings(in contents: String) -> [String: String] {
        var inPower = false
        var settings: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inPower = trimmed.lowercased() == "[power]"
            } else if inPower, let equals = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased()
                settings[key] = value
            }
        }
        return settings
    }

    /// Writes the fixed file, keeping the old one as `log.config.bak`. A file that exists but
    /// is not UTF-8 is backed up and left untouched rather than rewritten from nothing.
    static func apply(to url: URL = PowerLogConfig.url) throws {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        if exists {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        let old = exists ? try String(contentsOf: url, encoding: .utf8) : nil
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixed(old).write(to: url, atomically: true, encoding: .utf8)
    }
}
