import Foundation

/// 音声ファイルを文字起こしするエンジンが準拠するプロトコル。
/// 実装側は fileURL.isFileURL を確認し、ファイルスキーム以外は fileNotFound を投げること。
public protocol FileTranscriberProtocol: Sendable {
    func transcribe(fileURL: URL) async throws(SpeechCoreError) -> [TranscriptionSegment]
}
