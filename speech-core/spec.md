# speech-core spec

`audio-input` と `speech-file` が共通で使う最小の “土台” を Swift Package で提供する。
ここは API を増やしすぎない。アプリ固有（AVAudio/Hotkey/UI/CLI/Azure など）は持ち込まない。

## Goals

- 共通の型・Protocol・エラーを 1 箇所で管理する
- provider の追加を “実装1個 + register” に閉じ込める
- macOS API 非依存のロジックだけを持ち、CI で常にテスト可能にする

## Non-goals

- 音声キャプチャ（AVAudioEngine 等）
- グローバルホットキー
- テキスト挿入（AX API）
- CLI や `.md` 出力
- Azure/OpenAI/Gemini などのクライアント

## Public API（v0）

推奨構成:

```
Sources/
└── SpeechCore/
    ├── TranscriptionSegment.swift
    ├── TranscriptionService.swift
    ├── FileTranscriberProtocol.swift
    ├── SpeechCoreError.swift
    └── HallucinationFilter.swift
```

主要な型:

- `TranscriptionSegment`（話者分離がある場合に備えて `speaker: String?` を optional で持てる）
- `TranscriptionService`（audio-input の “音声URL→テキスト”）
- `FileTranscriberProtocol`（speech-file の “音声ファイル→セグメント列”）
- `SpeechCoreError`
- `HallucinationFilter`

## Registry パターン

enum + switch を廃止し、Registry に provider を登録するだけにする。

Swift 6 の並行実行で事故りにくくするため、Registry は `actor`（または `@MainActor`）で設計する。

## Testing

- speech-core は純ロジックのみ: `swift test` を CI（GitHub-hosted macOS）で常時実行する
- downstream（audio-input / speech-file）に壊れが波及しないよう、必要なら self-hosted runner でビルドも回す

## Versioning

- 開発中: `.package(path: "../speech-core")`
- リリース後: URL + SemVer（Protocol 変更は major）
