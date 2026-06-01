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

if [[ $UNINSTALL -eq 1 ]]; then
  echo "==> uninstalling"
  if [[ -f "$HOOKS_JSON" ]]; then
    bk="$HOOKS_JSON.$(stamp).bak"
    if [[ $DRY -eq 1 ]]; then
      echo "    would back up $HOOKS_JSON -> $bk"
    else
      cp "$HOOKS_JSON" "$bk"
      echo "    backed up $HOOKS_JSON -> $bk"
    fi
    new="$(jq '
      .hooks.stop |= ((. // []) | map(select(.command | test("attention-beep") | not)))
      | .hooks.beforeShellExecution |= ((. // []) | map(select(.command | test("attention-beep") | not)))
      | .hooks.stop = (if (.hooks.stop // [] | length) == 0 then null else .hooks.stop end)
      | .hooks.beforeShellExecution = (if (.hooks.beforeShellExecution // [] | length) == 0 then null else .hooks.beforeShellExecution end)
      | .hooks |= with_entries(select(.value != null))
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
  bk="$HOOKS_JSON.$(stamp).bak"
  if [[ $DRY -eq 1 ]]; then
    echo "    would back up $HOOKS_JSON -> $bk"
  else
    cp "$HOOKS_JSON" "$bk"
    echo "    backed up $HOOKS_JSON -> $bk"
  fi

  # Merge: append our entries iff not already present (matched by command substring).
  merged="$(jq '
    def ensure(path; entry):
      if (getpath(path) // []) | any(.command | test("attention-beep"))
      then .
      else setpath(path; ((getpath(path) // []) + [entry]))
      end;
    .version = (.version // 1)
    | .hooks = (.hooks // {})
    | ensure(["hooks","stop"]; {command: "./hooks/attention-beep.sh stop", timeout: 5})
    | ensure(["hooks","beforeShellExecution"]; {command: "./hooks/attention-beep.sh shell", timeout: 5})
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
    1. Open Cursor -> Settings -> Hooks (the entries should appear).
    2. End an agent turn -- you should hear Sosumi.
    3. To test manually:
         echo '{"command":"curl https://example.com"}' | $SCRIPT_DST shell    # beep
         echo '{"command":"ls"}'                       | $SCRIPT_DST shell    # silent
         $SCRIPT_DST stop </dev/null                                          # beep

==> customize via env vars (set in your shell profile):
      ATTENTION_BEEP_SOUND=/System/Library/Sounds/Glass.aiff
      ATTENTION_BEEP_DISABLE=1
      ATTENTION_BEEP_PATTERN='your-extended-regex'

==> uninstall:
      ./install.sh --uninstall
EOF
