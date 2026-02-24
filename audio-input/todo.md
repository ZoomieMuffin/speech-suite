# audio-input — 実装 TODO

**前提**: 既存コードベースがある場合は `audio-input/` に取り込み、そこから進化させる。
**依存**: `speech-core` Package を先に構築してから着手。
開発環境: **ローカル Mac**

---

## 0. 環境検証（着手前）

- [ ] `sw_vers` / `xcode-select -p` / `swift --version`
- [ ] `./scripts/build-app.sh` → `open build/AudioInput.app` で既存アプリ正常動作確認
- [ ] macOS 26 なら `import Speech` → `SpeechAnalyzer` の存在確認
- [ ] GitHub Actions macOS runner 状況確認（SpeechAnalyzer を参照する場合、runner の SDK でコンパイルできない可能性あり）
- [ ] self-hosted runner（mac mini）で build/test/release を回す方針を確認

---

## Phase 1: 基盤整備（worktree なし、develop ブランチで直接作業）

### 1-1. CI/CD セットアップ

- [ ] `.github/workflows/ci.yml` 作成:
  - whisper.cpp ビルドキャッシュ (`actions/cache`)
  - `swift build`
  - `swift test --filter "UnitTests"`
- [ ] `.github/workflows/release.yml` 作成（タグ push → .app ビルド → GitHub Release）
- [ ] ブランチ保護ルール設定

### 1-2. speech-core 依存の追加

**speech-core の todo.md が完了してから着手。**

- [ ] `Package.swift` に speech-core 依存追加:
  ```swift
  .package(path: "../speech-core")
  // ...
  dependencies: [
      .product(name: "SpeechCore", package: "SpeechCore"),
  ]
  ```
- [ ] `swift build` が通ることを確認

### 1-3. Protocol 導入 + UseCase 分離

既存サービスクラスに speech-core の Protocol を被せ、AppDelegate から UseCase を分離する。

- [ ] `WhisperTranscriber` を `TranscriptionService` (speech-core) に準拠させる
- [ ] `OpenAITranscriber` を `TranscriptionService` に準拠させる
- [ ] `GeminiTranscriber` を `TranscriptionService` に準拠させる
- [ ] `TranscriberRegistry` を `AppDelegate` に導入し、enum `TranscriptionProvider` を廃止
  ```swift
  // Before: enum ベース
  switch settings.provider {
  case .local: whisperTranscriber.transcribe(...)
  case .openai: openAITranscriber.transcribe(...)
  // ...
  }

  // After: Registry ベース
  guard let service = registry.service(for: settings.selectedServiceID) else { ... }
  try await service.transcribe(audioURL: url, language: lang)
  ```
- [ ] `AudioRecorderProtocol` 定義 → `AudioRecorder` を準拠
- [ ] `TextInserterProtocol` 定義 → `TextInserter` を準拠
- [ ] `TextProcessorProtocol` 定義 → `TextProcessor` を準拠
- [ ] `HotkeyManagerProtocol` 定義 → `HotkeyManager` を準拠
- [ ] UseCase 作成（AppDelegate のビジネスロジックを移動）
  - `InsertTranscriptionUseCase`（挿入）
  - `AppendDailyVoiceNoteUseCase`（Daily Voice Note 追記。Phase 1 では骨組みまで）
- [ ] `AppDelegate` を UseCase 呼び出しに簡素化
- [ ] `HallucinationFilter` を speech-core に移動（WhisperTranscriber から抽出）
- [ ] **手動テスト**: `build-app.sh` → アプリの全機能が既存通り動作すること確認
- [ ] commit → develop push

### 1-4. Hotkey 設計（Aqua Voice ライク）

- [ ] デフォルトの Push-to-Talk は「右 Option ホールド」にする（Space はコンフリクトが多い）
- [ ] 後から変更できるように、ホットキーは設定可能にする
- [ ] modifier-only（右 Option 単体）を検知できる方式を採用する:
  - Carbon Hotkey は modifier 単体に弱いことがあるため、必要なら `CGEventTap`（`.flagsChanged`）を併用
  - 右/左 Option の判定は keycode（Right Option）で分ける

### 1-5. 追加モード: アイディアストック（Daily Voice Note）

