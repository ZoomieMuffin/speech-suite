# speech-file — 実装 TODO

**前提**: monorepo（`speech-suite/`）内の `speech-file/`。`speech-core` Package に依存。
開発環境: **ローカル Mac**

---

## 0. 環境検証（着手前）

- [ ] `sw_vers` / `xcode-select -p` / `swift --version`
- [ ] SpeechTranscriber API の存在確認:
  ```bash
  echo 'import Speech; print(SpeechTranscriber.self)' | swift -
  ```
- [ ] GitHub Actions macOS runner 状況確認（SpeechTranscriber を参照する場合、runner の SDK でコンパイルできない可能性あり）
- [ ] self-hosted runner（mac mini）で build/test/release を回す方針を確認
- [ ] **speech-core が完成済みであること**を確認（`swift test` 全パス）

---

## Phase 1: 基盤整備（develop ブランチで直接作業）

### 1-1. リポジトリ初期化

- [ ] `speech-suite/` の中で `speech-file/` を Swift Package として初期化
- [ ] `cd speech-file && swift package init --type executable --name SpeechFile`
- [ ] `Package.swift`:
  ```swift
  // swift-tools-version: 6.0
  import PackageDescription
  let package = Package(
      name: "SpeechFile",
      platforms: [.macOS(.v15)],
      dependencies: [
          .package(path: "../speech-core"),
          .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
      ],
      targets: [
          .executableTarget(
              name: "SpeechFile",
              dependencies: [
                  .product(name: "SpeechCore", package: "SpeechCore"),
                  .product(name: "ArgumentParser", package: "swift-argument-parser"),
              ]
          ),
          .testTarget(
              name: "SpeechFileTests",
              dependencies: ["SpeechFile"],
              resources: [.copy("Fixtures")]
          ),
      ]
  )
  ```
- [ ] `.gitignore` 作成
- [ ] CI は repo ルート（`speech-suite/.github/workflows/`）でまとめて管理する

### 1-2. CI/CD セットアップ

- [ ] monorepo の workflow で `speech-file` の build/test を回す（self-hosted runner）

---

## Phase 2: 並列開発（worktree 展開）

```
develop
├── feat/cli-and-errors   ← worktree A（CLI + エラーを合併。小さいので）
├── feat/transcriber      ← worktree B（認識エンジン）
└── feat/folder-watch     ← worktree C（監視テンプレート。Swift コードなし）
```

3 worktree。v0 は `.md` 固定のため、共有フォーマッターは使わず `MarkdownWriter` を speech-file 側に持つ。

```bash
cd ~/workspace/projects/speech-suite
git worktree add ../speech-suite-cli   -b feat/cli-and-errors
git worktree add ../speech-suite-core  -b feat/transcriber
git worktree add ../speech-suite-watch -b feat/folder-watch
```

### 依存関係

```
[speech-core 完了] ──→ [Phase 1 完了]
                              │
                    ├── [A: CLI + Errors]     並列
                    ├── [B: Transcriber]      並列
                    └── [C: Folder watch]     並列
                              │
                        [Phase 3: 統合]
```

**A, B, C はすべて並列開発可能。**
A と B は speech-core の型と Mock を使うが互いに依存しない。
C は Swift コードなし（シェルスクリプトと plist のみ）。

---

### 2-A. feat/cli-and-errors（worktree A）

CLI 引数パーサーとエラー型を合わせて実装。どちらも小さい。

**CLI 引数:**
- [ ] **[RED]** テスト: `SpeechFileCommand.parse(["test.m4a"])` が成功
- [ ] **[GREEN]** `SpeechFileCommand: AsyncParsableCommand` 実装:
  ```swift
  @Argument var input: String
  @Option(name: .shortAndLong) var output: String?
  @Option(name: .long) var outputDir: String?
  @Option(name: .shortAndLong) var locale: String = "ja-JP"
  @Option(name: .long) var engine: String = "azure"
  @Flag(name: .shortAndLong) var verbose: Bool = false
  ```
- [ ] **[RED]** テスト: 存在しないファイルパスで `ValidationError`
- [ ] **[GREEN]** `validate()` でファイル存在 + 拡張子チェック
- [ ] 対応拡張子: `m4a`, `wav`, `mp3`, `flac`, `aiff`, `caf`

**エラー型:**
- [ ] `SpeechFileError` 定義（`SpeechCoreError` を拡張、CLI 固有の exit code マッピング追加）
- [ ] **[RED]** テスト: 各エラー → exit code (1/2/3) マッピング
- [ ] **[GREEN]** 実装
- [ ] TCC 権限未付与時のガイドメッセージ

- [ ] 出力仕様（最低限）:
  - 既定で `.md` を生成して終了（stdout は任意/デバッグ用）
  - 出力ファイル名は `YYYY-MM-DD_HH-mm.md` を既定にし、衝突時は `_01` などで回避
  - 出力形式はタイムスタンプ付きセグメント列を基本にする（既定: `[HH:MM:SS]`）

