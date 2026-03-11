import Foundation
import Testing
@testable import SpeechCore

// MARK: - TranscriptionSegment

@Test func segmentCodableRoundTrip() throws {
    let original = try TranscriptionSegment(
        text: "Hello",
        startTime: 1.0,
        endTime: 2.5,
        confidence: 0.9,
        speaker: "Alice"
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    #expect(decoded == original)
}

@Test func segmentCodableRoundTripWithNils() throws {
    let original = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    #expect(decoded == original)
}

@Test func segmentSpeakerIsOptional() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    #expect(seg.speaker == nil)
}

@Test func segmentStoresSpeaker() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1, speaker: "Bob")
    #expect(seg.speaker == "Bob")
}

@Test func segmentDecodeInvalidTimeRangeThrows() {
    let json = #"{"text":"Bad","startTime":5.0,"endTime":1.0}"#
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    }
}

@Test func segmentDecodeInvalidConfidenceThrows() {
    let json = #"{"text":"Bad","startTime":0,"endTime":1,"confidence":2.0}"#
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    }
}

@Test func segmentStoresFields() throws {
    let seg = try TranscriptionSegment(
        text: "Hello",
        startTime: 1.0,
        endTime: 2.5,
        confidence: 0.9
    )
    #expect(seg.text == "Hello")
    #expect(seg.startTime == 1.0)
    #expect(seg.endTime == 2.5)
    #expect(seg.confidence == 0.9)
    #expect(seg.duration == 1.5)
}

@Test func segmentConfidenceIsOptional() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    #expect(seg.confidence == nil)
}

@Test func segmentZeroDurationIsValid() throws {
    let seg = try TranscriptionSegment(text: "", startTime: 1.0, endTime: 1.0)
    #expect(seg.duration == 0)
}

@Test func segmentInvalidTimeRangeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 2.0, endTime: 1.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentNegativeStartTimeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: -1.0, endTime: 0.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentInfiniteTimeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: .infinity, endTime: .infinity)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: .nan, endTime: 1.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentConfidenceOutOfRangeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: 1.5)
    } throws: { error in
        if case SpeechCoreError.invalidConfiguration = error { true } else { false }
    }
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: -0.1)
    } throws: { error in
        if case SpeechCoreError.invalidConfiguration = error { true } else { false }
    }
}

// MARK: - SpeechCoreError

@Test func errorDescriptionIsNonNil() {
    struct StubError: Error, Sendable {}

    let cases: [SpeechCoreError] = [
        .fileNotFound(path: "/tmp/a.wav"),
        .unsupportedFormat(path: "/tmp/b.opus"),
        .permissionDenied(permission: "microphone"),
        .engineUnavailable(engine: "Apple Speech", requiredOS: "macOS 15"),
        .recognitionFailed(underlying: StubError()),
        .timeout,
        .emptyResult,
        .invalidTimeRange,
        .invalidConfiguration("bad"),
        .alreadyStarted,
        .invalidInputURL,
    ]
    for error in cases {
        #expect(error.errorDescription != nil, "errorDescription should be non-nil for \(error)")
    }
}

@Test func recognitionFailedIncludesUnderlyingDescription() {
    struct EngineError: Error, Sendable, LocalizedError {
        var errorDescription: String? { "Model loading failed" }
    }
    let error = SpeechCoreError.recognitionFailed(underlying: EngineError())
    let description = error.errorDescription ?? ""
    #expect(description.contains("Model loading failed"),
            "errorDescription should include underlying error description, got: \(description)")
}

// MARK: - HallucinationFilter

@Test func filterRemovesShortSegments() throws {
    let segments = try [
        TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.2),
        TranscriptionSegment(text: "Hello world", startTime: 1.0, endTime: 2.0),
        TranscriptionSegment(text: "Ok", startTime: 3.0, endTime: 3.4),
        TranscriptionSegment(text: "Good morning", startTime: 4.0, endTime: 5.5),
    ]
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
    #expect(result[0].text == "Hello world")
    #expect(result[1].text == "Good morning")
}

@Test func filterKeepsAllWhenNoneShort() throws {
    let segments = try [
        TranscriptionSegment(text: "Hello", startTime: 0.0, endTime: 1.0),
        TranscriptionSegment(text: "World", startTime: 1.0, endTime: 2.0),
    ]
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
}

