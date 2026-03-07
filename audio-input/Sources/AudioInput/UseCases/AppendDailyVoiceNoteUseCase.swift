import Foundation
import SpeechCore

/// Daily Voice Note モード: 録音 → 文字起こし → フィラー除去 → ファイル追記。
/// push-to-talk で押している間だけ録音し、離した瞬間（stop）に確定テキストを一括追記する。
/// 保存失敗時はエラーを throw し、UI 側で通知表示に使用する。
public actor AppendDailyVoiceNoteUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let sink: any OutputSinkProtocol
    private let hallucinationFilter: HallucinationFilter
    private var streamTask: Task<[TranscriptionSegment], any Error>?

    public init(
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        textProcessor: (any TextProcessorProtocol)? = nil,
        sink: any OutputSinkProtocol,
        hallucinationFilter: HallucinationFilter? = nil
    ) throws {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textProcessor = textProcessor
        self.sink = sink
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

    /// 録音を停止し、蓄積したセグメントを結合してファイルに追記する。
    /// 保存に失敗した場合はエラーを throw する。
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
        let timestamp = Self.currentTimestamp()
        try await sink.write("- [\(timestamp)] \(text)\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func currentTimestamp() -> String {
        timestampFormatter.string(from: Date())
    }
}
