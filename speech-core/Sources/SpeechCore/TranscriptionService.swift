/// マイク入力のリアルタイム文字起こしエンジンが準拠するプロトコル。
public protocol TranscriptionService: Sendable {
    /// 文字起こしを開始する。セグメントは `onSegment` で逐次通知される。
    func start(onSegment: @Sendable (TranscriptionSegment) -> Void) async throws

    /// 文字起こしを停止する。
    func stop() async throws
}
