# speech-file spec

音声ファイルを文字起こしして `.md` を生成して終了する CLI。
フォルダ監視は外に委譲する（launchd / fswatch）。

## Output

- 既定ファイル名: `YYYY-MM-DD_HH-mm.md`（同一分の衝突は `_01` などで回避）
- 本文はタイムスタンプ付きのエントリ列
  - 既定: `- [HH:MM:SS] <text>`
  - 話者分離が取れる場合: `- [HH:MM:SS] Speaker 1: <text>`

## Engines（v0 の考え方）

- デフォルトは Azure Speech の diarization（Speaker 1/2 で十分）
- Azure の認証情報がない場合は Apple Speech（macOS 26）にフォールバックして “確実に動く” を優先
- 不満があれば `--engine` で切り替えられる仕様にする

## CLI（最小）

- 入力: 音声ファイルパス
- 出力: `--output`（任意） / `--output-dir`（任意）
- その他: `--locale`, `--verbose`
  - `--engine`（任意）: `azure` (default) | `apple`

## Components（切り方）

- `SpeechFileCommand`（引数検証 + 実行）
- `FileTranscriberProtocol` 実装（Apple / Azure など）
- `MarkdownWriter`（segments → markdown）
- `OutputPathResolver`（出力パス決定）

## CI

- Speech API の都合で macOS 26 SDK が必要になる可能性があるため、基本は self-hosted runner（mac mini）で build/test を回す
- CI は Unit test 中心（実音声の E2E はローカルで）
