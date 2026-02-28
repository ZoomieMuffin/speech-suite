/// マイク入力のリアルタイム文字起こしエンジンが準拠するプロトコル。
/// Actor 準拠により start()/stop() の並行アクセスを actor isolation で保護する。
public protocol TranscriptionService: Actor {
    /// 文字起こしを開始し、セグメントを非同期ストリームで返す。
    /// 既に開始済みの場合は実装側で SpeechCoreError をストリームに流すか無視する契約とする。
    func start() -> AsyncThrowingStream<TranscriptionSegment, SpeechCoreError>

    /// 文字起こしを停止する。
    func stop() async throws(SpeechCoreError)
}
