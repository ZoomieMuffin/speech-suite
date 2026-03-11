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
    /// nil の場合はフィルタリングをスキップする（fillerFilterEnabled: false に対応）。
    private let hallucinationFilter: HallucinationFilter?

    private enum State { case idle, active, stopping }
    private var state: State = .idle
    private var streamTask: Task<[TranscriptionSegment], any Error>?

    /// セッション開始日時。start() 時に確定し stop() のタイムスタンプ・ファイルパスに使う。
    /// 23:59 に開始して 00:01 に終了しても、録音開始日のファイルに追記される。
    private var sessionDate: Date?

    /// start() の await 中に stop() が来た場合に立てるフラグ。
    /// state == .active だが streamTask == nil の窓で released が届くと stop() が空振りし
    /// 録音だけ走り続ける。このフラグで「起動中に stop が来た」を吸収する。
    private var stopRequested = false

    /// DateFormatter は actor-isolated なインスタンス変数でキャッシュする。
    /// actor が直列アクセスを保証するため、毎呼び出し生成コストを避けつつ thread-safe を維持する。
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "HH:mm"
        return f
    }()

    public init(
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        textProcessor: (any TextProcessorProtocol)? = nil,
        sink: any OutputSinkProtocol,
        hallucinationFilter: HallucinationFilter? = HallucinationFilter.default
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textProcessor = textProcessor
        self.sink = sink
        self.hallucinationFilter = hallucinationFilter
    }

    /// 録音を開始し、セグメントの蓄積を始める。
    /// 既に開始済みの場合は SpeechCoreError.alreadyStarted を throw する。
    public func start() async throws {
        guard state == .idle else { throw SpeechCoreError.alreadyStarted }
        // セッション基準日時を start() 時に確定する。
        // stop() で Date() を取ると日付境界をまたいだ場合に翌日ファイルへ誤入力される。
        sessionDate = Date()
        state = .active
        stopRequested = false
        do {
            try await recorder.startRecording()
            // await から戻った時点で stop() が来ていたらクリーンアップして終了する。
            if stopRequested {
                _ = try? await recorder.stopRecording()
                state = .idle
                sessionDate = nil
                stopRequested = false
                return
            }
            let stream = try await transcriptionService.start()
            if stopRequested {
                try? await transcriptionService.stop()
                _ = try? await recorder.stopRecording()
                state = .idle
                sessionDate = nil
                stopRequested = false
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
            sessionDate = nil
            stopRequested = false
            _ = try? await recorder.stopRecording()
            state = .idle
            throw error
        }
    }

    /// 録音を停止し、蓄積したセグメントを結合してファイルに追記する。
    /// 保存に失敗した場合はエラーを throw する。
    public func stop() async throws {
        guard state == .active else { return }
        // start() の await 中（streamTask がまだ nil）に released が来た場合は
        // フラグだけ立てて戻る。start() 側が await 完了後にチェックしてクリーンアップする。
        guard let task = streamTask else {
            stopRequested = true
            return
        }
        state = .stopping
        streamTask = nil
        let date = sessionDate ?? Date()
        sessionDate = nil
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
        let timestamp = timeFormatter.string(from: date)
        try await sink.write("- [\(timestamp)] \(text)\n", date: date)
    }
}
