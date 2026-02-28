/// SpeechCore で発生するエラー。
public enum SpeechCoreError: Error, Equatable, Sendable {
    case fileNotFound
    case unsupportedFormat
    case transcriptionFailed(String)
    case invalidTimeRange
    case invalidConfiguration(String)
    /// start() を既に開始済みの状態で再呼び出しした場合。
    case alreadyStarted
    /// file:// スキーム以外の URL が渡された場合など、入力 URL が無効な場合。
    case invalidInputURL
}