- [ ] PR → CI グリーン → develop マージ

---

### 2-B. feat/transcriber（worktree B）

Apple SpeechTranscriber ラッパー実装。

- [ ] `AppleSpeechFileTranscriber: FileTranscriberProtocol` 実装:
  ```swift
  @available(macOS 26, *)
  struct AppleSpeechFileTranscriber: FileTranscriberProtocol {
      func transcribe(fileURL: URL, locale: Locale)
          -> AsyncThrowingStream<TranscriptionSegment, Error> { ... }
  }
  ```
- [ ] ストリーミング処理（AVAssetReader チャンク読み出し）
- [ ] `LegacySpeechFileTranscriber: FileTranscriberProtocol` (macOS 15 フォールバック)
- [ ] Azure diarization の transcriber を追加（Speaker 1/2）
- [ ] ファクトリ（既定は Azure、認証情報がない場合は Apple にフォールバック）
- [ ] **Unit test**: MockFileTranscriber (speech-core) で認識フロー確認
- [ ] **Integration test（ローカルのみ）**: 短い日本語音声フィクスチャで認識テスト

- [ ] PR → CI グリーン → develop マージ

---

### 2-C. feat/folder-watch（worktree C）

Swift コード不要。テンプレートとスクリプトのみ。

- [ ] `templates/com.nyosegawa.speech-file-watcher.plist` 作成
- [ ] `scripts/watch.sh`: fswatch ベースの監視スクリプト
  ```bash
  #!/bin/bash
  WATCH_DIR="${1:?Usage: watch.sh <dir>}"
  TRANSCRIPT_DIR="${2:-$WATCH_DIR/transcripts}"
  mkdir -p "$TRANSCRIPT_DIR"
  fswatch -0 --event Created "$WATCH_DIR" | while IFS= read -r -d '' file; do
      ext="${file##*.}"
      case "$ext" in m4a|wav|mp3|flac|aiff|caf)
          speech-file "$file" -o "$TRANSCRIPT_DIR/$(basename "${file%.*}").md"
      ;; esac
  done
  ```
- [ ] `scripts/install-watcher.sh` / `scripts/uninstall-watcher.sh`

- [ ] PR → develop マージ

---

## Phase 3: 統合（develop ブランチ）

Phase 2 の全 worktree マージ後。

- [ ] `SpeechFileCommand.run()` で全モジュールをワイヤリング:
  ```swift
  func run() async throws {
      let transcriber = TranscriberFactory.create()
      let writer = MarkdownWriter()
      var segments: [TranscriptionSegment] = []

      for try await segment in transcriber.transcribe(
          fileURL: URL(filePath: input),
          locale: Locale(identifier: locale)
      ) {
          if verbose {
              FileHandle.standardError.write("[  \(segment.startTime)s] \(segment.text)\n".data(using: .utf8)!)
          }
          segments.append(segment)
      }

      let markdown = writer.render(segments: segments)
      let outputURL = OutputPathResolver.resolve(
          inputURL: URL(filePath: input),
          output: output,
          outputDir: outputDir
      )
      try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
  }
  ```
- [ ] `swift build -c release` でリリースビルド確認
- [ ] **Integration test**: 短い日本語音声で E2E テスト
- [ ] **長尺テスト**: 1 時間超ファイルでメモリ計測 (Instruments)
- [ ] README.md 記載

## 将来: 話者分離（任意）

音声→テキスト変換は Apple Speech（SpeechTranscriber）を使うとしても、話者分離（speaker diarization）は別エンジンが必要になる可能性が高い。
まずはタイムスタンプ付きセグメント出力を v0 とし、話者分離は「利用できれば付与する」任意機能として後追いで追加する。

---

## リリース

- [ ] バージョンタグ `v0.1.0` → Release workflow
- [ ] GitHub Release にバイナリ添付確認
- [ ] コードサイニング確認
- [ ] （任意）Homebrew formula

---

## 既知のリスク

| # | 課題 | 対処 |
|---|---|---|
| R-1 | SpeechTranscriber API 名称が異なる可能性 | Step 0 で即確認。ドキュメント参照 |
| R-2 | macOS 26 runner 未対応 | `#available` 分岐で macOS 15 ビルド通過 |
| R-3 | CLI での TCC 権限ダイアログ | `SFSpeechRecognizer.requestAuthorization` を run() 冒頭で呼ぶ |
| R-4 | 長尺ファイル OOM | AVAssetReader チャンク処理 + 実測 |
| R-5 | `WatchPaths` で変更ファイル特定不可 | ラッパースクリプトで `find -newer` |
| R-6 | speech-core の path 参照が CI で壊れる | CI で speech-core を別途 checkout、または git URL 参照 |
