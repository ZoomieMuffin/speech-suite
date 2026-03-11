import Foundation
import SpeechCore

/// Insert モード: 録音 → 文字起こし → 後処理 → カーソル位置に挿入。
/// push-to-talk で押している間だけ録音し、離した瞬間（stop）に確定テキストを一括挿入する。
public actor InsertTranscriptionUseCase {
    private let recorder: any AudioRecorderProtocol
    private let transcriptionService: any TranscriptionService
    private let textProcessor: (any TextProcessorProtocol)?
    private let inserter: any TextInserterProtocol
    /// nil の場合はフィルタリングをスキップする（fillerFilterEnabled: false に対応）。
    private let hallucinationFilter: HallucinationFilter?

    private enum State { case idle, active, stopping }
    private var state: State = .idle
    private var streamTask: Task<[TranscriptionSegment], any Error>?

    /// start() の await 中（state==.active, streamTask==nil）に stop() が来た場合のフラグ。
    private var stopRequested = false

    /// stop() が start() の setup 完了を待つための continuation。
    /// stop() はここで suspend し、start() のクリーンアップ完了後に resume される。
    /// これにより activeMode = nil が setup 完了前に起きて別モードが start() するのを防ぐ。
    private var stopWhileStartingContinuation: CheckedContinuation<Void, Never>?

    public init(
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        textProcessor: (any TextProcessorProtocol)? = nil,
        inserter: any TextInserterProtocol,
        hallucinationFilter: HallucinationFilter? = HallucinationFilter.default
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textProcessor = textProcessor
        self.inserter = inserter
        self.hallucinationFilter = hallucinationFilter
    }

    /// 録音を開始し、セグメントの蓄積を始める。
    /// 既に開始済みの場合は SpeechCoreError.alreadyStarted を throw する。
    public func start() async throws {
        guard state == .idle else { throw SpeechCoreError.alreadyStarted }
        state = .active
        stopRequested = false
        do {
            try await recorder.startRecording()
            if stopRequested {
                _ = try? await recorder.stopRecording()
                finishEarlyStop()
                return
            }
            let stream = try await transcriptionService.start()
            if stopRequested {
                try? await transcriptionService.stop()
                _ = try? await recorder.stopRecording()
                finishEarlyStop()
                return
            }
            streamTask = Task { [hallucinationFilter] in
                var segments: [TranscriptionSegment] = []
                for try await segment in stream {
                    try Task.checkCancellation()
                    if let filter = hallucinationFilter {
                        if let seg = filter.filter([segment]).first {
                            segments.append(seg)
                        }
                    } else {
                        segments.append(segment)
                    }
                }
                return segments
            }
        } catch {
            streamTask = nil
            stopRequested = false
            resumeStopContinuation()
            _ = try? await recorder.stopRecording()
            state = .idle
            throw error
        }
    }

    /// 録音を停止し、蓄積したセグメントを結合してカーソル位置に挿入する。
    public func stop() async throws {
        guard state == .active else { return }
        guard let task = streamTask else {
            // start() が await 中（streamTask がまだ nil）。
            // フラグを立てて start() のクリーンアップ完了まで待機する。
            // ここで return せず待つことで AppController が activeMode = nil にする前に
            // recorder / transcriptionService の解放が完了する。
            stopRequested = true
            await withCheckedContinuation { continuation in
                stopWhileStartingContinuation = continuation
            }
            return
        }
        state = .stopping
        streamTask = nil
        defer { state = .idle }

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

        if let error = firstError { throw error }
        guard !segments.isEmpty else { return }
        var text = segments.map(\.text).joined(separator: " ")
        if let processor = textProcessor {
            text = try await processor.process(text)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await inserter.insert(text)
    }

    // MARK: - Private helpers

    /// stopRequested によるクリーンアップを完了させ、待機中の stop() を起こす。
    private func finishEarlyStop() {
        state = .idle
        stopRequested = false
        resumeStopContinuation()
    }

    private func resumeStopContinuation() {
        stopWhileStartingContinuation?.resume()
        stopWhileStartingContinuation = nil
    }
}
