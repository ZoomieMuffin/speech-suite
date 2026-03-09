import Foundation

/// カーソル位置へのテキスト挿入を抽象化するプロトコル。
/// AX API またはクリップボード経由での挿入を想定するため @MainActor に制約する。
@MainActor
public protocol TextInserterProtocol: Sendable {
    /// テキストをカーソル位置に挿入する。
    func insert(_ text: String) async throws
}
