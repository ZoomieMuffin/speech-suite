import Foundation
import SpeechCore

/// Insert モード: 録音 → 文字起こし → 後処理 → カーソル位置に挿入。
/// push-to-talk で押している間だけ録音し、離した瞬間（stop）に確定テキストを一括挿入する。
public actor InsertTranscriptionUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let inserter: any TextInserterProtocol
    private let hallucinationFilter: HallucinationFilter

    private enum State { case idle, active, stopping }
    private var state: State = .idle
    private var streamTask: Task<[TranscriptionSegment], any Error>?

    public init(
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        textProcessor: (any TextProcessorProtocol)? = nil,
        inserter: any TextInserterProtocol,
        hallucinationFilter: HallucinationFilter? = nil
    ) throws {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textProcessor = textProcessor
        self.inserter = inserter
        self.hallucinationFilter = try hallucinationFilter ?? HallucinationFilter()
    }

    /// 録音を開始し、セグメントの蓄積を始める。
    /// 既に開始済みの場合は SpeechCoreError.alreadyStarted を throw する。
    public func start() async throws {
        guard state == .idle else { throw SpeechCoreError.alreadyStarted }
        // await 前に状態を確保して reentrancy を防ぐ
        state = .active
        do {
            try await recorder.startRecording()
            let stream = try await transcriptionService.start()
            streamTask = Task { [hallucinationFilter] in
                var segments: [TranscriptionSegment] = []
                for try await segment in stream {
                    try Task.checkCancellation()
                    let filtered = hallucinationFilter.filter([segment])
                    if let seg = filtered.first {
                        segments.append(seg)
                    }
                }
                return segments
            }
        } catch {
            streamTask = nil
            _ = try? await recorder.stopRecording()
            state = .idle
            throw error
        }
    }

    /// 録音を停止し、蓄積したセグメントを結合してカーソル位置に挿入する。
    public func stop() async throws {
        guard state == .active, let task = streamTask else { return }
        // await 前に状態とタスクを退避して reentrancy を防ぐ
        state = .stopping
        streamTask = nil

        var segments: [TranscriptionSegment] = []
        var firstError: (any Error)?
        do {
            try await transcriptionService.stop()
            segments = try await task.value
        } catch {
            firstError = error
            task.cancel()
            _ = try? await task.value
        }

        do {
            _ = try await recorder.stopRecording()
        } catch where firstError == nil {
            firstError = error
        }

        state = .idle
        if let error = firstError { throw error }
        guard !segments.isEmpty else { return }
        var text = segments.map(\.text).joined(separator: " ")
        if let processor = textProcessor {
            text = try await processor.process(text)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await inserter.insert(text)
    }
}
