"""
Prepare a prompt for Claude to generate a PR human-review checklist.
"""

from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path


PROMPT_FILE = os.getenv(
    "CHECKLIST_PROMPT_FILE", ".github/claude-checklist-prompt.md"
)
OUTPUT_PATH = os.getenv(
    "CHECKLIST_OUTPUT_PATH", ".tmp/pr-human-checklist.md"
)


def set_output(name: str, value: str) -> None:
    github_output = os.getenv("GITHUB_OUTPUT")
    if not github_output:
        return

    delimiter = f"EOF_{uuid.uuid4().hex}"
    with open(github_output, "a", encoding="utf-8") as fh:
        fh.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")


def main() -> None:
    prompt_path = Path(PROMPT_FILE)
    if not prompt_path.exists():
        set_output("enabled", "false")
        set_output("prompt", "")
        print(f"Prompt file not found: {PROMPT_FILE}")
        return

    user_prompt = prompt_path.read_text(encoding="utf-8").strip()
    if not user_prompt:
        set_output("enabled", "false")
        set_output("prompt", "")
        print("Prompt file is empty")
        return

    prompt = "\n".join(
        [
            "あなたは Pull Request 向けの human checklist generator です。",
            "目的は、AI だけでは判定しにくい確認項目を人間向けのチェックリストとして作ることです。",
            "通常のコードレビューはしないでください。",
            "",
            "重視する観点:",
            "- ローカルでの UI / UX 挙動確認が必要な点",
            "- 正解が一意でない並び順や文言の妥当性",
            "- 長い文字列や edge case の表示崩れ",
            "- Figma / 仕様意図との一致確認",
            "- 手元やステージングでしか確かめにくい内容",
            "",
            "出力ルール:",
            "- 出力は Pull Request コメント本文になる markdown のみ",
            "- 冒頭に短い見出しと 1 行の説明を書く",
            "- 本文は `- [ ]` 形式の checklist にする",
            "- 各項目の直前に `<!-- reason: ... -->` 形式で選定理由を書く",
            "- 差分と無関係な項目は出さない",
            "- 項目数は最大 5 件まで",
            "- 適切な項目がなければ、その旨を短く書く",
            "- GitHub への投稿はしない",
            f"- 完成した markdown を `{OUTPUT_PATH}` に書き出す",
            "",
            "リポジトリは既に checkout 済みです。必要なら git diff やファイル読取で差分を確認してください。",
            "",
            user_prompt,
        ]
    )

    set_output("enabled", "true")
    set_output("prompt", prompt)
    print(f"Prepared checklist prompt from {PROMPT_FILE}")


if __name__ == "__main__":
    main()
