import Foundation

/// 録音の開始・停止を抽象化するプロトコル。
public protocol AudioRecorderProtocol: Sendable {
    /// 録音を開始する。
    func startRecording() async throws
    /// 録音を停止し、録音データの URL を返す。
    func stopRecording() async throws -> URL
    /// 現在録音中かどうか。
    var isRecording: Bool { get async }
}
