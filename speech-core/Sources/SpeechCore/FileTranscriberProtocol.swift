import Foundation

/// 音声ファイルを文字起こしするエンジンが準拠するプロトコル。
public protocol FileTranscriberProtocol: Sendable {
    func transcribe(fileURL: URL) async throws(SpeechCoreError) -> [TranscriptionSegment]
}
