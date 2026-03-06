import Foundation

/// 文字起こし結果の出力先を抽象化するプロトコル。
/// Insert モード（カーソル挿入）と Daily Voice Note モード（ファイル追記）で実装を切り替える。
public protocol OutputSinkProtocol: Sendable {
    /// テキストを出力先に書き出す。
    func write(_ text: String) async throws
}
