import Foundation

/// アプリの録音状態を UI レイヤーへ公開する Observable モデル。
/// AppController が更新し、MenuBarExtra ラベルとオーバーレイが購読する。
@MainActor
@Observable
public final class AppState {
    /// ホットキーモード。
    public enum RecordingMode: Equatable {
        case insert
        case dvn
    }

    /// アプリの状態。
    public enum Status: Equatable {
        case idle
        case recording(RecordingMode)
        case transcribing(RecordingMode)
        case error
    }

    /// 現在の録音状態。AppController が更新する。
    public var status: Status = .idle

    /// 0.0〜1.0 の正規化音声レベル。録音中に AudioRecorder から更新される。
    /// PRV-72 で具体実装が接続されるまでは 0.0 固定。
    public var audioLevel: Float = 0.0

    public init() {}
}