@Test func filterWithDefaultThreshold() throws {
    let short = try TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.4)
    let normal = try TranscriptionSegment(text: "Hello", startTime: 1.0, endTime: 2.0)
    let filter = try HallucinationFilter()
    let result = filter.filter([short, normal])
    #expect(result.count == 1)
    #expect(result[0].text == "Hello")
}

@Test func filterInvalidMinimumDurationThrows() {
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: -1.0)
    }
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: .nan)
    }
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: .infinity)
    }
}

@Test func filterBoundaryDurationIsKept() throws {
    // duration == minimumDuration は除外しない（>= の境界）
    let seg = try TranscriptionSegment(text: "Boundary", startTime: 0.0, endTime: 0.5)
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter([seg])
    #expect(result.count == 1)
}

// MARK: - HallucinationFilter (content-based)

@Test func filterDetectsKnownHallucinationStrings() throws {
    let segments = try [
        TranscriptionSegment(text: "ご視聴ありがとうございました", startTime: 0.0, endTime: 3.0),
        TranscriptionSegment(text: "こんにちは世界", startTime: 3.0, endTime: 5.0),
    ]
    let filter = try HallucinationFilter()
    let result = filter.filter(segments)
    #expect(result.count == 1)
    #expect(result[0].text == "こんにちは世界")
}

@Test func filterDetectsMultipleHallucinationPatterns() throws {
    let hallucinationTexts = [
        "ご視聴ありがとうございました",
        "チャンネル登録よろしくお願いします",
        "Thank you for watching",
        "Thanks for watching",
        "Please subscribe",
        "いいねとチャンネル登録お願いします",
    ]
    for text in hallucinationTexts {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let filter = try HallucinationFilter()
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected as hallucination")
    }
}

@Test func filterPassesNormalText() throws {
    let normalTexts = [
        "今日の天気は晴れです",
        "会議は15時から始まります",
        "Hello, how are you doing today?",
        "The quick brown fox jumps over the lazy dog",
    ]
    for text in normalTexts {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let filter = try HallucinationFilter()
        let result = filter.filter([seg])
        #expect(result.count == 1, "Expected '\(text)' to pass through filter")
    }
}

@Test func filterDetectsHallucinationWithWhitespace() throws {
    let seg = try TranscriptionSegment(text: "  ご視聴ありがとうございました  ", startTime: 0.0, endTime: 3.0)
    let filter = try HallucinationFilter()
    let result = filter.filter([seg])
    #expect(result.isEmpty, "Should detect hallucination even with surrounding whitespace")
}

@Test func filterDetectsHallucinationWithPunctuation() throws {
    let variants = [
        "Thank you for watching.",
        "Thank you for watching!",
        "Thank you for watching...",
        "ご視聴ありがとうございました。",
        "ご視聴ありがとうございました！",
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected as hallucination despite punctuation")
    }
}

@Test func filterDetectsFullWidthHallucination() throws {
    // 全角英数: "Ｔｈａｎｋ ｙｏｕ ｆｏｒ ｗａｔｃｈｉｎｇ"
    let seg = try TranscriptionSegment(text: "\u{FF34}\u{FF48}\u{FF41}\u{FF4E}\u{FF4B} \u{FF59}\u{FF4F}\u{FF55} \u{FF46}\u{FF4F}\u{FF52} \u{FF57}\u{FF41}\u{FF54}\u{FF43}\u{FF48}\u{FF49}\u{FF4E}\u{FF47}", startTime: 0.0, endTime: 3.0)
    let filter = try HallucinationFilter()
    let result = filter.filter([seg])
    #expect(result.isEmpty, "Should detect hallucination in full-width characters")
}

@Test func filterDetectsHallucinationWithInternalWhitespace() throws {
    let variants = [
        "Thank   you  for  watching",   // 連続スペース
        "Thank you\nfor watching",       // 改行
        "Thank you\tfor\twatching",      // タブ
        "Thank\u{3000}you for watching", // 全角空白
        "ご視聴 ありがとうございました",        // 日本語への空白混入
        "チャンネル 登録 お願いします",         // 日本語への空白混入（複数箇所）
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected as hallucination despite irregular whitespace")
    }
}

@Test func filterDetectsHallucinationWithInvisibleCharacters() throws {
    // ZWJ (U+200D) や ZWNJ (U+200C) 等の不可視フォーマット文字
    let variants = [
        "Thank\u{200D} you for watching",   // ZWJ
        "Thank\u{200C} you for watching",   // ZWNJ
        "ご視聴\u{FEFF}ありがとうございました", // BOM
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected text with invisible chars to be detected as hallucination")
    }
}

