import Foundation

/// 文字起こし結果の出力先を抽象化するプロトコル。
/// Insert モード（カーソル挿入）と Daily Voice Note モード（ファイル追記）で実装を切り替える。
public protocol OutputSinkProtocol: Sendable {
    /// テキストを出力先に書き出す。
    /// - Parameters:
    ///   - text: 書き出すテキスト
    ///   - date: タイムスタンプとファイル名の基準日時。UseCase 側で Date() を一度だけ取得して渡すことで
    ///           日付境界での不整合（23:59 のメモが翌日ファイルに入るズレ）を防ぐ。
    func write(_ text: String, date: Date) async throws
}
