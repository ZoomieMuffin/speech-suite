import Foundation
import SpeechCore

/// Daily Voice Note モード: 録音 → 文字起こし → フィラー除去 → ファイル追記。
public actor AppendDailyVoiceNoteUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let sink: any OutputSinkProtocol
    private let hallucinationFilter: HallucinationFilter
    private var streamTask: Task<Void, Never>?

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

    /// 録音を開始する。
    public func start() async throws {
        try await recorder.startRecording()
        let stream = try await transcriptionService.start()
        streamTask = Task { [hallucinationFilter, textProcessor, sink] in
            do {
                for try await segment in stream {
                    try Task.checkCancellation()
                    let filtered = hallucinationFilter.filter([segment])
                    guard let seg = filtered.first else { continue }
                    var text = seg.text
                    if let processor = textProcessor {
                        text = try await processor.process(text)
                    }
                    let timestamp = Self.currentTimestamp()
                    try await sink.write("- [\(timestamp)] \(text)\n")
                }
            } catch is CancellationError {
                // Task was cancelled via stop() — expected
            } catch {
                print("[AppendDailyVoiceNoteUseCase] stream error: \(error)")
            }
        }
    }

    /// 録音を停止する。
    public func stop() async throws {
        streamTask?.cancel()
        streamTask = nil
        _ = try await recorder.stopRecording()
        try await transcriptionService.stop()
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
