import Foundation
import Testing
@testable import AudioInput

// MARK: - 組み込みフィラー除去

@Test func removesJapaneseFillers() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("えーと 今日は天気がいいですね")
    #expect(result == "今日は天気がいいですね")
}

@Test func removesMultipleJapaneseFillers() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("あの 今日は えーと 会議があります")
    #expect(result == "今日は 会議があります")
}

@Test func removesEnglishFillers() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("um I think uh this is good")
    #expect(result == "I think this is good")
}

@Test func preservesNonFillerText() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("今日は会議があります")
    #expect(result == "今日は会議があります")
}

@Test func removesFillerAtEndOfText() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("会議があります えーと")
    #expect(result == "会議があります")
}

@Test func handlesEmptyInput() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("")
    #expect(result == "")
}

@Test func removesFillerWithJapanesePunctuation() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("えーと、今日は天気がいい")
    #expect(result == "今日は天気がいい")
}

@Test func removesFillerWithInnerJapanesePunctuation() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("今日は、えーと、会議があります")
    #expect(result == "今日は、会議があります")
}

// MARK: - ユーザー定義パターン

@Test func removesCustomFillerPattern() async throws {
    let processor = FillerTextProcessor(customPatterns: ["ですね"])
    let result = try await processor.process("そうですね、いい天気 ですね")
    #expect(result == "いい天気")
}

// MARK: - エッジケース

@Test func doesNotRemoveFillerAsSubstring() async throws {
    // 「あの」がフィラーだが「あのひと」の部分一致では除去しない
    let processor = FillerTextProcessor()
    let input = "あのひとは元気です"
    let result = try await processor.process(input)
    #expect(result == "あのひとは元気です")
}

@Test func normalizesWhitespaceAfterRemoval() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("えーと   今日は   えー   天気がいい")
    #expect(result == "今日は 天気がいい")
}

@Test func fillerOnlyInputReturnsEmpty() async throws {
    let processor = FillerTextProcessor()
    let result = try await processor.process("えーと")
    #expect(result == "")
}
