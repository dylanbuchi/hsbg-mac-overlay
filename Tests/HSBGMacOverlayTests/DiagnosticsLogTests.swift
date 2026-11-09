import XCTest
@testable import HSBGMacOverlay

final class DiagnosticsLogTests: XCTestCase {
    private func makeLog() -> DiagnosticsLog {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return DiagnosticsLog(directory: dir)
    }

    private func lines(_ log: DiagnosticsLog) -> [String] {
        ((try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func testWritesNameJoinIssuesOnlyWhenTheyChange() {
        let log = makeLog()
        log.noteNameJoin([])
        log.noteNameJoin(["a"])
        log.noteNameJoin(["a"])
        log.noteNameJoin([])
        let written = lines(log)
        XCTAssertEqual(written.count, 2)
        XCTAssertTrue(written[0].hasSuffix("name join: a"))
        XCTAssertTrue(written[1].hasSuffix("name join ok again"))
    }

    func testRotatesIntoOneOldFile() throws {
        let log = makeLog()
        let long = String(repeating: "x", count: 1000)
        for _ in 0..<(DiagnosticsLog.maxBytes / 1000 + 5) { log.note(long) }
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: log.fileURL.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, DiagnosticsLog.maxBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.directory.appendingPathComponent("overlay.old.log").path))
    }
}
