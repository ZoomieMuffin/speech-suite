# audio-input spec

常駐する macOS アプリ。Aqua Voice 風に “押して話す/離して確定” を基本動作にする。
入力欄へ挿入するモードと、Daily Voice Note に保存するモードを切り替えられるようにする。

## Modes

### 1) Insert（Aqua Voice ライク）

- 既定ホットキー: 右 Option のホールド
- 押している間だけ録音/認識
- 離した瞬間に確定テキストをカーソル位置に挿入

### 2) Daily Voice Note（アイディアストック）

- 既定ホットキー: Shift + Ctrl + F のホールド（設定で変更可）
- 別ホットキーで Push-to-Talk
- 確定テキストは “挿入せず” にファイルへ追記する
  - 既定の保存先: `./audio/YYYY-MM-DD-voice.md`（`notesDir` で変更可）
  - 追記フォーマット: `- [HH:MM] <text>`
- フィラー除去: 既定 ON（ON/OFF + 辞書編集可）
- 保存成功/失敗が分かるよう通知/オーバーレイを出す

## UI フィードバック（v0）

- メニューバー常駐は前提。常に状態が分かるようにアイコンを状態反映する（idle/recording/transcribing/error）。
- Push-to-Talk 中は “体感” が重要なので、Aqua Voice 風の軽いオーバーレイ（非アクティブでフォーカスを奪わない）を既定で表示する。
  - 表示する内容は最小: モード（Insert/Daily）+ 録音中表示 + 簡易レベルメーター
  - 途中経過（partial text）は v0 ではオプション扱い（既定OFF）
- オーバーレイは設定でOFFにできる（メニューバーのみでも使えるようにする）。

## Settings（v0）

- hotkey（Insert 用 / Daily Voice Note 用）
- `notesDir`（既定: `./audio`）
- filler filter: enabled / dictionary
 - overlay: enabled

## Components（切り方）

- `HotkeyEngine`（modifier-only と通常ホットキーを扱える）
- `AudioCapture`（録音 start/stop）
- `TranscriptionEngine`（provider は `speech-core` の Registry）
- `TextPostProcessing`（v0 はフィラー除去、将来要約/整形を追加）
- `OutputSink`
  - `TextInsertionSink`（AX API / clipboard fallback）
  - `DailyVoiceNoteSink`（ファイル追記）
- `UseCase`
  - `InsertTranscriptionUseCase`
  - `AppendDailyVoiceNoteUseCase`

## CI

- SpeechAnalyzer 等の macOS 26 SDK が必要になる可能性があるため、基本は self-hosted runner（mac mini）で build/test/release を回す
