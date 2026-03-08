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
        guard streamTask == nil else { throw SpeechCoreError.alreadyStarted }
        try await recorder.startRecording()
        let stream: AsyncThrowingStream<TranscriptionSegment, SpeechCoreError>
        do {
            stream = try await transcriptionService.start()
        } catch {
            try? await stopRecorder()
            throw error
        }
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
    }

    /// 録音を停止し、蓄積したセグメントを結合してカーソル位置に挿入する。
    public func stop() async throws {
        // transcription を先に停止して最終セグメントを確定させる
        var segments: [TranscriptionSegment] = []
        var firstError: (any Error)?
        do {
            try await transcriptionService.stop()
            segments = try await streamTask?.value ?? []
        } catch {
            firstError = error
            streamTask?.cancel()
            _ = try? await streamTask?.value
        }
        streamTask = nil
        // 録音は必ず停止する — 先行エラーがなければ stop エラーを伝播
        do {
            try await stopRecorder()
        } catch where firstError == nil {
            firstError = error
        }

        if let error = firstError { throw error }
        guard !segments.isEmpty else { return }
        var text = segments.map(\.text).joined()
        if let processor = textProcessor {
            text = try await processor.process(text)
        }
        try await inserter.insert(text)
    }

    private func stopRecorder() async throws {
        _ = try await recorder.stopRecording()
    }
}
