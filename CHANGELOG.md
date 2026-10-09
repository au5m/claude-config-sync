# Changelog

Newest first. The plugin has no version field; each entry names the commit range it covers once it is pushed.

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
