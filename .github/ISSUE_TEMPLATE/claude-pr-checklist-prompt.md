---
name: Claude PR Checklist Prompt
about: PR ごとの human review checklist を生成する prompt ソース
title: "[Claude checklist] "
labels: ["claude-pr-checklist-prompt"]
assignees: []
---

## Purpose

この Issue は Claude PR Human Checklist workflow の prompt ソースです。
Assignee に入っているメンバーが author の PR にだけ適用されます。

## Checklist Focus

この prompt で重視したい観点を書いてください。例:

- UI の見た目や挙動で人間確認が必要な点
- 長いテキストや edge case の表示崩れ
- 並び順、文言、導線の妥当性
- Figma や仕様意図との一致

## Hints For Claude

Claude に追加で伝えたい判断基準や除外条件があれば書いてください。例:

- デザイン差分がある画面だけ対象にする
- バックエンド変更のみの PR では項目を出さない
- 重要度の低い一般論は出さない

## Example Checks

必要なら、出てほしい checklist の例を箇条書きで書いてください。

- [ ] ローカルで UI の動作確認をしたか
- [ ] 長い文字列でも崩れないか
- [ ] 並び順が意図どおりか