- [ ] 別ホットキー（設定で変更可）を追加し、Push-to-Talk の出力先を切り替える
  - 通常: アクティブアプリへ挿入
  - ストック: `YYYY-MM-DD-voice.md` に追記（挿入しない）
- [ ] Daily Voice Note の既定ホットキーを Shift + Ctrl + F のホールドにする（設定で変更可）
- [ ] 保存先ディレクトリ（`notesDir`）を設定で指定可能にする（既定: `./audio`。後で Obsidian vault に変更できる）
- [ ] 追記フォーマットを実装する（確定: `- [HH:MM] ...`）
- [ ] 同一日付ファイルが存在する場合は追記、存在しない場合は作成
- [ ] フィラー除去フィルタを実装し、ON/OFF と辞書を設定で変更可能にする
- [ ] エラー時の通知（保存失敗、権限不足など）をオーバーレイ/通知で出す

### 1-5b. UI フィードバック（メニューバー + オーバーレイ）

- [ ] メニューバーアイコン/メニューで状態が分かるようにする（idle/recording/transcribing/error）
- [ ] Push-to-Talk 中のオーバーレイ表示（フォーカスを奪わない）
- [ ] オーバーレイ表示の ON/OFF を設定で切り替え可能にする（既定ON）

### 1-6. 将来（任意）: 後処理プロバイダ（要約/整形）

v0 では実装しないが、後から追加しやすいように「後処理」を抽象化しておく。

- [ ] `TextPostProcessorProtocol`（例: `process(_ text: String) async throws -> String`）を用意
- [ ] 実装は 2 系統を想定:
  - ローカル: フィラー除去など（同期/軽量）
  - LLM: 要約/整形（OpenAI/Gemini 等。API キーと provider 設定が必要）
- [ ] Daily Voice Note は「認識 → 後処理 → 追記」を 1 UseCase に閉じ込める

---

## Phase 2: 並列開発（worktree 展開）

Protocol 化が develop に入った後、以下を展開。**全 worktree 並列可能。**

```
develop (Protocol 化済み)
├── feat/unit-tests          ← worktree A
├── feat/speech-analyzer     ← worktree B
└── feat/daily-voice-note    ← worktree C
```

3 worktree に絞る（コンフリクト最小化）。

```bash
cd ~/workspace/projects/speech-suite
git worktree add ../speech-suite-tests  -b feat/unit-tests
git worktree add ../speech-suite-sa     -b feat/speech-analyzer
git worktree add ../speech-suite-dvn    -b feat/daily-voice-note
```

### 2-A. feat/unit-tests（worktree A）

既存ロジックの Unit test を追加。

- [ ] **AppState テスト**:
  - `addRecord()` 追加・50件制限
  - `saveHistory()` / `loadHistory()` Codable 往復
  - `statusText` 各状態のメッセージ
  - `isRecording` / `isTranscribing` / `isBusy` 判定
- [ ] **TranscriptionUseCase テスト** (Mock DI):
  - 正常フロー: 録音 → 文字起こし → テキスト処理 → 挿入
  - 文字起こし失敗 → エラー伝播
  - テキスト処理スキップ（mode == .none）
- [ ] **TextProcessor テスト**:
  - 各 `TextProcessingMode` のプロンプト生成
  - `isRetryable` 分類（timeout → true, invalidKey → false）
- [ ] **RetryHelper テスト**:
  - 成功時は 1 回で返る
  - retryable エラーで maxAttempts 回リトライ
  - non-retryable エラーで即 throw
- [ ] **TranscriberRegistry テスト** (speech-core 側にもあるが、audio-input 固有の登録パターンをテスト):
  - 全プロバイダ登録 → availableServices に期待通り含まれる
- [ ] PR → CI グリーン → develop マージ

### 2-B. feat/speech-analyzer（worktree B）

macOS 26 SpeechAnalyzer をプロバイダとして追加。

- [ ] `SpeechAnalyzerTranscriber: TranscriptionService` 実装:
  ```swift
  @available(macOS 26, *)
  struct SpeechAnalyzerTranscriber: TranscriptionService {
      var id: String { "speechAnalyzer" }
      var displayName: String { "Apple SpeechAnalyzer" }
      var isAvailable: Bool { true }
      func transcribe(audioURL: URL, language: String) async throws -> String { ... }
  }
  ```
