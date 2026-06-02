#!/bin/bash
# cursor-attention-beep
# https://github.com/aRealGem/cursor-attention-beep
#
# Plays a short macOS system sound when the Cursor agent needs your
# attention. The hook is purely observational: it prints nothing on
# stdout, so Cursor's normal approval flow is unchanged.
#
# Invocation modes (mode = arg 1):
#   stop    play sound. Use in: `stop`
#   shell   play sound iff stdin .command starts (or starts a sub-command
#           after ;, |, ||, &&) with a truly elevated token. Use in:
#           `beforeShellExecution`
#   edit    play sound (matcher in hooks.json filters which tools).
#           Use in: `preToolUse`
#   mcp     play sound. Use in: `beforeMCPExecution`
#
# Default shell tokens that beep:
#   sudo, ssh, scp, sftp, rsync, nc, ncat, telnet, chmod, chown
# Specifically EXCLUDED (tuned out of v0.3.1 based on real-session noise
# data -- agents run these constantly and they're typically
# auto-approved):
#   git, npm, pnpm, yarn, pip, pip3, uv, brew, apt, apt-get, docker,
#   dig, ping, nslookup, host, curl, wget, http(s):// URLs.
#
# Customization via env vars:
#   ATTENTION_BEEP_SOUND          full path to a sound file
#                                 (default: /System/Library/Sounds/Sosumi.aiff)
#   ATTENTION_BEEP_DISABLE=1      master kill switch (no-op all events)
#   ATTENTION_BEEP_DISABLE_STOP=1
#   ATTENTION_BEEP_DISABLE_SHELL=1
#   ATTENTION_BEEP_DISABLE_EDIT=1
#   ATTENTION_BEEP_DISABLE_MCP=1  per-event kill switches
#   ATTENTION_BEEP_PATTERN        override the shell-match regex entirely
#                                 (extended regex)

set -u
mode="${1:-}"
[[ "${ATTENTION_BEEP_DISABLE:-}" = "1" ]] && exit 0

# Read stdin if any. Cursor pipes JSON in; direct CLI tests may pipe
# nothing. Treat absence as empty.
input="$(cat 2>/dev/null || true)"

SOUND_FILE="${ATTENTION_BEEP_SOUND:-/System/Library/Sounds/Sosumi.aiff}"

play() {
  if [[ -f "$SOUND_FILE" ]] && command -v afplay >/dev/null 2>&1; then
    ( afplay "$SOUND_FILE" >/dev/null 2>&1 & )
  elif command -v osascript >/dev/null 2>&1; then
    ( osascript -e 'beep 2' >/dev/null 2>&1 & )
  fi
}

# Anchor matches to the start of a (sub-)command -- start of string, or
# after ; | || && (optionally surrounded by whitespace). This stops
# arguments like ~/.ssh/config (containing "ssh") from triggering the
# `ssh` token when the actual command is just `cat` or `grep`.
DEFAULT_PATTERN='(^|[[:space:]]*(\|\||&&|;|\|)[[:space:]]*)(sudo|ssh|scp|sftp|rsync|nc|ncat|telnet|chmod|chown)([^[:alnum:]_]|$)'
PATTERN="${ATTENTION_BEEP_PATTERN:-$DEFAULT_PATTERN}"

case "$mode" in
  stop)
    [[ "${ATTENTION_BEEP_DISABLE_STOP:-}" = "1" ]] && exit 0
    play
    ;;
  shell)
    [[ "${ATTENTION_BEEP_DISABLE_SHELL:-}" = "1" ]] && exit 0
    cmd="$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null || true)"
    if printf '%s' "$cmd" | grep -qiE "$PATTERN"; then
      play
    fi
    ;;
  edit)
    [[ "${ATTENTION_BEEP_DISABLE_EDIT:-}" = "1" ]] && exit 0
    play
    ;;
  mcp)
    [[ "${ATTENTION_BEEP_DISABLE_MCP:-}" = "1" ]] && exit 0
    play
    ;;
  *)
    # Unknown mode: no-op rather than crash the agent.
    ;;
esac

# Intentionally no JSON on stdout -> no permission decision returned ->
# Cursor's native approval flow stays exactly as it was.
exit 0
