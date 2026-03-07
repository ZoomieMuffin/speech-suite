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
    public func start() async throws {
        try await recorder.startRecording()
        let stream: AsyncThrowingStream<TranscriptionSegment, SpeechCoreError>
        do {
            stream = try await transcriptionService.start()
        } catch {
            _ = try? await recorder.stopRecording()
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
        try await transcriptionService.stop()
        // ストリーム終了を待ち、蓄積セグメントを回収
        let segments = try await streamTask?.value ?? []
        streamTask = nil
        _ = try await recorder.stopRecording()

        guard !segments.isEmpty else { return }
        var text = segments.map(\.text).joined()
        if let processor = textProcessor {
            text = try await processor.process(text)
        }
        try await inserter.insert(text)
    }
}
