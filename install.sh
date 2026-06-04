#!/bin/bash
# Install cursor-attention-beep into the user's ~/.cursor/ hooks.
#
# - Copies hooks/attention-beep.sh -> ~/.cursor/hooks/attention-beep.sh
# - Merges hooks.json entries into ~/.cursor/hooks.json (preserving any
#   existing hooks). Backs up the existing file with a UTC timestamp.
# - Idempotent: re-running will not create duplicate entries.
#
# Usage:
#   ./install.sh           # install
#   ./install.sh --dry-run # show what would change
#   ./install.sh --uninstall

set -euo pipefail

DRY=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CURSOR_DIR="$HOME/.cursor"
HOOKS_DIR="$CURSOR_DIR/hooks"
HOOKS_JSON="$CURSOR_DIR/hooks.json"
SCRIPT_SRC="$REPO_DIR/hooks/attention-beep.sh"
SCRIPT_DST="$HOOKS_DIR/attention-beep.sh"

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required (brew install jq)" >&2
  exit 1
}

if [[ "$OSTYPE" != darwin* ]]; then
  echo "warning: this installer is macOS-first; non-macOS systems may need to set ATTENTION_BEEP_SOUND or edit the script." >&2
fi

stamp() { date -u +%Y%m%dT%H%M%SZ; }

backup_hooks_json() {
  local bk="$HOOKS_JSON.$(stamp).bak"
  if [[ $DRY -eq 1 ]]; then
    echo "    would back up $HOOKS_JSON -> $bk"
  else
    cp "$HOOKS_JSON" "$bk"
    echo "    backed up $HOOKS_JSON -> $bk"
  fi
}