@Test func filterDetectsHallucinationWithEmojiAndSymbols() throws {
    let variants = [
        "Thank you for watching 🎬🎬🎬",
        "ご視聴ありがとうございました ❤️🙏",
        "Please subscribe ▶️🔔",
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected despite emoji/symbols")
    }
}

@Test func filterDetectsHallucinationWithExcessivePunctuation() throws {
    let variants = [
        "Thank you for watching!!!!!!!!!!",
        "Thank you for watching...!!!...!!!",
        "ご視聴ありがとうございました。。。！！！",
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected despite excessive punctuation")
    }
}

@Test func filterDetectsHallucinationCaseInsensitive() throws {
    let variants = [
        "THANK YOU FOR WATCHING",
        "thank you for watching",
        "Thank You For Watching",
        "tHaNk YoU fOr WaTcHiNg",
        "PLEASE SUBSCRIBE",
        "please subscribe",
    ]
    let filter = try HallucinationFilter()
    for text in variants {
        let seg = try TranscriptionSegment(text: text, startTime: 0.0, endTime: 3.0)
        let result = filter.filter([seg])
        #expect(result.isEmpty, "Expected '\(text)' to be detected as hallucination (case-insensitive)")
    }
}

@Test func filterSkipsLongNormalText() throws {
    // 最長パターンの2倍を超える長文は normalize をスキップして通過する
    let longText = String(repeating: "This is a normal sentence. ", count: 50)
    let seg = try TranscriptionSegment(text: longText, startTime: 0.0, endTime: 60.0)
    let filter = try HallucinationFilter()
    let result = filter.filter([seg])
    #expect(result.count == 1)
}

@Test func filterCombinesDurationAndContentFiltering() throws {
    let segments = try [
        // short + hallucination → removed (both reasons)
        TranscriptionSegment(text: "ご視聴ありがとうございました", startTime: 0.0, endTime: 0.2),
        // short + normal → removed (duration)
        TranscriptionSegment(text: "Hi", startTime: 1.0, endTime: 1.2),
        // long + hallucination → removed (content)
        TranscriptionSegment(text: "Thank you for watching", startTime: 2.0, endTime: 5.0),
        // long + normal → kept
        TranscriptionSegment(text: "Good morning everyone", startTime: 5.0, endTime: 7.0),
    ]
    let filter = try HallucinationFilter()
    let result = filter.filter(segments)
    #expect(result.count == 1)
    #expect(result[0].text == "Good morning everyone")
}

// MARK: - HallucinationFilter (custom patterns)

@Test func filterCustomPatternIsRemoved() throws {
    let seg = try TranscriptionSegment(text: "えーと", startTime: 0.0, endTime: 2.0)
    let filter = try HallucinationFilter(customPatterns: ["えーと"])
    let result = filter.filter([seg])
    #expect(result.isEmpty, "ユーザー定義パターンは除去される")
}

@Test func filterCustomPatternCaseInsensitive() throws {
    let seg = try TranscriptionSegment(text: "FILLER WORD", startTime: 0.0, endTime: 2.0)
    let filter = try HallucinationFilter(customPatterns: ["filler word"])
    let result = filter.filter([seg])
    #expect(result.isEmpty, "カスタムパターンは大文字小文字を無視する")
}

@Test func filterCustomPatternDoesNotAffectNormalText() throws {
    let seg = try TranscriptionSegment(text: "今日の天気は晴れ", startTime: 0.0, endTime: 2.0)
    let filter = try HallucinationFilter(customPatterns: ["えーと"])
    let result = filter.filter([seg])
    #expect(result.count == 1, "カスタムパターン以外の通常テキストは通過する")
}

@Test func filterCustomPatternCoexistsWithBuiltIn() throws {
    let segments = try [
        TranscriptionSegment(text: "えーと", startTime: 0.0, endTime: 2.0),        // custom
        TranscriptionSegment(text: "Thank you for watching", startTime: 2.0, endTime: 5.0), // built-in
        TranscriptionSegment(text: "今日のミーティング", startTime: 5.0, endTime: 8.0),        // keep
    ]
    let filter = try HallucinationFilter(customPatterns: ["えーと"])
    let result = filter.filter(segments)
    #expect(result.count == 1)
    #expect(result[0].text == "今日のミーティング")
}

