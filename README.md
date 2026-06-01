# cursor-attention-beep

A small, observe-only Cursor hook that plays a macOS system sound when the agent
finishes a turn, or is about to run a likely-gated shell command (`curl`,
`ssh`, `sudo`, package managers, anything with an `http(s)://` URL, etc.).

It is intentionally small (one shell script, one JSON file) and **never prints a
permission decision**, so Cursor's normal approval prompts are unchanged. The
hook only listens; you still drive the approvals.

Status: alpha. macOS-first. Tested on macOS 25 with Cursor's hook system.

## Why this exists

Cursor has [hooks](https://cursor.com/docs/agent/hooks) but no first-class
"agent is waiting for input" event. Claude Code has a `Notification` event with
a `permission_prompt` matcher and a thriving ecosystem of sound-notification
tools; Cursor does not. This repo fills the obvious gap with the smallest
useful thing.

The closest existing tools and how this one differs:

| Tool | IDE focus | Cursor support | Style |
| --- | --- | --- | --- |
| [`PeonPing/peon-ping`](https://github.com/PeonPing/peon-ping) | Claude Code primary, Cursor adapter | yes (adapter) | voice packs, themes, multi-platform, larger surface |
| [`NazarenoL/cursor-but-fun`](https://github.com/NazarenoL/cursor-but-fun) | Cursor | yes | switches apps to a game while you wait |
| [`beautyfree/cursor-activate-hook`](https://github.com/beautyfree/cursor-window-activate-hook) | Cursor | yes | window focus, not sound |
| [`fsalmons/claude-chime`](https://github.com/fsalmons/claude-chime), [`EryouHao/claude-code-sound-notification`](https://github.com/EryouHao/claude-code-sound-notification), [`ChanMeng666/claude-code-audio-hooks`](https://github.com/ChanMeng666/claude-code-audio-hooks) | Claude Code | no | mature, Claude-only |
| **cursor-attention-beep** | Cursor only | n/a | minimal, single sound, fires only on turn-end + likely-gated shell commands |

If you want voice packs / multi-IDE support / dashboards, use PeonPing. If you
want one short script that pings only when it probably matters, use this.

## How it works

Two hook entries, both pointing at the same shell script:

```json
{
  "version": 1,
  "hooks": {
    "stop": [
      { "command": "./hooks/attention-beep.sh stop", "timeout": 5 }
    ],
    "beforeShellExecution": [
      { "command": "./hooks/attention-beep.sh shell", "timeout": 5 }
    ]
  }
}
```

- `stop` fires once when the agent finishes a turn -> always beeps.
- `beforeShellExecution` fires before every shell command. The script reads
  the JSON command from stdin and beeps **only** when the command matches a
  network/elevated regex (`curl|wget|ssh|scp|sftp|rsync|nc|ncat|telnet|sudo|git|npm|pnpm|yarn|pip|pip3|uv|brew|apt|apt-get|docker|dig|ping|nslookup|host`
  or contains `http(s)://`). On anything else it is silent.

The shell script writes nothing to stdout, so it returns no `permission`
decision. Cursor falls back to its default approval flow for every command.

## Install

Requirements: macOS, `jq`, `afplay` (built in). All are present on every modern
Mac except `jq`, which you can install with `brew install jq`.

```bash
git clone https://github.com/aRealGem/cursor-attention-beep.git
cd cursor-attention-beep
./install.sh
```

The installer:

1. Copies `hooks/attention-beep.sh` -> `~/.cursor/hooks/attention-beep.sh` (`chmod +x`).
2. If `~/.cursor/hooks.json` already exists, backs it up to
   `hooks.json.<UTC>.bak` and **merges** the two entries in (idempotent;
   re-running will not add duplicates).
3. If it does not exist, copies the template.

Dry-run first if you want: `./install.sh --dry-run`.

Verify in Cursor: **Settings -> Hooks** should list both entries. End an agent
turn -> Sosumi.

## Customize

All knobs are environment variables; set them in your shell profile.

| Variable | Default | Effect |
| --- | --- | --- |
| `ATTENTION_BEEP_SOUND` | `/System/Library/Sounds/Sosumi.aiff` | Any `.aiff`/`.wav`/`.mp3` path that `afplay` can play |
| `ATTENTION_BEEP_DISABLE` | unset | If `1`, the hook is a no-op (kill switch) |
| `ATTENTION_BEEP_PATTERN` | see source | Override the shell-match extended regex entirely |

Available system sounds: `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`,
`Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`.

To make it quieter (network-only, no turn-end beep), remove the `stop` entry
from `~/.cursor/hooks.json`. To make it chattier, drop the regex filter.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the script and strips the two entries from `~/.cursor/hooks.json`
(backed up with a UTC timestamp). Other hooks in that file are preserved.

## Manual testing

```bash
echo '{"command":"curl https://example.com"}' | ~/.cursor/hooks/attention-beep.sh shell  # beep
echo '{"command":"ls -la"}'                   | ~/.cursor/hooks/attention-beep.sh shell  # silent
~/.cursor/hooks/attention-beep.sh stop </dev/null                                         # beep
```

## Known gaps and why

Cursor has no hook event that fires specifically when an approval prompt is
shown to the user. (Claude Code has `PermissionRequest` / `Notification` with a
`permission_prompt` matcher; Cursor does not.) The closest events Cursor
exposes are:

- `beforeShellExecution` — fires before each shell command. Covered here.
- `preToolUse` — fires before *every* invocation of a matched tool, whether
  or not Cursor actually pauses for approval.
- `beforeMCPExecution` — fires before every MCP tool call, similarly.

So this hook deliberately **does not** beep on:

- "Accept changes" prompts for `Write` / `StrReplace` / `Edit` / `EditNotebook`.
- MCP tool calls that pause for approval.

Adding `preToolUse(Write|StrReplace|Edit|EditNotebook)` would catch the file
edit gates, but it would *also* beep on every auto-accepted edit, which in a
high-throughput session is a lot of noise for no signal. The design choice
here is "never false-positive" over "best coverage." If your workflow
manually approves every edit (auto-accept off), the trade-off may flip — add
this to `~/.cursor/hooks.json` and you'll get edit-gate beeps too:

```json
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "command": "./hooks/attention-beep.sh stop",
        "matcher": "^(Write|StrReplace|Edit|EditNotebook)$",
        "timeout": 5
      }
    ],
    "beforeMCPExecution": [
      { "command": "./hooks/attention-beep.sh stop", "timeout": 5 }
    ]
  }
}
```

(`stop` is reused as the mode arg because all those events should just always
beep — no per-event filter needed.)

If Cursor adds a real `notification` / `permissionRequest` event, this hook
should switch to it and the trade-off disappears.

## Roadmap (no promises)

- Linux / Windows audio backends (`paplay`, `ffplay`, PowerShell `MediaPlayer`).
- Optional distinct sound per event (turn-end vs network shell).
- A second hook on `beforeMCPExecution` for MCP-call attention.
- An optional `terminal-notifier` integration for a banner alongside the sound.

If you want any of these, open an issue.

## License

MIT. See [LICENSE](LICENSE).
