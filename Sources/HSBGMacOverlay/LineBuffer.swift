import Foundation

/// Turns arbitrary byte chunks into whole lines. A chunk can end mid-line or in the
/// middle of a multi-byte character, so lines are split on raw newline bytes first
/// and only then decoded; names in any script survive.
struct LineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        pending.append(data)
        guard let lastNewline = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[pending.startIndex...lastNewline]
        pending = Data(pending[pending.index(after: lastNewline)...])
        return complete.split(separator: 0x0A).map {
            String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
    }

    mutating func reset() {
        pending = Data()
    }
}
