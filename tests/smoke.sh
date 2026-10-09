#!/usr/bin/env bash
# Smoke test for scripts/config-sync-check.sh against throwaway repos.
# Run: bash tests/smoke.sh   (needs git; writes only under a temp dir; 15 checks)
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
S="$HERE/scripts/config-sync-check.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude"
export CONFIG_SYNC_CONF="$HOME/.claude/config-sync.conf"
G="git -c user.name=t -c user.email=t@t"

mk() { git init -q -b main "$T/base/$1"; $G -C "$T/base/$1" commit -q --allow-empty -m init
       git init -q --bare "$T/base/$1.git"; git -C "$T/base/$1" remote add origin "$T/base/$1.git"
       git -C "$T/base/$1" push -q -u origin main; }
mkdir -p "$T/base"; mk skills; mk dotfiles
mkdir -p "$T/base/dotfiles/claude/agents"; echo a > "$T/base/dotfiles/claude/CLAUDE.md"; echo ag > "$T/base/dotfiles/claude/agents/one.md"
git -C "$T/base/dotfiles" add -A; $G -C "$T/base/dotfiles" commit -qm c; git -C "$T/base/dotfiles" push -q
mkdir -p "$HOME/.claude/agents"; cp "$T/base/dotfiles/claude/CLAUDE.md" "$HOME/.claude/"; cp "$T/base/dotfiles/claude/agents/one.md" "$HOME/.claude/agents/"
cat > "$CONFIG_SYNC_CONF" <<EOF
base = /nonexistent/first
base = $T/base
repo = skills
repo = dotfiles
live = dotfiles/claude/CLAUDE.md -> ~/.claude/CLAUDE.md
livedir = dotfiles/claude/agents -> ~/.claude/agents
pr = skills
EOF

fail=0
check() { if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: expected [$2] got [$1]"; fail=1; fi; }

# 1. clean
check "$(bash "$S"; echo "x$?")" "x0" "hook silent + exit 0 when clean"
check "$(bash "$S" --start; echo "x$?")" "x0" "start silent + exit 0 when clean"
check "$(bash "$S" --report | tail -1)" "config-sync: clean" "report says clean"
case "$(bash "$S" --report)" in *"== skills"*"[publish via PR]"*) echo "ok   report marks pr repo";; *) echo "FAIL pr mark"; fail=1;; esac

# 2. dirty everywhere
sleep 1; echo b > "$HOME/.claude/CLAUDE.md"; echo x > "$T/base/skills/new.md"
git clone -q -b main "$T/base/dotfiles.git" "$T/other"; echo z > "$T/other/zz"; git -C "$T/other" add -A; $G -C "$T/other" commit -qm remote; git -C "$T/other" push -q origin main
out="$(bash "$S" 2>&1 >/dev/null; true)"; code=$(bash "$S" 2>/dev/null; echo $?)
check "$code" "2" "hook exits 2 on drift"
case "$out" in *"skills: 1 uncommitted"*"CLAUDE.md"*|*"skills: 1 uncommitted"*"drifted"*) echo "ok   hook names the repo and the drift";; *) echo "FAIL hook line: $out"; fail=1;; esac
sout="$(bash "$S" --start)"; case "$sout" in "config-sync check: "*"offer to run /config-sync:config-sync.") echo "ok   start line shape";; *) echo "FAIL start line: $sout"; fail=1;; esac
rep="$(bash "$S" --report)"
case "$rep" in *"behind origin: 1"*) echo "ok   report detects behind after fetch";; *) echo "FAIL behind not detected"; echo "$rep"; fail=1;; esac
case "$rep" in *"CLAUDE.md: differs (live newer)"*) echo "ok   report flags live newer";; *) echo "FAIL live-newer"; fail=1;; esac

# 3. livedir: missing file in live
rm "$HOME/.claude/agents/one.md"
case "$(bash "$S" --report)" in *"agents/one.md: missing in live"*) echo "ok   livedir missing-in-live";; *) echo "FAIL livedir"; fail=1;; esac

# 3b. repo with no upstream: named, not "?"
git init -q -b main "$T/base/lone"; $G -C "$T/base/lone" commit -q --allow-empty -m init
printf 'base = %s\nrepo = lone\n' "$T/base" > "$T/c3"
case "$(CONFIG_SYNC_CONF=$T/c3 bash "$S" 2>&1 >/dev/null; true)" in *"lone: no upstream branch"*) echo "ok   no-upstream named in hook";; *) echo "FAIL no-upstream hook"; fail=1;; esac
case "$(CONFIG_SYNC_CONF=$T/c3 bash "$S" --report)" in *"no upstream branch"*"push -u origin"*) echo "ok   no-upstream explained in report";; *) echo "FAIL no-upstream report"; fail=1;; esac

# 4. no config / no base: hooks silent
check "$(CONFIG_SYNC_CONF=/nope bash "$S"; echo "x$?")" "x0" "hook silent with no config"
check "$(CONFIG_SYNC_CONF=/nope bash "$S" --start; echo "x$?")" "x0" "start silent with no config"
printf 'base = /nope\nrepo = a\n' > "$T/c2"
check "$(CONFIG_SYNC_CONF=$T/c2 bash "$S"; echo "x$?")" "x0" "hook silent when no base exists"

[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
