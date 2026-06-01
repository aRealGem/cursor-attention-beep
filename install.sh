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

if [[ ! -f "$HOOKS_JSON" ]]; then
  if [[ $DRY -eq 1 ]]; then
    echo "    would create $HOOKS_JSON from repo template"
  else
    cp "$REPO_DIR/hooks.json" "$HOOKS_JSON"
    echo "    created $HOOKS_JSON"
  fi
else
  backup_hooks_json
  # Merge our v0.2 entries idempotently. For each event we ensure exactly
  # one entry whose command mentions "attention-beep". Existing user
  # entries on the same event keys are preserved verbatim.
  merged="$(jq --slurpfile tmpl "$REPO_DIR/hooks.json" '
    def ensure(key; entry):
      .hooks[key] = (
        ((.hooks[key] // []) | map(select(.command | test("attention-beep") | not)))
        + [entry]
      );
    . as $orig
    | .version = (.version // 1)
    | .hooks = (.hooks // {})
    | ensure("stop";                 $tmpl[0].hooks.stop[0])
    | ensure("beforeShellExecution"; $tmpl[0].hooks.beforeShellExecution[0])
    | ensure("preToolUse";           $tmpl[0].hooks.preToolUse[0])
    | ensure("beforeMCPExecution";   $tmpl[0].hooks.beforeMCPExecution[0])
  ' "$HOOKS_JSON")"

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
    1. Open Cursor -> Settings -> Hooks (4 entries should appear:
       stop, beforeShellExecution, preToolUse, beforeMCPExecution).
    2. End an agent turn -- you should hear Sosumi.
    3. Manual tests:
         echo '{"command":"curl https://example.com"}' | $SCRIPT_DST shell  # beep
         echo '{"command":"ls"}'                       | $SCRIPT_DST shell  # silent
         $SCRIPT_DST stop </dev/null                                        # beep
         $SCRIPT_DST edit </dev/null                                        # beep
         $SCRIPT_DST mcp  </dev/null                                        # beep

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
