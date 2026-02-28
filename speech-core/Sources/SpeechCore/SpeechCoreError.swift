/// SpeechCore で発生するエラー。
public enum SpeechCoreError: Error, Equatable {
    case fileNotFound
    case unsupportedFormat
    case transcriptionFailed(String)

    public static func == (lhs: SpeechCoreError, rhs: SpeechCoreError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound, .fileNotFound): true
        case (.unsupportedFormat, .unsupportedFormat): true
        case (.transcriptionFailed(let l), .transcriptionFailed(let r)): l == r
        default: false
        }
    }
}
