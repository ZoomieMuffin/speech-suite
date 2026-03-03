import Foundation

/// 音声ファイルを文字起こしするエンジンが準拠するプロトコル。
///
/// 実装側は `fileURL.isFileURL` を確認し、ファイルスキーム以外の場合は
/// `continuation.finish(throwing: SpeechCoreError.invalidInputURL)` で
/// ストリーム経由でエラーを送出すること。
///
/// - Note: `Failure` 型は `any Error`。Swift 6 の `AsyncThrowingStream` は
///   `Failure == any Error` でのみ構築可能なため、typed throws は使用しない。
public protocol FileTranscriberProtocol: Sendable {
    func transcribe(fileURL: URL, locale: Locale) -> AsyncThrowingStream<TranscriptionSegment, Error>
}
