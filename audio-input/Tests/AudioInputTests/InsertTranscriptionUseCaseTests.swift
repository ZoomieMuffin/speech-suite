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
