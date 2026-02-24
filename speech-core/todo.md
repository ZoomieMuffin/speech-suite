# speech-core — 実装 TODO

共有 Swift Package。audio-input と speech-file の両方が依存する。
**他の 2 プロジェクトより先に着手し、develop で安定させてから worktree 展開に入る。**

---

## 0. 環境検証

- [ ] ローカル Mac で `swift package init --type library --name SpeechCore` が通ることを確認
- [ ] `swift test` が空テストで通ることを確認

---

## 1. パッケージ初期化（monorepo）

- [ ] `speech-suite/` の中で `speech-core/` を Swift Package として初期化:
  ```bash
  cd ~/workspace/projects/speech-suite
  mkdir -p speech-core && cd speech-core
  swift package init --type library --name SpeechCore
  ```
- [ ] `Package.swift` 設計:
  ```swift
  // swift-tools-version: 6.0
  import PackageDescription
  let package = Package(
      name: "SpeechCore",
      platforms: [.macOS(.v15), .iOS(.v17)],
      products: [
          .library(name: "SpeechCore", targets: ["SpeechCore"]),
      ],
      targets: [
          .target(name: "SpeechCore"),
          .testTarget(name: "SpeechCoreTests", dependencies: ["SpeechCore"]),
      ]
  )
  ```
- [ ] `.gitignore` 作成
- [ ] CI は repo ルート（`speech-suite/.github/workflows/`）でまとめて管理する

---

## 2. SpeechCore モジュール（TDD）

### 2.1 TranscriptionSegment

- [ ] **[RED]** テスト: `Codable` 往復（encode → decode で同値）
- [ ] **[GREEN]** 実装:
  ```swift
  public struct TranscriptionSegment: Sendable, Codable, Equatable {
      public let text: String
      public let startTime: TimeInterval
      public let endTime: TimeInterval
      public let confidence: Float?
  }
  ```

### 2.2 TranscriptionService Protocol + Registry

- [ ] **[RED]** テスト: `MockService` を `register()` → `service(for:)` で取得
- [ ] **[RED]** テスト: `isAvailable == false` のサービスは `availableServices` に含まれない
- [ ] **[GREEN]** `TranscriptionService` Protocol + `TranscriberRegistry` 実装
- [ ] **[RED]** テスト: 同一 ID の二重登録は上書き
- [ ] **[GREEN]** 実装

### 2.3 FileTranscriberProtocol

- [ ] Protocol 定義:
  ```swift
  public protocol FileTranscriberProtocol: Sendable {
      func transcribe(fileURL: URL, locale: Locale) -> AsyncThrowingStream<TranscriptionSegment, Error>
  }
  ```
- [ ] `MockFileTranscriber` 実装（テスト用。固定セグメントを yield）

### 2.4 SpeechCoreError

- [ ] **[RED]** テスト: 各エラーの `errorDescription` が non-nil
- [ ] **[GREEN]** 実装:
  ```swift
  public enum SpeechCoreError: LocalizedError {
      case fileNotFound(path: String)
      case unsupportedFormat(path: String)
      case permissionDenied(permission: String)
      case engineUnavailable(engine: String, requiredOS: String)
      case recognitionFailed(underlying: Error)
      case timeout
      case emptyResult
  }
  ```

### 2.5 HallucinationFilter

audio-input の `WhisperTranscriber` 内にある検出ロジックを抽出。

- [ ] **[RED]** テスト: 既知のハルシネーション文字列（"ご視聴ありがとうございました" 等）を検出
- [ ] **[RED]** テスト: 通常テキストは通過
- [ ] **[GREEN]** 実装

---

## 3. CI グリーン確認 & タグ

- [ ] `swift test` が全テスト通過
- [ ] CI ワークフロー グリーン
- [ ] `v0.1.0` タグ作成 → push
- [ ] audio-input / speech-file から `.package(path: "../speech-core")` で参照できることを確認

---

## 既知のリスク

| # | 課題 | 対処 |
|---|---|---|
| R-1 | 過度な抽象化 | 「今使うもの」だけ入れる。不要な汎用化はしない |
| R-2 | ローカルパス参照が壊れやすい | ディレクトリ配置を dev-workflow.md で統一 |
| R-3 | API 変更が 2 アプリに波及 | SemVer 運用。Protocol 変更は major バンプ |
