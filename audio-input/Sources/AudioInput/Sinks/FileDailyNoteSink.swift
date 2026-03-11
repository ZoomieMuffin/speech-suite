import Foundation

/// Daily Voice Note の出力先：日付ごとのファイルへの追記。
/// ファイルが存在しなければ作成し、存在すれば末尾に追記する。
/// ディレクトリが存在しなければ自動作成する。
public struct FileDailyNoteSink: OutputSinkProtocol {
    /// Voice Note の保存先ディレクトリ
    public let notesDir: URL

    public init(notesDir: URL) {
        self.notesDir = notesDir
    }

    public func write(_ text: String, date: Date) async throws {
        let fileURL = fileURL(for: date)

        do {
            try FileManager.default.createDirectory(
                at: notesDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw FileDailyNoteSinkError.directoryCreationFailed(notesDir, error.localizedDescription)
        }

        guard let data = text.data(using: .utf8) else { return }

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            throw FileDailyNoteSinkError.writeFailed(fileURL, error.localizedDescription)
        }
    }

    /// 日付から保存先ファイル URL を生成する。形式: YYYY-MM-DD.md
    /// DateFormatter は Sendable な struct に static で持つと並行呼び出し時に thread-safe でない。
    /// Calendar.dateComponents で直接年月日を取得して文字列化することで Formatter を排除する。
    /// Gregorian 固定により非グレゴリオ暦環境でも仕様どおりのファイル名を保証する。
    func fileURL(for date: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let filename = String(format: "%04d-%02d-%02d.md", c.year!, c.month!, c.day!)
        return notesDir.appendingPathComponent(filename)
    }
}

/// FileDailyNoteSink 固有のエラー。
/// 関連値に String を使うことで Sendable を自明に満たす。
/// catch 句で any Error から any Error & Sendable へのキャストが不要になり Swift 6 と整合する。
public enum FileDailyNoteSinkError: Error, LocalizedError, Sendable {
    case directoryCreationFailed(URL, String)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url, let description):
            return "ディレクトリの作成に失敗しました: \(url.path) — \(description)"
        case .writeFailed(let url, let description):
            return "ファイルへの書き込みに失敗しました: \(url.path) — \(description)"
        }
    }
}
