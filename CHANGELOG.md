# Changelog

Newest first. The plugin has no version field; each entry names the commit range it covers once it is pushed.

## 2026-10-14 — LF for all text files
- `.gitattributes`: new baseline `* text=auto eol=lf` (png, jpg, zip as binary) above the existing `*.sh` and `*.conf` rules. Why: Git for Windows defaults to `core.autocrlf=true`, which checked out `hooks.json`, Markdown and workflow files with CRLF. The index was already LF; renormalize changed no file.

## 2026-10-11 (later) — start check names the drifted files
- `--start` lists each drifted file (same lines as `--report`: name, differs/missing, which side is newer) under the summary, up to 5, then `and N more`. SKILL.md: Claude names the files one per line and offers the full list; "show all drift" runs `--report`. Smoke test: 19 checks.

## 2026-10-11 — skill merges its own PR; .env.example
- For a `pr = <repo>` repo the skill now merges the PR it opened after the one approval (`gh pr merge --squash --delete-branch`, then `git checkout <default> && git pull --ff-only`) and reports the merged commit. The approval point is still the diff and the commit message. Without `gh` it pushes the branch and the user opens and merges the PR. SKILL.md safety rules and README updated to match.
- `.env.example` added (config-sync reads no environment variables).

## 2026-10-09 (evening) — ready for other people
- Skill gains a first-run setup: with no conf it finds your repos, drafts `~/.claude/config-sync.conf`, and writes it on approval.
- Check script names a repo with no upstream branch instead of printing `?`.
- README: requirements, desktop-app install path, example start message, uninstall; plugin-update troubleshooting corrected to the documented `claude plugin marketplace update` + `claude plugin update` flow; Windows WSL-bash gotcha.
- GitHub Actions: smoke test on Ubuntu and Windows.

## 2026-10-09 (later) — PR-based publish for skills repos
- Verified: claude.ai syncs a marketplace within minutes of a PR merge into the default branch; a plain push does nothing. Docs updated accordingly.
- New conf line `pr = <repo>`: the skill commits that repo on a branch and opens a PR instead of pushing to its default branch. `--report` marks such repos `[publish via PR]`.

## 2026-10-09 — first public version
- Extracted from a private skill into a standalone plugin.
- `scripts/config-sync-check.sh`: reads `~/.claude/config-sync.conf` (base, repo, live, livedir lines); three modes: SessionEnd (stderr, exit 2), `--start` (stdout, exit 0), `--report` (fetches origin, detects behind).
- `hooks/hooks.json`: SessionStart and SessionEnd registered by the plugin; no `settings.json` edit needed.
- `skills/config-sync/SKILL.md`: detect, reverse pass, commit and push with gitleaks, forward pass, report.
- `tests/smoke.sh`: 12 checks against throwaway repos.
- `.gitattributes` forces LF for `*.sh` and `*.conf`.
