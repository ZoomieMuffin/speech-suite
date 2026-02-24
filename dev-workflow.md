# 開発ワークフロー共通ガイド

3 プロジェクトの全体設計・開発方針・着手順序。

---

## リポジトリ構成（monorepo）

```
~/workspace/projects/speech-suite/
├── speech-core/          ← 共有 Swift Package（Protocol, Model, Error）
├── audio-input/          ← macOS メニューバーアプリ（Aqua Voice もどき）
├── speech-file/          ← CLI: 音声ファイル → .md
└── dev-workflow.md       ← このファイル
```

### 依存関係

```
speech-core (Swift Package)
└── SpeechCore        ← Protocol, Model, Error, Filter
      ↑                    ↑
      │                    │
audio-input ──────────── speech-file
(GUI アプリ)             (CLI ツール)
```

---

## 着手順序（全体のフェーズ）

```
Phase 0: speech-core 構築
    ↓
Phase 1: 両プロジェクトの基盤整備（CI/CD + speech-core 依存 + Protocol 導入）
    ↓
Phase 2: worktree 並列開発
    ↓
Phase 3: 統合・リリース
```

### Phase 0: speech-core 構築

**最優先**。他の全作業の前提。

1. リポジトリ初期化 + Package.swift
2. `SpeechCore` モジュール: TranscriptionSegment, TranscriptionService Protocol, Registry, Error, HallucinationFilter
3. 全テスト通過 + CI グリーン
4. `v0.1.0` タグ

### Phase 1: 基盤整備

speech-core 完了後、両プロジェクトで並行して作業可能。

**audio-input:**
1. CI/CD セットアップ
2. Package.swift に speech-core 依存追加
3. 既存サービスを speech-core Protocol に準拠させる
4. enum `TranscriptionProvider` → `TranscriberRegistry` 移行
5. UseCase パターン導入（AppDelegate 簡素化）

**speech-file:**
1. リポジトリ初期化 + CI/CD
2. Package.swift に speech-core + ArgumentParser 依存

### Phase 2: worktree 並列開発

```
audio-input:                    speech-file:
├── feat/unit-tests        (A)  ├── feat/cli-and-errors  (A)
├── feat/speech-analyzer   (B)  ├── feat/transcriber     (B)
└── feat/daily-voice-note  (C)  └── feat/folder-watch    (C)
```

合計 6 worktree。各プロジェクト内の worktree は全て並列可能。

Issue 切り分け（最小）:

- Phase 1 で先に入れる（衝突しやすい）: `Package.swift`、設定モデル/永続化、DI ルート配線、UseCase 分離
- Phase 2 は worktree ごとに独立: `feat/unit-tests` / `feat/speech-analyzer` / `feat/daily-voice-note`、speech-file 側は `feat/cli-and-errors` / `feat/transcriber` / `feat/folder-watch`

### Phase 3: 統合・リリース

- worktree → develop → main マージ
- リリースビルド・署名・GitHub Release

---

## TDD 方針

### テスト分類

| 分類 | 内容 | CI | ローカル |
|---|---|---|---|
| **Unit test** | Mock ベースの純粋ロジック | ✅ | ✅ |
| **Integration test** | 実 API + 実ファイル | ❌ | ✅ |
| **Manual test** | 実デバイス操作 | ❌ | ✅ |

### テスト命名

```swift
// CI で実行
@Suite("AppState Unit Tests") struct AppStateUnitTests { ... }
final class AppStateUnitTests: XCTestCase { ... }

// CI 除外
@Suite("Transcriber Integration Tests") struct TranscriberIntegrationTests { ... }
```

CI フィルタ: `swift test --filter "UnitTests"`

### Protocol + Mock + Registry

```
speech-core:
  TranscriptionService (Protocol)
  TranscriberRegistry
  MockTranscriptionService

audio-input:
  WhisperTranscriber: TranscriptionService
  OpenAITranscriber: TranscriptionService
  SpeechAnalyzerTranscriber: TranscriptionService
  → registry.register(...)

speech-file:
  AppleSpeechFileTranscriber: FileTranscriberProtocol
  LegacySpeechFileTranscriber: FileTranscriberProtocol
```

