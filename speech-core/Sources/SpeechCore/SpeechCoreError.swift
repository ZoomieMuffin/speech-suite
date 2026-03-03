import Foundation

/// SpeechCore で発生するエラー。
public enum SpeechCoreError: Error, Sendable {
    // --- PRV-83 新規ケース ---
    case fileNotFound(path: String)
    case unsupportedFormat(path: String)
    case permissionDenied(permission: String)
    case engineUnavailable(engine: String, requiredOS: String)
    case recognitionFailed(underlying: any Error & Sendable)
    case timeout
    case emptyResult

    // --- 既存ケース（先行 issue で導入済み、後日整理） ---
    case invalidTimeRange
    case invalidConfiguration(String)
    /// start() を既に開始済みの状態で再呼び出しした場合。
    case alreadyStarted
    /// file:// スキーム以外の URL が渡された場合など、入力 URL が無効な場合。
    case invalidInputURL
}

extension SpeechCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "File not found: \(path)"
        case .unsupportedFormat(let path):
            "Unsupported audio format: \(path)"
        case .permissionDenied(let permission):
            "Permission denied: \(permission)"
        case .engineUnavailable(let engine, let requiredOS):
            "\(engine) requires \(requiredOS) or later"
        case .recognitionFailed(let underlying):
            "Recognition failed: \(underlying.localizedDescription)"
        case .timeout:
            "Recognition timed out"
        case .emptyResult:
            "Recognition produced no results"
        case .invalidTimeRange:
            "Invalid time range"
        case .invalidConfiguration(let message):
            "Invalid configuration: \(message)"
        case .alreadyStarted:
            "Already started"
        case .invalidInputURL:
            "Invalid input URL"
        }
    }
}
