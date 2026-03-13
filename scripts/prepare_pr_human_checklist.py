"""
Prepare a prompt for Claude to generate a PR human-review checklist.
"""

from __future__ import annotations

import os
import sys
import uuid

from github import Auth, Github


PROMPT_LABEL = os.getenv("PROMPT_LABEL", "claude-pr-checklist-prompt")
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
    github_token = os.getenv("GITHUB_TOKEN")
    pr_number = os.getenv("PR_NUMBER")
    repository = os.getenv("REPOSITORY")

    if not all([github_token, pr_number, repository]):
        print("Missing required env vars", file=sys.stderr)
        sys.exit(1)

    gh = Github(auth=Auth.Token(github_token))
    repo = gh.get_repo(repository)
    pr = repo.get_pull(int(pr_number))
    pr_author = pr.user.login

    matched_issues = []
    for issue in repo.get_issues(state="open", labels=[PROMPT_LABEL]):
        if issue.pull_request is not None:
            continue
        label_names = {label.name for label in issue.labels}
        if PROMPT_LABEL not in label_names:
            continue
        assignees = {assignee.login for assignee in issue.assignees}
        if pr_author not in assignees:
            continue
        matched_issues.append(issue)

    if not matched_issues:
        set_output("enabled", "false")
        set_output("prompt", "")
        print(
            f"No prompt issues matched label={PROMPT_LABEL} for author={pr_author}"
        )
        return

    matched_issues.sort(key=lambda issue: issue.number)
    prompt_sections = []
    for issue in matched_issues:
        prompt_sections.append(
            "\n".join(
                [
                    f"## Prompt Source: #{issue.number} {issue.title}",
                    issue.body or "",
                ]
            )
        )

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
            *prompt_sections,
        ]
    )

    set_output("enabled", "true")
    set_output("prompt", prompt)
    print(
        f"Prepared checklist prompt from {len(matched_issues)} issue(s) for {pr_author}"
    )


if __name__ == "__main__":
    main()
