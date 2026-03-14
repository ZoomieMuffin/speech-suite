import Foundation
import Testing
@testable import AudioInput
import SpeechCore

// MARK: - Helpers

private actor StubRecorder: AudioRecorderProtocol {
    var isRecording = false
    func startRecording() async throws { isRecording = true }
    func stopRecording() async throws -> URL { isRecording = false; return URL(fileURLWithPath: "/tmp/stub.wav") }
}

private actor StubTranscriptionService: TranscriptionService {
    nonisolated let id = "stub"
    var isAvailable = true
    private let segments: [TranscriptionSegment]

    init(segments: [TranscriptionSegment]) { self.segments = segments }

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, any Error> {
        let segments = self.segments
        return AsyncThrowingStream { continuation in
            for segment in segments { continuation.yield(segment) }
            continuation.finish()
        }
    }

    func stop() async throws(SpeechCoreError) {}
}

private struct CapturingSink: OutputSinkProtocol {
    let onWrite: @Sendable (String, Date) async -> Void
    func write(_ text: String, date: Date) async throws {
        await onWrite(text, date)
    }
}

// MARK: - Tests

@Test func useCaseSessionDateCapturedAtStart() async throws {
    // start() 時に sessionDate が確定し、stop() でその date が sink に渡ることを確認。
    // 23:59 開始 → 00:01 停止のような日付境界またぎでも start() 時の date が使われる。
    let segment = try TranscriptionSegment(text: "テスト", startTime: 0, endTime: 2)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])

    let capturedDates = ActorBox<[Date]>([])
    let sink = CapturingSink { _, date in
        await capturedDates.append(date)
    }

    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        sink: sink,
        hallucinationFilter: nil
    )

    let before = Date()
    try await useCase.start()
    try await useCase.stop()
    let after = Date()

    let dates = await capturedDates.value
    #expect(dates.count == 1)
    #expect(dates[0] >= before)
    #expect(dates[0] <= after)
}

@Test func useCaseSkipsWriteWhenNoSegments() async throws {
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [])

    let writeCount = ActorBox<Int>(0)
    let sink = CapturingSink { _, _ in await writeCount.increment() }

    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        sink: sink,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(await writeCount.value == 0)
}

@Test func useCaseWritesLineInExpectedFormat() async throws {
    // 追記行が `- [HH:MM] テキスト\n` フォーマットであることを確認
    let segment = try TranscriptionSegment(text: "会議の議事録", startTime: 0, endTime: 3)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])

    let capturedTexts = ActorBox<[String]>([])
    let sink = CapturingSink { text, _ in
        await capturedTexts.appendString(text)
    }

    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        sink: sink,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    let texts = await capturedTexts.value
    #expect(texts.count == 1)
    // `- [HH:MM] テキスト\n` フォーマットを検証
    #expect(texts[0].hasPrefix("- ["))
    #expect(texts[0].hasSuffix("会議の議事録\n"))
    // タイムスタンプ部分が HH:MM 形式
    let bracketContent = texts[0].split(separator: "[")[1].split(separator: "]")[0]
    #expect(bracketContent.count == 5)  // "HH:MM"
    #expect(bracketContent.contains(":"))
}

@Test func useCaseJoinsMultipleSegments() async throws {
    let segments = try [
        TranscriptionSegment(text: "今日は", startTime: 0, endTime: 1),
        TranscriptionSegment(text: "天気がいい", startTime: 1, endTime: 3),
    ]
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: segments)

    let capturedTexts = ActorBox<[String]>([])
    let sink = CapturingSink { text, _ in
        await capturedTexts.appendString(text)
    }

    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        sink: sink,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    let texts = await capturedTexts.value
    #expect(texts.count == 1)
    #expect(texts[0].contains("今日は 天気がいい"))
}

@Test func useCaseAppliesTextProcessor() async throws {
    // TextProcessor（フィラー除去）が UseCase のパイプラインに組み込まれていることを確認
    let segment = try TranscriptionSegment(text: "えーと 今日は天気がいい", startTime: 0, endTime: 3)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])

    let capturedTexts = ActorBox<[String]>([])
    let sink = CapturingSink { text, _ in
        await capturedTexts.appendString(text)
    }

    let processor = FillerTextProcessor()
    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        textProcessor: processor,
        sink: sink,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    let texts = await capturedTexts.value
    #expect(texts.count == 1)
    #expect(texts[0].contains("今日は天気がいい"))
    #expect(!texts[0].contains("えーと"))
}

@Test func useCaseSkipsWriteWhenOnlyFillersRemain() async throws {
    // フィラー除去後にテキストが空になった場合は書き込みをスキップする
    let segment = try TranscriptionSegment(text: "えーと", startTime: 0, endTime: 2)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])

    let writeCount = ActorBox<Int>(0)
    let sink = CapturingSink { _, _ in await writeCount.increment() }

    let processor = FillerTextProcessor()
    let useCase = AppendDailyVoiceNoteUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        textProcessor: processor,
        sink: sink,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(await writeCount.value == 0)
}

// MARK: - ActorBox helper

private actor ActorBox<T: Sendable> {
    var value: T
    init(_ value: T) { self.value = value }
}

extension ActorBox where T == [Date] {
    func append(_ date: Date) { value.append(date) }
}

extension ActorBox where T == [String] {
    func appendString(_ string: String) { value.append(string) }
}

extension ActorBox where T == Int {
    func increment() { value += 1 }
}
