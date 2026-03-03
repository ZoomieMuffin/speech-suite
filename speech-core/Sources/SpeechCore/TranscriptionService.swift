/// マイク入力のリアルタイム文字起こしエンジンが準拠するプロトコル。
/// Actor 準拠により start()/stop() の並行アクセスを actor isolation で保護する。
public protocol TranscriptionService: Actor {
    /// サービスを一意に識別する ID。不変のため nonisolated で同期アクセス可。
    nonisolated var id: String { get }

    /// サービスが現在利用可能かどうか。実行時に変化しうるため actor-isolated。
    var isAvailable: Bool { get }

    /// 文字起こしを開始し、セグメントを非同期ストリームで返す。
    /// 既に開始済みの場合は呼び出し時点で SpeechCoreError.alreadyStarted を投げる。
    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, SpeechCoreError>

    /// 文字起こしを停止する。
    func stop() async throws(SpeechCoreError)
}
