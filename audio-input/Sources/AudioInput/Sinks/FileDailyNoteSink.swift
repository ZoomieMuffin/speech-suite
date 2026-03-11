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
    /// locale / calendar を en_US_POSIX + Gregorian に固定し、
    /// 非グレゴリオ暦環境でもファイル名が仕様どおりになることを保証する。
    func fileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: date)).md"
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
