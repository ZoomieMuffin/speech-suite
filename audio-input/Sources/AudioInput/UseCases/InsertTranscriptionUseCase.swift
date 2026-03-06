import Foundation
import SpeechCore

/// Insert モード: 録音 → 文字起こし → 後処理 → カーソル位置に挿入。
public actor InsertTranscriptionUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let inserter: any TextInserterProtocol
    private let hallucinationFilter: HallucinationFilter
    private var streamTask: Task<Void, Never>?

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

    /// 録音を開始する。
    public func start() async throws {
        try await recorder.startRecording()
        let stream = try await transcriptionService.start()
        streamTask = Task { [hallucinationFilter, textProcessor, inserter] in
            do {
                for try await segment in stream {
                    try Task.checkCancellation()
                    let filtered = hallucinationFilter.filter([segment])
                    guard let seg = filtered.first else { continue }
                    var text = seg.text
                    if let processor = textProcessor {
                        text = try await processor.process(text)
                    }
                    try await inserter.insert(text)
                }
            } catch is CancellationError {
                // Task was cancelled via stop() — expected
            } catch {
                print("[InsertTranscriptionUseCase] stream error: \(error)")
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
}
