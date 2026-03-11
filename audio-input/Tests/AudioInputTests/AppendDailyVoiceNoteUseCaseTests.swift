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

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, SpeechCoreError> {
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

// MARK: - ActorBox helper

private actor ActorBox<T: Sendable> {
    var value: T
    init(_ value: T) { self.value = value }
}

extension ActorBox where T == [Date] {
    func append(_ date: Date) { value.append(date) }
}

extension ActorBox where T == Int {
    func increment() { value += 1 }
}