- [ ] `AppDelegate` の Registry 初期化に条件付き登録:
  ```swift
  if #available(macOS 26, *) {
      registry.register(SpeechAnalyzerTranscriber())
  }
  ```
- [ ] SettingsView: Registry ベースでプロバイダ一覧を動的生成
  - macOS 26 未満では SpeechAnalyzer が自動的に非表示
- [ ] セッションタイムアウト検証
- [ ] モデルダウンロード UI を SpeechAnalyzer 選択時は非表示
- [ ] **Unit test**: Mock Registry でプロバイダ切り替えロジック
- [ ] **Integration test（ローカルのみ）**: 短い日本語音声で whisper.cpp と精度比較
- [ ] PR → CI グリーン → develop マージ

### 2-C. feat/daily-voice-note（worktree C）

Daily Voice Note（アイディアストック）モードを追加。

- [ ] 別ホットキー（設定で変更可）で Push-to-Talk → `YYYY-MM-DD-voice.md` に追記
- [ ] 保存先ディレクトリ（`notesDir`）設定 + 権限/エラーハンドリング
- [ ] 追記フォーマット: `- [HH:MM] ...`
- [ ] フィラー除去（既定ON、ON/OFF + 辞書編集可）
- [ ] 保存成功/失敗のフィードバック（通知/オーバーレイ）
- [ ] **Unit test**: 追記行の生成、フィラー除去、ファイル追記のワイヤリング（I/O は Mock）
- [ ] PR → CI グリーン → develop マージ

---

## Phase 3: 追加改善（Phase 2 マージ後）

Phase 2 の変更が安定してから着手。

### 3-1. WhisperKit 移行 PoC

- [ ] WhisperKit を Package.swift に追加してビルド確認
- [ ] `WhisperKitTranscriber: TranscriptionService` PoC
- [ ] CWhisper / vendor/ 除去可否検証
- [ ] 日本語精度・速度の比較
- [ ] 結果を `docs/whisperkit-evaluation.md` にまとめ → 移行判断

### 3-2. クリップボード復元改善

- [ ] ペースト完了検知（AX API / changeCount 監視）
- [ ] 動的タイミング実装（検知 or 最大 3 秒）
- [ ] 主要アプリでの動作検証（ネイティブ / Electron / ブラウザ / ターミナル）

### 3-3. 品質改善

- [ ] `swift-format` / `swiftlint` 導入 + CI 組み込み
- [ ] `NSLog` → `os.Logger` 統一
- [ ] ConstraintFreeWindow ワークアラウンド経過観察
- [ ] Instruments でメモリプロファイル

### 3-4. コンテキスト対応（任意）

入力欄の既存テキストを取得し LLM に文脈として渡す（Daily Voice Note と衝突しやすいので後回し）。

- [ ] AX API でフォーカス要素の `kAXValueAttribute` 読み取り
- [ ] `TextProcessor` のシステムプロンプトにコンテキスト追加
- [ ] 設定で ON/OFF 切り替え（プライバシー配慮）
- [ ] Electron / ブラウザで取得できない場合はコンテキストなしで処理
- [ ] **Unit test**: コンテキスト付き / なしのプロンプト構築

---

## リリース

- [ ] バージョンタグ付け
- [ ] Developer ID コードサイニング
- [ ] GitHub Release にバイナリ添付
- [ ] README.md 更新

---

## 既知のリスク

| # | 課題 | 対処 |
|---|---|---|
| R-1 | Protocol 導入が全ファイルに波及 | Phase 1 で集中対応。手動テストで回帰確認 |
| R-2 | enum `TranscriptionProvider` 廃止の影響 | Settings の永続化形式が変わる → マイグレーション処理 |
| R-3 | CI での whisper.cpp ビルド時間 | actions/cache でキャッシュ |
| R-4 | WhisperKit 移行時の Kotoba-Whisper 互換性 | PoC で事前検証 |
| R-5 | ConstraintFreeWindow ハック | macOS 更新で壊れる可能性 → 都度確認 |