@Test func filterEmptyCustomPatterns() throws {
    let seg = try TranscriptionSegment(text: "えーと", startTime: 0.0, endTime: 2.0)
    let filter = try HallucinationFilter(customPatterns: [])
    let result = filter.filter([seg])
    #expect(result.count == 1, "空のカスタムパターンは何も除去しない")
}

@Test func filterCustomPatternWithPunctuation() throws {
    let seg = try TranscriptionSegment(text: "えーと！", startTime: 0.0, endTime: 2.0)
    let filter = try HallucinationFilter(customPatterns: ["えーと"])
    let result = filter.filter([seg])
    #expect(result.isEmpty, "句読点付きでもカスタムパターンにマッチする")
}

// MARK: - TranscriberRegistry

private actor MockService: TranscriptionService {
    nonisolated let id: String
    var isAvailable: Bool

    init(id: String, isAvailable: Bool = true) {
        self.id = id
        self.isAvailable = isAvailable
    }

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, SpeechCoreError> {
        fatalError("Not used in registry tests")
    }

    func stop() async throws(SpeechCoreError) {}
}

@Test func registryReturnsRegisteredService() async {
    let registry = TranscriberRegistry()
    let svc = MockService(id: "apple")
    await registry.register(svc)
    let found = await registry.service(for: "apple")
    #expect(found != nil)
    #expect(found?.id == "apple")
}

@Test func unavailableServiceExcludedFromAvailable() async {
    let registry = TranscriberRegistry()
    let available = MockService(id: "a", isAvailable: true)
    let unavailable = MockService(id: "b", isAvailable: false)
    await registry.register(available)
    await registry.register(unavailable)
    let result = await registry.availableServices()
    #expect(result.count == 1)
    #expect(result[0].id == "a")
}

@Test func duplicateRegistrationOverwrites() async {
    let registry = TranscriberRegistry()
    let first = MockService(id: "x", isAvailable: false)
    let second = MockService(id: "x", isAvailable: true)
    await registry.register(first)
    await registry.register(second)
    let found = await registry.service(for: "x")
    #expect(found != nil)
    let available = await found!.isAvailable
    #expect(available == true)
}

// MARK: - MockFileTranscriber

@Test func mockFileTranscriberYieldsSegments() async throws {
    let segments = try [
        TranscriptionSegment(text: "Hello", startTime: 0.0, endTime: 1.0),
        TranscriptionSegment(text: "World", startTime: 1.0, endTime: 2.0),
    ]
    let mock = MockFileTranscriber(segments: segments)
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "en_US"))
    var collected: [TranscriptionSegment] = []
    for try await segment in stream {
        collected.append(segment)
    }
    #expect(collected == segments)
}

@Test func mockFileTranscriberEmptySegments() async throws {
    let mock = MockFileTranscriber(segments: [])
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "ja_JP"))
    var collected: [TranscriptionSegment] = []
    for try await segment in stream {
        collected.append(segment)
    }
    #expect(collected.isEmpty)
}

@Test func mockFileTranscriberFinishesWithError() async throws {
    struct EngineError: Error, Sendable {}
    let engineError = EngineError()
    let segments = try [
        TranscriptionSegment(text: "Partial", startTime: 0.0, endTime: 1.0),
    ]
    let mock = MockFileTranscriber(segments: segments, error: SpeechCoreError.recognitionFailed(underlying: engineError))
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "en_US"))
    var collected: [TranscriptionSegment] = []
    do {
        for try await segment in stream {
            collected.append(segment)
        }
        Issue.record("Expected error but stream completed normally")
    } catch {
        guard case SpeechCoreError.recognitionFailed = error else {
            Issue.record("Expected .recognitionFailed but got \(error)")
            return
        }
    }
    #expect(collected == segments)
}

@Test func mockFileTranscriberRejectsNonFileURL() async {
    let mock = MockFileTranscriber(segments: [])
    let stream = mock.transcribe(fileURL: URL(string: "https://example.com/audio.wav")!, locale: Locale(identifier: "en_US"))
    do {
        for try await _ in stream {
            Issue.record("Expected error but received a segment")
        }
        Issue.record("Expected error but stream completed normally")
    } catch {
        if case .invalidInputURL = error as? SpeechCoreError {} else {
            Issue.record("Expected invalidInputURL but got \(error)")
        }
    }
}
