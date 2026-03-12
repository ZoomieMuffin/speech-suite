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

private actor FailOnceTranscriptionService: TranscriptionService {
    nonisolated let id = "fail-once-stub"
    var isAvailable = true
    private var callCount = 0

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, any Error> {
        callCount += 1
        if callCount == 1 { throw .invalidConfiguration("first call fails") }
        return AsyncThrowingStream { continuation in continuation.finish() }
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

/// startRecording() への突入を通知し、テストが明示的に解放するまで待機するスタブ。
/// Task.sleep に依存しない同期ポイントで early-stop 経路を安定して検証できる。
private actor HandshakeRecorder: AudioRecorderProtocol {
    var isRecording = false
    private var hasEntered = false
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var proceedContinuation: CheckedContinuation<Void, Never>?

    /// startRecording() に入るまで呼び出し元を待機させる。
    func awaitEntry() async {
        if hasEntered { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }

    /// startRecording() を完了させる。
    func proceed() {
        proceedContinuation?.resume()
        proceedContinuation = nil
    }

    func startRecording() async throws {
        hasEntered = true
        entryContinuation?.resume()
        entryContinuation = nil
        await withCheckedContinuation { proceedContinuation = $0 }
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
    // HandshakeRecorder の同期ポイントで startRecording() 突入を確認してから stop() を発行する。
    // Task.sleep に依存しないため CI 負荷に関わらず安定して動作する。
    let recorder = HandshakeRecorder()
    let transcription = StubTranscriptionService(segments: [])
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    let startTask = Task { try await useCase.start() }
    // startRecording() に入るまで待機 → use case actor はこの時点で空き状態。
    await recorder.awaitEntry()
    // stop() タスクを発行してから yield することで、start() が再開される前に
    // stopRequested フラグが立つことを保証する。
    let stopTask = Task { try await useCase.stop() }
    await Task.yield()
    // startRecording() を完了させ、start() に early-stop を検知させる。
    await recorder.proceed()
    try await stopTask.value
    try await startTask.value

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

@Test @MainActor func insertUseCaseIdleAfterTranscriptionStartFailure() async throws {
    // transcriptionService.start() が失敗した後、state が .idle に戻り
    // 再び start() できることを確認（recorder 失敗の対称テスト）。
    let recorder = StubRecorder()
    let transcription = FailOnceTranscriptionService()
    let inserter = CapturingInserter()

    let useCase = InsertTranscriptionUseCase(
        recorder: recorder,
        transcriptionService: transcription,
        inserter: inserter,
        hallucinationFilter: nil
    )

    // 1 回目: transcription.start() が失敗する
    await #expect(throws: SpeechCoreError.self) {
        try await useCase.start()
    }

    // state が .idle に戻っているため 2 回目は .alreadyStarted を throw せず正常完了する。
    try await useCase.start()
    try await useCase.stop()
    #expect(inserter.insertedTexts.isEmpty)
}
