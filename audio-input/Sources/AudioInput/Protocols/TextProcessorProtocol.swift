import Foundation

/// 文字起こし結果の後処理を抽象化するプロトコル。
/// v0 ではフィラー除去、将来的には要約・整形を追加。
public protocol TextProcessorProtocol: Sendable {
    /// テキストを後処理して返す。
    func process(_ text: String) async throws -> String
}
