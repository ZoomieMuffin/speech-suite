/// マイク入力のリアルタイム文字起こしエンジンが準拠するプロトコル。
public protocol TranscriptionService: Sendable {
    /// 文字起こしを開始し、セグメントを非同期ストリームで返す。
    func start() -> AsyncThrowingStream<TranscriptionSegment, Error>

    /// 文字起こしを停止する。
    func stop() async throws
}
