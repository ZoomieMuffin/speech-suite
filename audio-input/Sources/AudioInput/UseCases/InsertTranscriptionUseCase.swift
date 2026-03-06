import Foundation
import SpeechCore

/// Insert モード: 録音 → 文字起こし → 後処理 → カーソル位置に挿入。
public actor InsertTranscriptionUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let inserter: any TextInserterProtocol
    private let hallucinationFilter: HallucinationFilter

    public init(
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        textProcessor: (any TextProcessorProtocol)? = nil,
        inserter: any TextInserterProtocol,
        hallucinationFilter: HallucinationFilter = try! HallucinationFilter()
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textProcessor = textProcessor
        self.inserter = inserter
        self.hallucinationFilter = hallucinationFilter
    }

    /// 録音を開始する。
    public func start() async throws {
        try await recorder.startRecording()
        let stream = try await transcriptionService.start()
        Task { [hallucinationFilter, textProcessor, inserter] in
            for try await segment in stream {
                let filtered = hallucinationFilter.filter([segment])
                guard let seg = filtered.first else { continue }
                var text = seg.text
                if let processor = textProcessor {
                    text = try await processor.process(text)
                }
                try await inserter.insert(text)
            }
        }
    }

    /// 録音を停止する。
    public func stop() async throws {
        _ = try await recorder.stopRecording()
        try await transcriptionService.stop()
    }
}
