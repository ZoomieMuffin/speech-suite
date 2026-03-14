import Foundation
import Testing
@testable import AudioInput

// MARK: - FileDailyNoteSink

@Test func fileDailyNoteSinkCreatesFile() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date()
    let sink = FileDailyNoteSink(notesDir: dir)
    try await sink.write("- [10:00] テスト\n", date: now)

    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    #expect(files.count == 1)
    #expect(files[0].pathExtension == "md")
}

@Test func fileDailyNoteSinkAppendsToExistingFile() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date()
    let sink = FileDailyNoteSink(notesDir: dir)
    try await sink.write("- [10:00] 一行目\n", date: now)
    try await sink.write("- [10:01] 二行目\n", date: now)

    let fileURL = try sink.fileURL(for: now)
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content == "- [10:00] 一行目\n- [10:01] 二行目\n")
}

@Test func fileDailyNoteSinkCreatesDirectory() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("nested/dir")
    defer {
        let parent = dir.deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }

    let sink = FileDailyNoteSink(notesDir: dir)
    try await sink.write("- [09:00] ネストディレクトリ\n", date: Date())

    #expect(FileManager.default.fileExists(atPath: dir.path))
}

@Test func fileDailyNoteSinkFileNameFormat() throws {
    let dir = FileManager.default.temporaryDirectory
    let sink = FileDailyNoteSink(notesDir: dir)

    var comps = DateComponents()
    comps.year = 2026
    comps.month = 3
    comps.day = 11
    let date = Calendar.current.date(from: comps)!
    let url = try sink.fileURL(for: date)
    #expect(url.lastPathComponent == "2026-03-11-voice.md")
}

@Test func fileDailyNoteSinkUsesProvidedDateForFilePath() async throws {
    // write に渡した date がファイルパスに反映されることを確認（日付境界バグの回帰テスト）
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    var comps = DateComponents()
    comps.year = 2026; comps.month = 12; comps.day = 31
    let newYearsEve = Calendar.current.date(from: comps)!

    let sink = FileDailyNoteSink(notesDir: dir)
    try await sink.write("- [23:59] 大晦日\n", date: newYearsEve)

    let expectedFile = dir.appendingPathComponent("2026-12-31-voice.md")
    #expect(FileManager.default.fileExists(atPath: expectedFile.path))
}

@Test func fileDailyNoteSinkThrowsOnUnwritableDir() async throws {
    let sink = FileDailyNoteSink(notesDir: URL(fileURLWithPath: "/proc/invalid-\(UUID().uuidString)"))
    do {
        try await sink.write("- [00:00] 失敗するはず\n", date: Date())
        Issue.record("Expected write to throw but it succeeded")
    } catch is FileDailyNoteSinkError {
        // 期待通り
    } catch {
        Issue.record("Expected FileDailyNoteSinkError but got \(error)")
    }
}
