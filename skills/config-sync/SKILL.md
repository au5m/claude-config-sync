---
name: config-sync
description: Syncs the user's Claude configuration between its git repos (dotfiles, skills, agents) and the live copies in ~/.claude, in both directions, then commits and pushes. Use this skill whenever a skill, CLAUDE.md, settings.json, agent or hook file was created or edited (by the user or by Claude), when the user says "sync my config", "push my dotfiles", "did I commit that", "is my Claude config in sync", or asks why a skill or setting isn't showing up on another machine or in claude.ai. Also use it when the start-of-session check reported uncommitted, unpushed, behind or drifted files.
---

# config-sync

The user keeps their Claude configuration in git. Each repo is the source of truth, and some files have a live copy under `~/.claude/` that Claude Code actually reads. This skill makes repo and live copy identical, commits, pushes, and says what moved.

Everything machine-specific lives in `~/.claude/config-sync.conf` (format in the plugin's `examples/config-sync.conf`):

| Line | Meaning |
|---|---|
| `base = <dir>` | where the repos live; first existing wins, so one conf works on several machines |
| `repo = <path>` | a repo to keep committed and pushed |
| `live = <repo file> -> <live file>` | the repo is the source for that live file |
| `livedir = <repo dir> -> <live dir>` | same for a whole directory |
| `pr = <repo>` | commit this repo on a branch and open a PR instead of pushing to its default branch (claude.ai marketplaces sync on merge, not on push) |

The check script is `${CLAUDE_PLUGIN_ROOT}/scripts/config-sync-check.sh`. Run it, don't reimplement it.

## Rules

- **Say which machine** every command runs on when the user has more than one.
- **Check before acting.** Run the report first. Never write before showing what the report found.
- **Never** force-push, rewrite history, delete a branch or a tracked file, or merge/rebase on the user's behalf. Push only to the branch the repo already tracks.
- **No secrets in the repos.** Before every commit: `git add` the files, then run gitleaks on the staged changes and abort on exit code 1:
  `gitleaks git --pre-commit --staged --redact --verbose` (gitleaks 8.19+; older: `gitleaks protect --staged --redact --verbose`).
  Run it without a pipe (`| tail` hides the exit code) and report the real exit code. If gitleaks is not installed, say so plainly, read the full diff for tokens, keys and account numbers, and only then commit. Never report a scan that did not run.
- **Commit messages:** imperative first line under 60 characters with a scope (`skills: ...`, `dotfiles: ...`, `agents: ...`), blank line, then why. On Windows write the message file as UTF-8 without BOM (`[IO.File]::WriteAllText($path, $msg, (New-Object System.Text.UTF8Encoding $false))`); `Set-Content -Encoding UTF8` in Windows PowerShell 5.1 puts a BOM in the first line of the commit.
- **Show the diff and the planned commit message, then wait for one approval.** After that, do every step without asking again, unless step 2 finds a conflict.

## Procedure

### 1. Detect

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/config-sync-check.sh" --report
```

The report fetches origin (10s cap) and lists, per repo: uncommitted files, unpushed commits, commits behind origin (pushed from another machine); then every `live`/`livedir` mapping that differs and which side is newer.

If a repo is **behind**: `git pull --ff-only`. If that fails, local and remote both moved: stop, show the user both sides, let them decide.

### 2. Reverse pass (live → repo)

For every mapping where the live copy is newer than the repo copy: copy it into the repo and commit it on its own (`dotfiles: pull live <file> edited outside the repo`). Edits made directly in `~/.claude/` must never be overwritten by step 4.

If both sides changed since the last commit (repo copy differs from `HEAD` *and* live differs from repo), stop and show both versions.

### 3. Commit and push

Per repo with changes: stage, gitleaks, show diff and message, commit, `git push origin <branch>`, then confirm `git status -sb` shows nothing ahead or behind.

For a repo listed as `pr = <repo>`: create a branch (`config-sync/<yyyymmdd-hhmm>`), commit there, push it, run `gh pr create --fill --base <default> --head <branch>`, then check out the default branch again. Do **not** merge the PR yourself; give the user the PR URL. After they merge, `git pull --ff-only` on the next run clears the "behind" state. If `gh` is missing, say so and push the branch; the user opens the PR from the link git prints.

New skill in a marketplace repo: also add its folder to the plugin's `skills` list in `.claude-plugin/marketplace.json`.

### 4. Forward pass (repo → live)

For every mapping where the repo copy is newer: copy it to the live path (or `chezmoi apply` if the user uses chezmoi), then diff until identical.

Skills repos have no live copy to write. claude.ai and Claude Code pull them from GitHub, but **not on a plain push**. claude.ai syncs within a minute or two after a pull request is merged into the default branch, or when asked (Settings > Plugins > Add > Manage marketplaces > the marketplace's menu > Check for updates). Claude Code refreshes installed plugins when it starts. For a `pr` repo, tell the user the PR is open and that merging it is what updates claude.ai; for a pushed repo, tell them claude.ai needs that click.

### 5. Report

One short block: files moved and in which direction, commit hashes, anything skipped and why. Then run the report again; it must end with `config-sync: clean`. If it does not, say what is still dirty instead of declaring done.

## When a hook fires

The plugin registers the check script as a `SessionStart` hook (`--start`) and a `SessionEnd` hook. At session start the line arrives as context: tell the user what it says in one sentence and offer to run this skill; do not run it unasked. At session end (terminal only; the desktop app shows nothing) it is a reminder for next time. Neither is an error. Both are silent when the machine has no config or none of its `base` directories exist.
