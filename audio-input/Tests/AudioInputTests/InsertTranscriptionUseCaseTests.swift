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

private actor FailingRecorder: AudioRecorderProtocol {
    var isRecording = false
    func startRecording() async throws { throw URLError(.cannotConnectToHost) }
    func stopRecording() async throws -> URL { return URL(fileURLWithPath: "/tmp/stub.wav") }
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

private actor FailingTranscriptionService: TranscriptionService {
    nonisolated let id = "failing-stub"
    var isAvailable = false

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, any Error> {
        throw .invalidConfiguration("stub failure")
    }

    func stop() async throws(SpeechCoreError) {}
}

@MainActor
private final class CapturingInserter: TextInserterProtocol {
    var insertedTexts: [String] = []
    func insert(_ text: String) async throws {
        insertedTexts.append(text)
    }
}

private struct UpperCaseProcessor: TextProcessorProtocol {
    func process(_ text: String) async throws -> String {
        text.uppercased()
    }
}

private struct ThrowingProcessor: TextProcessorProtocol {
    func process(_ text: String) async throws -> String {
        throw URLError(.unknown)
    }
}

@MainActor
private final class ThrowingInserter: TextInserterProtocol {
    func insert(_ text: String) async throws {
        throw URLError(.unknown)
    }
}

private actor SlowRecorder: AudioRecorderProtocol {
    var isRecording = false
    func startRecording() async throws {
        try await Task.sleep(for: .milliseconds(50))
        isRecording = true
    }
    func stopRecording() async throws -> URL {
        isRecording = false
        return URL(fileURLWithPath: "/tmp/stub.wav")
    }
}

// MARK: - Tests

@Test @MainActor func insertUseCaseNormalFlowInsertsText() async throws {
    let segment = try TranscriptionSegment(text: "hello world", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts == ["hello world"])
}

@Test @MainActor func insertUseCaseMultipleSegmentsJoinedWithSpace() async throws {
    let seg1 = try TranscriptionSegment(text: "first", startTime: 0, endTime: 1)
    let seg2 = try TranscriptionSegment(text: "second", startTime: 1, endTime: 2)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [seg1, seg2])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts == ["first second"])
}

@Test @MainActor func insertUseCaseNoSegmentsSkipsInsert() async throws {
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseWhitespaceOnlySkipsInsert() async throws {
    let segment = try TranscriptionSegment(text: "   ", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseAppliesTextProcessor() async throws {
    let segment = try TranscriptionSegment(text: "hello", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        textProcessor: UpperCaseProcessor(),
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts == ["HELLO"])
}

@Test @MainActor func insertUseCaseRecorderStartFailurePropagates() async throws {
    let recorder = FailingRecorder()
    let transcription = StubTranscriptionService(segments: [])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    await #expect(throws: (any Error).self) {
        try await useCase.start()
    }
    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseTranscriptionStartFailurePropagates() async throws {
    let recorder = StubRecorder()
    let transcription = FailingTranscriptionService()
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    await #expect(throws: SpeechCoreError.self) {
        try await useCase.start()
    }
    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseDoubleStartThrows() async throws {
    let segment = try TranscriptionSegment(text: "テスト", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()

    // SpeechCoreError は Equatable 非準拠のため型でマッチする。
    await #expect(throws: SpeechCoreError.self) {
        try await useCase.start()
    }

    try await useCase.stop()
}

@Test @MainActor func insertUseCaseIdleAfterStartFailure() async throws {
    // recorder が start で失敗した後、state が .idle に戻り再び start() できることを確認。
    let failingRecorder = FailingRecorder()
    let transcription = StubTranscriptionService(segments: [])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: failingRecorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    // 1 回目の start() は失敗する
    await #expect(throws: (any Error).self) {
        try await useCase.start()
    }

    // state が .idle に戻っているため .alreadyStarted を throw しないことを確認。
    // 2 回目の start() も recorder が FailingRecorder なので失敗するが、
    // .alreadyStarted ではなく URLError を throw する。
    await #expect(throws: URLError.self) {
        try await useCase.start()
    }
}

@Test @MainActor func insertUseCaseProcessorFailurePropagatesOnStop() async throws {
    // textProcessor.process(_:) が throw した場合、stop() がそのエラーを伝播することを確認。
    let segment = try TranscriptionSegment(text: "hello", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        textProcessor: ThrowingProcessor(),
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    await #expect(throws: (any Error).self) {
        try await useCase.stop()
    }
    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseInserterFailurePropagatesOnStop() async throws {
    // inserter.insert(_:) が throw した場合、stop() がそのエラーを伝播することを確認。
    let segment = try TranscriptionSegment(text: "hello", startTime: 0, endTime: 1)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [segment])
    let inserter = ThrowingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    try await useCase.start()
    await #expect(throws: (any Error).self) {
        try await useCase.stop()
    }
}

@Test @MainActor func insertUseCaseEarlyStopDuringStartRecording() async throws {
    // start() が recorder.startRecording() を await している最中に stop() を受け取る経路を検証。
    // SlowRecorder が 50ms 待機する間に stop() を送り、stopRequested フラグと
    // stopWhileStartingContinuation の経路（InsertTranscriptionUseCase.swift:87-96）を踏む。
    let recorder = SlowRecorder()
    let transcription = StubTranscriptionService(segments: [])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    // start() を別タスクで起動し、startRecording() await 中に stop() を割り込ませる。
    let startTask = Task { try await useCase.start() }
    try await Task.sleep(for: .milliseconds(10))
    try await useCase.stop()
    try await startTask.value

    // early-stop 後は inserter が呼ばれない。
    #expect(inserter.insertedTexts.isEmpty)
}

@Test @MainActor func insertUseCaseHallucinationFilterRemovesCustomPattern() async throws {
    // カスタムパターン "えーと" に完全一致するセグメントはフィルタで除去され、
    // それ以外の "こんにちは" だけが挿入されることを確認する。
    let fillerSeg  = try TranscriptionSegment(text: "えーと",    startTime: 0, endTime: 1)
    let normalSeg  = try TranscriptionSegment(text: "こんにちは", startTime: 1, endTime: 2)
    let recorder = StubRecorder()
    let transcription = StubTranscriptionService(segments: [fillerSeg, normalSeg])
    let inserter = CapturingInserter()
    let filter = try HallucinationFilter(customPatterns: ["えーと"])

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: filter
    )

    try await useCase.start()
    try await useCase.stop()

    #expect(inserter.insertedTexts == ["こんにちは"])
}
