#!/bin/bash
# cursor-attention-beep
# https://github.com/aRealGem/cursor-attention-beep
#
# Plays a short macOS system sound to grab your attention when the Cursor
# agent finishes a turn, or is about to run a likely-gated shell command
# (network access, sudo, package managers, etc.).
#
# This script is purely observational: it never prints a permission decision,
# so Cursor's normal approval flow is unaffected.
#
# Invocation modes:
#   attention-beep.sh stop    # play sound (use in `stop` hook)
#   attention-beep.sh shell   # play sound iff stdin .command matches
#                             # the network/elevated regex (use in
#                             # `beforeShellExecution` hook)
#
# Customization via env vars:
#   ATTENTION_BEEP_SOUND       full path to a sound file
#                              (default: /System/Library/Sounds/Sosumi.aiff)
#   ATTENTION_BEEP_DISABLE=1   no-op all events (kill switch)
#   ATTENTION_BEEP_PATTERN     override the shell-match regex entirely
#                              (extended regex, passed to grep -E)

set -u
mode="${1:-}"
[[ "${ATTENTION_BEEP_DISABLE:-}" = "1" ]] && exit 0

# Read stdin if present (Cursor pipes JSON in; for direct CLI tests
# stdin may be empty -- handle gracefully).
input="$(cat 2>/dev/null || true)"

SOUND_FILE="${ATTENTION_BEEP_SOUND:-/System/Library/Sounds/Sosumi.aiff}"

play() {
  if [[ -f "$SOUND_FILE" ]] && command -v afplay >/dev/null 2>&1; then
    ( afplay "$SOUND_FILE" >/dev/null 2>&1 & )
  elif command -v osascript >/dev/null 2>&1; then
    ( osascript -e 'beep 2' >/dev/null 2>&1 & )
  fi
}

DEFAULT_PATTERN='(^|[^[:alnum:]_])(curl|wget|ssh|scp|sftp|rsync|nc|ncat|telnet|sudo|git|npm|pnpm|yarn|pip|pip3|uv|brew|apt|apt-get|docker|dig|ping|nslookup|host)([^[:alnum:]_]|$)|https?://'
PATTERN="${ATTENTION_BEEP_PATTERN:-$DEFAULT_PATTERN}"

case "$mode" in
  stop)
    play
    ;;
  shell)
    cmd="$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null || true)"
    if printf '%s' "$cmd" | grep -qiE "$PATTERN"; then
      play
    fi
    # No JSON output on purpose -- this hook is observe-only.
    ;;
  *)
    # Unknown mode: be a no-op rather than crashing the agent.
    ;;
esac
exit 0
