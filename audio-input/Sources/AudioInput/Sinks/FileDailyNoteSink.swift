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

    public func write(_ text: String) async throws {
        let fileURL = fileURL(for: Date())

        do {
            try FileManager.default.createDirectory(
                at: notesDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw FileDailyNoteSinkError.directoryCreationFailed(notesDir, error)
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
            throw FileDailyNoteSinkError.writeFailed(fileURL, error)
        }
    }

    /// 日付から保存先ファイル URL を生成する。形式: YYYY-MM-DD.md
    func fileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: date)).md"
        return notesDir.appendingPathComponent(filename)
    }
}

/// FileDailyNoteSink 固有のエラー。
public enum FileDailyNoteSinkError: Error, LocalizedError, Sendable {
    case directoryCreationFailed(URL, any Error)
    case writeFailed(URL, any Error)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url, let underlying):
            return "ディレクトリの作成に失敗しました: \(url.path) — \(underlying.localizedDescription)"
        case .writeFailed(let url, let underlying):
            return "ファイルへの書き込みに失敗しました: \(url.path) — \(underlying.localizedDescription)"
        }
    }
}
