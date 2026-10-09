# claude-config-sync

A Claude Code plugin that keeps your Claude configuration in git and tells you when it isn't.

You keep `CLAUDE.md`, `settings.json`, agents and skills in one or more repos. Claude Code reads live copies under `~/.claude/`. Over time the two drift: you edit a live file directly, Claude edits a skill and nobody commits it, a push from another machine never gets pulled. This plugin adds:

- **A start-of-session check.** Every new Claude Code session opens knowing whether anything is uncommitted, unpushed, behind origin, or different between repo and live copy. If so, Claude says it and offers to fix it. Silent when clean.
- **A `config-sync` skill** that does the fix: pulls live edits into the repo, commits, pushes, copies repo changes back out to the live files, and re-checks. It shows the diff and the commit message and waits for one approval. It runs gitleaks on every commit.
- **An end-of-session warning** in the terminal, for the days you ignore the first one.

## Requirements

- Claude Code (terminal, or the desktop app's Code tab), on Windows with Git Bash, macOS or Linux
- `git`, with a stored credential or SSH key for your repos
- [`gitleaks`](https://github.com/gitleaks/gitleaks), strongly recommended: every commit is scanned before it happens
- [`gh`](https://cli.github.com/) only if you use the `pr` line (skills repos published through a pull request)

## Install

From a terminal (or inside a terminal Claude Code session, with the leading `claude` dropped):

```
claude plugin marketplace add au5m/claude-config-sync
claude plugin install config-sync@claude-config-sync
```

In the desktop app: `+` next to the prompt box > **Plugins** > **Add marketplace**, enter `au5m/claude-config-sync`, then install **Config sync** from it. The terminal, the desktop app and the VS Code extension share the same settings, so installing in one covers the others.

Then run the skill once:

```
/config-sync:config-sync
```

With no config yet, it finds your repos, drafts `~/.claude/config-sync.conf`, shows it, and writes it when you say yes. You can also write it yourself from [`examples/config-sync.conf`](examples/config-sync.conf):

```ini
base = /c/dev/personal        # first existing base wins, so one conf
base = ~/dev/personal         # can serve a Windows box and a Linux box

repo = claude-skills          # relative to base, or absolute
repo = dotfiles

live    = dotfiles/claude/CLAUDE.md      -> ~/.claude/CLAUDE.md
live    = dotfiles/claude/settings.json  -> ~/.claude/settings.json
livedir = dotfiles/claude/agents         -> ~/.claude/agents

pr = claude-skills            # push this repo through a PR, so claude.ai syncs
```

Keep the conf in your dotfiles repo and map it too, so new machines get it:

```ini
live = dotfiles/claude/config-sync.conf -> ~/.claude/config-sync.conf
```

Start a new session. If the check finds anything, Claude opens with something like:

> The session-start check found 1 uncommitted change in dotfiles and 1 live file in `~/.claude` that differs from the repo. Want me to run `/config-sync:config-sync`?

If it finds nothing, you see nothing; that is the point.

## How it behaves

The skill always runs in this order and stops at the first problem:

1. **Detect.** Runs the check in report mode: fetches origin, lists uncommitted, unpushed and behind-origin work per repo, and every mapped file that differs with which side is newer. Nothing is written.
2. **Reverse pass (live → repo).** A live file newer than its repo copy is copied into the repo and committed on its own, so an edit you made directly in `~/.claude/` is never overwritten. If both sides changed, it stops and shows you both.
3. **Commit and push.** Stage, gitleaks, show the diff and the planned message, wait for your approval, commit, push, confirm nothing is ahead or behind.
4. **Forward pass (repo → live).** A repo file newer than its live copy is copied out and diffed until identical.
5. **Report**, then re-run the check. It is only done when the check says `config-sync: clean`.

What it never does: force-push, rewrite history, delete branches or tracked files, merge or rebase for you, push anywhere but the tracked branch, or commit without showing you the diff.

### The hooks

The plugin ships [`hooks/hooks.json`](hooks/hooks.json), so installing it registers both hooks. You do not edit `settings.json`.

| Hook | What you see |
|---|---|
| `SessionStart` | Claude opens with one sentence about what is out of sync and offers `/config-sync:config-sync`. Works in the terminal and in the desktop app's Code tab. |
| `SessionEnd` | One warning line in the terminal. The desktop app shows nothing here, which is why the start hook exists. |

Both are silent when the machine has no `config-sync.conf` or none of its `base` directories exist, so the plugin can sit in a shared settings file without nagging on a machine you haven't set up.

You can run the check yourself:

```bash
bash ~/.claude/plugins/cache/claude-config-sync/config-sync/*/scripts/config-sync-check.sh --report
```

## Skills repos and claude.ai

If one of your repos is a plugin marketplace that claude.ai or Claude Code installs from, there is no live file to copy; the apps pull from GitHub. Two things to know:

- **claude.ai does not sync on a plain push.** It syncs within a minute or two when a pull request is merged into the default branch (verified on a personal account, 2026-10-09), or when you ask: Settings > Plugins > Add > Manage marketplaces > your marketplace's menu > Check for updates. So for a skills repo, push a branch and merge a PR instead of pushing to `main`; the skill does that for any repo listed on a `pr = <repo>` line in the conf.
- **Claude Code updates installed plugins on its own schedule**, not on every session start. To pull a skills repo change into Claude Code right away: `claude plugin marketplace update <marketplace>` then `claude plugin update <plugin>@<marketplace>`.

### If you only use claude.ai or Cowork

Add the marketplace under Settings > Plugins > Add > Add marketplace, `au5m/claude-config-sync`. The skill works in Cowork when your computer is linked (it can run git there). The hooks only run in Claude Code and the desktop app's Code tab, so the start-of-session check needs one of those.

## Troubleshooting

- **The hook never says anything, even when I know a repo is dirty.** Check that `~/.claude/config-sync.conf` exists and one of its `base` lines is a real directory on this machine. Run the check with `--report` to see what it reads.
- **The terminal says `SessionEnd hook [...] failed:` followed by the sync line.** That is the warning working. Claude Code shows a hook's text only when it exits non-zero, and labels it that way.
- **`$'\r': command not found`** when the hook runs. The script got CRLF line endings, usually from `core.autocrlf=true` on Windows. This repo's `.gitattributes` forces LF for `*.sh`; if you copied the script somewhere else, run `dos2unix` on it or re-clone.
- **"behind origin" never shows up.** The hooks don't fetch (no network at session start). Only `--report`, which the skill runs, does.
- **gitleaks exit code looks wrong.** Don't pipe its output (`| tail`, `| head`); the exit code you get is the pipe's. The skill is told this; if you run it by hand, run it bare.
- **A new version of this plugin was pushed and nothing changed.** Claude Code keeps the installed commit until it is told to look again. From a terminal: `claude plugin marketplace update claude-config-sync` then `claude plugin update config-sync@claude-config-sync`, and start a new session. In the desktop app the Update button may stay grey; uninstall Config sync from its ⋮ menu and install it again from the marketplace. Your conf and repos are untouched either way. (This plugin has no `version` field on purpose: with one, Claude Code would stay on the pinned version until the string changes; without one, every commit is a release.)
- **Windows: the hook fails with a path error or `bash: ... No such file`.** `bash` on PATH resolved to WSL (`C:\Windows\System32\bash.exe`) instead of Git Bash, and WSL cannot read the Windows path in `${CLAUDE_PLUGIN_ROOT}`. Put `C:\Program Files\Git\bin` ahead of `System32` in PATH, or install Git for Windows if it is missing.
- **Commit message starts with a stray character on Windows.** `Set-Content -Encoding UTF8` in PowerShell 5.1 writes a BOM. Use `[IO.File]::WriteAllText` with `UTF8Encoding $false`, or `git commit -m`.

## Uninstall

`claude plugin uninstall config-sync@claude-config-sync` (desktop app: ⋮ on Config sync > Uninstall). Delete `~/.claude/config-sync.conf` if you don't want it. Nothing else was written outside your own repos.

## Development

```bash
bash tests/smoke.sh        # builds throwaway repos in a temp dir, 15 checks
claude plugin validate .   # manifest and skill validation
```

CI runs the smoke test on Ubuntu and Windows (Git Bash) on every push. Changes are tracked in [CHANGELOG.md](CHANGELOG.md). The plugin has no `version` field on purpose: Claude Code then derives the version from the commit, so a push is a release.

## License

MIT. See [LICENSE](LICENSE).