---

## git worktree 運用

### 展開イメージ（Phase 2）

```
~/workspace/projects/
├── speech-suite/             ← develop ブランチ（この monorepo）
├── speech-suite-tests/       ← feat/unit-tests
├── speech-suite-sa/          ← feat/speech-analyzer
├── speech-suite-dvn/         ← feat/daily-voice-note
├── speech-suite-cli/         ← feat/cli-and-errors
├── speech-suite-core/        ← feat/transcriber
└── speech-suite-watch/       ← feat/folder-watch
```

### ルール

1. **Protocol / 共有型は develop で先に確定**。worktree は Mock で独立開発。
2. **worktree 間でファイルを直接コピーしない**。PR → develop マージ経由。
3. **各 worktree で CI が通ること**を PR 前に確認。
4. **Package.swift を触る worktree は 1 つだけ**（コンフリクト防止）。

### コンフリクト最小化

| 手法 | 効果 |
|---|---|
| worktree 数を絞る（各 3 本） | 競合するファイルが減る |
| Protocol を develop で先行確定 | worktree は実装のみに集中 |
| Phase 分けで時間差をつける | Phase 3 の追加改善は Phase 2 安定後 |

---

## CI/CD 設計

### 各プロジェクトの CI 構成

| 対象 | runner | ビルド | テスト |
|---|---|---|---|
| speech-core | `macos-15` | `cd speech-core && swift build` | `cd speech-core && swift test` |
| audio-input | self-hosted（mac mini, macOS 26） | `cd audio-input && swift build` | `cd audio-input && swift test --filter UnitTests` |
| speech-file | self-hosted（mac mini, macOS 26） | `cd speech-file && swift build` | `cd speech-file && swift test --filter UnitTests` |

> **注意 (macOS 26 API)**: `SpeechAnalyzer` / `SpeechTranscriber` のように **新しい SDK でしか存在しない型** を Swift で参照する場合、
> `#available` でガードしても **CI の古い SDK ではコンパイル自体が失敗**することがある。
> その場合は次のいずれかを採用する:
> - self-hosted runner（mac mini, macOS 26）で build / release を行う
> - SpeechAnalyzer 依存のコードを別ターゲット/別モジュールに分離し、CI ではそのターゲットをビルドしない

### モノレポの CI ポイント

- 依存関係は同一 repo 内なので “downstream checkout” は不要
- SDK 制約がある対象（audio-input / speech-file）は self-hosted で回す

### Release ワークフロー

```
.github/workflows/
├── ci.yml          ← push / PR: build + test
└── release.yml     ← tag push: release build + sign + GitHub Release
```

---

## Mac ↔ Linux 環境

| 項目 | ローカル Mac | リモート Linux |
|---|---|---|
| `swift build` (speech-core) | ✅ | 条件付き ✅ (Foundation のみなら) |
| `swift test` (speech-core) | ✅ | 条件付き ✅ |
| `swift build` (audio-input / speech-file) | ✅ | ❌ (macOS framework 依存) |
| git 操作 | ✅ | ✅ |
| ドキュメント編集 | ✅ | ✅ |
| CI ログ確認 | ✅ | ✅ |

**開発・テストはすべてローカル Mac で行う。**
リモート Linux では git 操作・ドキュメント編集・CI ログ確認のみ。
speech-core の純粋ロジック部分は Linux でもテスト可能な可能性あり（`#if canImport(Speech)` 分岐で）。

---

## 推奨ツール

| ツール | 用途 | インストール |
|---|---|---|
| `swift-format` | フォーマット | `brew install swift-format` |
| `swiftlint` | Lint | `brew install swiftlint` |
| `Instruments` | プロファイル | Xcode 付属 |
| `gh` | GitHub CLI | `brew install gh` |
| `fswatch` | フォルダ監視 | `brew install fswatch` |
