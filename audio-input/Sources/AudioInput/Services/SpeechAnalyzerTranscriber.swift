import AVFoundation
import CoreMedia
import Speech
import SpeechCore

/// Apple SpeechAnalyzer フレームワーク (macOS 26+) を使った文字起こしサービス。
/// `TranscriptionService` プロトコルに準拠し、`TranscriberRegistry` 経由で動的に選択できる。
///
/// **動作フロー**
/// 1. `start()` が `AsyncStream<AnalyzerInput>` と `AsyncThrowingStream<TranscriptionSegment>` を生成する。
/// 2. バックグラウンドタスクが `analyse()` を実行: AVAudioEngine でマイク入力を取得し、
///    `AnalyzerInput` として inputStream に yield する。
/// 3. `SpeechAnalyzer.analyzeSequence(_:)` と `SpeechTranscriber.results` の反復を
///    `withThrowingTaskGroup` で並行実行し、確定セグメントを outputStream に yield する。
/// 4. `stop()` が inputContinuation を finish することで inputStream が終端し、
///    analyzeSequence → results stream → タスクグループの順に自然に完了する。
@available(macOS 26, *)
public actor SpeechAnalyzerTranscriber: TranscriptionService {

    // MARK: - TranscriptionService

    public nonisolated let id = "com.speech-suite.speech-analyzer"

    public var isAvailable: Bool { SpeechTranscriber.isAvailable }

    // MARK: - State

    private var isRunning = false
    private var analyzerTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    // MARK: - Init

    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: - TranscriptionService

    public func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, any Error> {
        guard !isRunning else { throw .alreadyStarted }
        isRunning = true

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        let (outputStream, outputContinuation) = AsyncThrowingStream<TranscriptionSegment, any Error>.makeStream()

        let locale = self.locale
        analyzerTask = Task { [weak self] in
            await Self.analyse(
                locale: locale,
                inputStream: inputStream,
                inputContinuation: inputContinuation,
                outputContinuation: outputContinuation
            )
            await self?.onAnalysisFinished()
        }

        return outputStream
    }

    public func stop() async throws(SpeechCoreError) {
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzerTask?.value
        analyzerTask = nil
    }

    // MARK: - Private

    private func onAnalysisFinished() {
        isRunning = false
        inputContinuation = nil
    }

    /// SpeechAnalyzer を用いて音声を文字起こしし、結果を outputContinuation に yield する。
    /// `static` 宣言により actor isolation 外（cooperative thread pool）で実行される。
    ///
    /// - AVAudioEngine の tap が inputContinuation へ `AnalyzerInput` を yield する。
    /// - `withThrowingTaskGroup` により `analyzeSequence` と `results` 反復を並行実行する。
    /// - いずれかのタスクがエラーを投げるとグループがキャンセルされ、他のタスクも終了する。
    private static func analyse(
        locale: Locale,
        inputStream: AsyncStream<AnalyzerInput>,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        outputContinuation: AsyncThrowingStream<TranscriptionSegment, any Error>.Continuation
    ) async {
        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            try await analyzer.prepareToAnalyze(in: audioFormat)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let tapFormat = audioFormat ?? inputNode.outputFormat(forBus: 0)

            // tap コールバックは AVAudioEngine のプライベートスレッドで呼ばれる。
            // Continuation は Sendable なので安全にキャプチャできる。
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                inputContinuation.yield(AnalyzerInput(buffer: buffer))
            }

            try engine.start()
            defer {
                inputNode.removeTap(onBus: 0)
                engine.stop()
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                // タスク A: 入力ストリームを SpeechAnalyzer に送り込む。
                // inputStream が finish されると analyzeSequence が完了する。
                group.addTask {
                    _ = try await analyzer.analyzeSequence(inputStream)
                }

                // タスク B: 確定した文字起こし結果を TranscriptionSegment に変換して yield する。
                // analyzeSequence 完了後 transcriber.results ストリームも終端する。
                group.addTask {
                    for try await result in transcriber.results {
                        guard let segment = try? TranscriptionSegment(
                            text: String(result.text.characters),
                            startTime: result.range.start.seconds,
                            endTime: result.range.end.seconds
                        ) else { continue }
                        outputContinuation.yield(segment)
                    }
                }

                try await group.waitForAll()
            }

            outputContinuation.finish()
        } catch {
            outputContinuation.finish(throwing: error)
        }
    }
}
