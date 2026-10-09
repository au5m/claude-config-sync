#!/usr/bin/env bash
# config-sync-check.sh — is your Claude configuration in sync?
#
# Reads ~/.claude/config-sync.conf (see examples/config-sync.conf) and checks:
#   - each listed repo for uncommitted, unpushed and (in --report) behind-origin work
#   - each live-file mapping for drift between the repo copy and the live copy
#
# Modes:
#   (no args)   SessionEnd hook: silent when clean; on drift prints one line to
#               stderr and exits 2 so a terminal shows it.
#   --start     SessionStart hook: prints one line to stdout (Claude Code adds
#               stdout to the session context), always exits 0.
#   --report    Full report on stdout for the config-sync skill, always exit 0.
#               Fetches origin first (10s cap) so "behind" is detected.
#
# Both hook modes are silent (exit 0) when there is no config file or none of
# the configured base directories exist, so the plugin is quiet on a machine
# that is not set up yet.
#
# Runs under Git Bash on Windows and bash on Linux/macOS. Needs git only.
# This file must keep LF line endings (.gitattributes enforces it).

set -u

CONF="${CONFIG_SYNC_CONF:-$HOME/.claude/config-sync.conf}"
SKILL_CMD="/config-sync:config-sync"

mode="hook"
case "${1:-}" in
  --report) mode="report" ;;
  --start)  mode="start" ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
esac

expand() {  # ~ and $HOME at the start of a path
  local p="$1"
  case "$p" in
    "~"|"~/"*) p="$HOME${p#"~"}" ;;
    '$HOME'*)  p="$HOME${p#\$HOME}" ;;
  esac
  printf '%s' "$p"
}
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# ---- parse config
base=""; REPOS=(); LIVE=(); LIVEDIR=()
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line="$(trim "$line")"; [ -z "$line" ] && continue
    key="$(trim "${line%%=*}")"; val="$(trim "${line#*=}")"
    case "$key" in
      base)    [ -z "$base" ] && [ -d "$(expand "$val")" ] && base="$(expand "$val")" ;;
      repo)    REPOS+=("$val") ;;
      live)    LIVE+=("$val") ;;
      livedir) LIVEDIR+=("$val") ;;
    esac
  done < "$CONF"
fi

if [ ! -f "$CONF" ]; then
  [ "$mode" = "report" ] && echo "config-sync: no config at $CONF (copy examples/config-sync.conf from the plugin and edit it)"
  exit 0
fi
if [ -z "$base" ] && [ ${#REPOS[@]} -gt 0 ]; then
  # allow absolute repo paths with no base line
  abs=0; for r in "${REPOS[@]}"; do case "$(expand "$r")" in /*|[A-Za-z]:/*) abs=1 ;; esac; done
  if [ $abs -eq 0 ]; then
    [ "$mode" = "report" ] && echo "config-sync: none of the 'base' directories in $CONF exist on this machine"
    exit 0
  fi
fi

resolve() {  # repo-relative or absolute -> absolute
  local p="$(expand "$1")"
  case "$p" in /*|[A-Za-z]:/*) printf '%s' "$p" ;; *) printf '%s' "$base/$p" ;; esac
}

problems=0; out=""
say() { out+="$1"$'\n'; }

# ---- repos
for rr in "${REPOS[@]}"; do
  r="$(resolve "$rr")"; name=$(basename "$r")
  if [ ! -d "$r/.git" ]; then say "$name: missing at $r"; problems=1; continue; fi
  if [ "$mode" = "report" ]; then
    if command -v timeout >/dev/null 2>&1; then
      GIT_TERMINAL_PROMPT=0 timeout 10 git -C "$r" fetch -q origin 2>/dev/null || say "$name: fetch failed (offline or no stored credential); 'behind' may be stale"
    else
      GIT_TERMINAL_PROMPT=0 git -C "$r" fetch -q origin 2>/dev/null || say "$name: fetch failed (offline or no stored credential); 'behind' may be stale"
    fi
  fi
  dirty=$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$r" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
  behind=$(git -C "$r" rev-list --count HEAD..@{u} 2>/dev/null || echo "?")
  if [ "$dirty" != "0" ] || [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then problems=1; fi
  if [ "$mode" = "report" ]; then
    say "== $name  ($(git -C "$r" status -sb 2>/dev/null | head -1))"
    say "   uncommitted: $dirty   unpushed: $ahead   behind origin: $behind"
    [ "$dirty" != "0" ] && say "$(git -C "$r" status --porcelain | sed 's/^/   /')"
  elif [ "$dirty" != "0" ] || [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
    say "$name: $dirty uncommitted, $ahead unpushed, $behind behind"
  fi
done

# ---- live vs repo drift
drift=0; driftlines=""
check_pair() {  # repo-file live-file label
  local rp="$1" lp="$2" label="$3"
  if [ ! -f "$rp" ] && [ ! -f "$lp" ]; then return; fi
  if [ ! -f "$lp" ]; then driftlines+="   $label: missing in live"$'\n'; drift=$((drift+1)); return; fi
  if [ ! -f "$rp" ]; then driftlines+="   $label: missing in repo"$'\n'; drift=$((drift+1)); return; fi
  if ! cmp -s "$rp" "$lp"; then
    local side="repo newer"; [ "$lp" -nt "$rp" ] && side="live newer"
    driftlines+="   $label: differs ($side)"$'\n'; drift=$((drift+1))
  fi
}
for m in "${LIVE[@]}"; do
  rp="$(resolve "$(trim "${m%%->*}")")"; lp="$(expand "$(trim "${m#*->}")")"
  check_pair "$rp" "$lp" "$(basename "$lp")"
done
for m in "${LIVEDIR[@]}"; do
  rd="$(resolve "$(trim "${m%%->*}")")"; ld="$(expand "$(trim "${m#*->}")")"
  [ -d "$rd" ] || { driftlines+="   $(basename "$rd")/: missing in repo"$'\n'; drift=$((drift+1)); continue; }
  while IFS= read -r f; do
    rel="${f#"$rd"/}"; check_pair "$f" "$ld/$rel" "$(basename "$ld")/$rel"
  done < <(find "$rd" -type f | sort)
done
[ $drift -gt 0 ] && problems=1
if [ "$mode" = "report" ]; then
  say "== live vs repo: $drift file(s) differ"
  [ -n "$driftlines" ] && say "${driftlines%$'\n'}"
elif [ $drift -gt 0 ]; then
  say "live config drifted from repo: $drift file(s)"
fi

oneline() { printf '%s' "$out" | paste -sd ';' - | sed 's/;/; /g'; }

case "$mode" in
  report)
    printf '%s' "$out"
    [ $problems -eq 0 ] && echo "config-sync: clean"
    exit 0 ;;
  start)
    [ $problems -ne 0 ] && echo "config-sync check: $(oneline). Mention this to the user at the start of the session and offer to run $SKILL_CMD."
    exit 0 ;;
  *)
    if [ $problems -ne 0 ]; then
      echo "config-sync: $(oneline) -> run $SKILL_CMD next session" >&2
      exit 2
    fi
    exit 0 ;;
esac