if [[ $UNINSTALL -eq 1 ]]; then
  echo "==> uninstalling"
  if [[ -f "$HOOKS_JSON" ]]; then
    backup_hooks_json
    # Strip every entry whose command mentions "attention-beep", from
    # every event list. Then drop empty event lists, then drop empty
    # hooks/version if the whole thing collapses.
    new="$(jq '
      (.hooks // {}) as $h
      | .hooks = (
          $h
          | to_entries
          | map(
              .value |= ((. // []) | map(select(.command | test("attention-beep") | not)))
            )
          | map(select(.value | length > 0))
          | from_entries
        )
    ' "$HOOKS_JSON")"
    if [[ $DRY -eq 1 ]]; then
      echo "    would write to $HOOKS_JSON:"
      printf '%s\n' "$new" | sed 's/^/      /'
    else
      printf '%s\n' "$new" > "$HOOKS_JSON"
      echo "    cleaned $HOOKS_JSON"
    fi
  fi
  if [[ -f "$SCRIPT_DST" ]]; then
    if [[ $DRY -eq 1 ]]; then
      echo "    would remove $SCRIPT_DST"
    else
      rm "$SCRIPT_DST"
      echo "    removed $SCRIPT_DST"
    fi
  fi
  echo "==> done"
  exit 0
fi

echo "==> installing cursor-attention-beep"

[[ -f "$SCRIPT_SRC" ]] || { echo "error: missing $SCRIPT_SRC" >&2; exit 1; }

if [[ $DRY -eq 1 ]]; then
  echo "    would copy $SCRIPT_SRC -> $SCRIPT_DST (chmod +x)"
else
  mkdir -p "$HOOKS_DIR"
  cp "$SCRIPT_SRC" "$SCRIPT_DST"
  chmod +x "$SCRIPT_DST"
  echo "    installed $SCRIPT_DST"
fi

# Render hook commands with the ABSOLUTE path to the installed script.
# hooks.json has no env-var/tilde expansion, and Cursor does not
# guarantee the cwd it spawns hooks from (it varies by workspace), so a
# relative "./hooks/attention-beep.sh" silently fails in any window whose
# cwd is not ~/.cursor/. Absolute paths work regardless of cwd.
CMD_STOP="$SCRIPT_DST stop"
CMD_SHELL="$SCRIPT_DST shell"
CMD_MCP="$SCRIPT_DST mcp"

# Seed used for a fresh install (no existing hooks.json). Reuses the
# exact same merge program below so both paths render identical output.
SEED='{"version":1,"hooks":{}}'

# Merge entries idempotently:
#   1. Strip every existing "attention-beep" entry from every event
#      list (cleans stale/relative entries from prior versions, and any
#      event keys we no longer install -- e.g. preToolUse from v0.2).
#   2. Drop event lists that become empty after the strip.
#   3. Add exactly one attention-beep entry per event we ship, each with
#      an absolute command path.
# Existing non-attention-beep entries on any event key are preserved.
merge_program='
  def ensure(key; cmd):
    .hooks[key] = ((.hooks[key] // []) + [{command: cmd, timeout: 5}]);
  .version = (.version // 1)
  | .hooks = (.hooks // {})
  | .hooks = (
      .hooks
      | to_entries
      | map(.value |= ((. // []) | map(select(.command | test("attention-beep") | not))))
      | map(select(.value | length > 0))
      | from_entries
    )
  | ensure("stop";                 $cmd_stop)
  | ensure("beforeShellExecution"; $cmd_shell)
  | ensure("beforeMCPExecution";   $cmd_mcp)
'

if [[ ! -f "$HOOKS_JSON" ]]; then
  rendered="$(printf '%s' "$SEED" | jq \
    --arg cmd_stop "$CMD_STOP" \
    --arg cmd_shell "$CMD_SHELL" \
    --arg cmd_mcp "$CMD_MCP" \
    "$merge_program")"
  if [[ $DRY -eq 1 ]]; then
    echo "    would create $HOOKS_JSON:"
    printf '%s\n' "$rendered" | sed 's/^/      /'
  else
    printf '%s\n' "$rendered" > "$HOOKS_JSON"
    echo "    created $HOOKS_JSON"
  fi
else
  backup_hooks_json
  merged="$(jq \
    --arg cmd_stop "$CMD_STOP" \
    --arg cmd_shell "$CMD_SHELL" \
    --arg cmd_mcp "$CMD_MCP" \
    "$merge_program" "$HOOKS_JSON")"

  if [[ $DRY -eq 1 ]]; then
    echo "    would write merged $HOOKS_JSON:"
    printf '%s\n' "$merged" | sed 's/^/      /'
  else
    printf '%s\n' "$merged" > "$HOOKS_JSON"
    echo "    merged into $HOOKS_JSON"
  fi
fi

cat <<EOF

==> done. To verify:
    1. Open Cursor -> Settings -> Hooks (3 entries should appear:
       stop, beforeShellExecution, beforeMCPExecution).
    2. End an agent turn -- you should hear Sosumi.
    3. Manual tests:
         echo '{"command":"ssh host hostname"}' | $SCRIPT_DST shell  # beep
         echo '{"command":"git status"}'        | $SCRIPT_DST shell  # silent
         $SCRIPT_DST stop </dev/null                                 # beep
         $SCRIPT_DST mcp  </dev/null                                 # beep
         $SCRIPT_DST edit </dev/null                                 # beep (only if you opt in -- see README)

==> turn parts off via env vars in your shell profile:
      ATTENTION_BEEP_DISABLE=1         # master kill switch
      ATTENTION_BEEP_DISABLE_STOP=1    # silence turn-end beeps
      ATTENTION_BEEP_DISABLE_SHELL=1   # silence shell beeps
      ATTENTION_BEEP_DISABLE_EDIT=1    # silence file-edit beeps
      ATTENTION_BEEP_DISABLE_MCP=1     # silence MCP-call beeps
      ATTENTION_BEEP_SOUND=/System/Library/Sounds/Glass.aiff
      ATTENTION_BEEP_PATTERN='your-extended-regex'   # shell-only

==> uninstall:
      ./install.sh --uninstall
EOF
