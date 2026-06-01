# cursor-attention-beep

A small, observe-only Cursor hook that plays a macOS system sound whenever the
agent might need your attention: end of a turn, a likely-gated shell command
(`curl`, `ssh`, `sudo`, package managers, anything with an `http(s)://` URL),
or an MCP tool call. Edit-gate coverage is available as a one-snippet opt-in
because it tends to fire on every auto-accepted edit too.

It is intentionally small (one shell script, one JSON file) and **never prints
a permission decision**, so Cursor's normal approval prompts are unchanged. The
hook only listens; you still drive the approvals.

Status: alpha. macOS-first. Tested with Cursor's hook system on macOS.

## Why this exists

Cursor has [hooks](https://cursor.com/docs/agent/hooks) but no first-class
"agent is waiting for input" event. Claude Code has a `Notification` event
with a `permission_prompt` matcher and a thriving ecosystem of
sound-notification tools; Cursor does not. This repo fills the obvious gap
with the smallest useful thing.

How it differs from neighbors:

| Tool | IDE focus | Cursor support | Style |
| --- | --- | --- | --- |
| [`PeonPing/peon-ping`](https://github.com/PeonPing/peon-ping) | Claude Code primary, Cursor adapter | yes (adapter) | voice packs, themes, multi-platform, larger surface |
| [`NazarenoL/cursor-but-fun`](https://github.com/NazarenoL/cursor-but-fun) | Cursor | yes | switches apps to a game while you wait |
| [`beautyfree/cursor-activate-hook`](https://github.com/beautyfree/cursor-window-activate-hook) | Cursor | yes | window focus, not sound |
| [`fsalmons/claude-chime`](https://github.com/fsalmons/claude-chime), [`EryouHao/claude-code-sound-notification`](https://github.com/EryouHao/claude-code-sound-notification), [`ChanMeng666/claude-code-audio-hooks`](https://github.com/ChanMeng666/claude-code-audio-hooks) | Claude Code | no | mature, Claude-only |
| **cursor-attention-beep** | Cursor only | n/a | minimal, single sound, observe-only; turn-end + network-shell + MCP by default, edit-gates opt-in |

If you want voice packs / multi-IDE support / dashboards, use PeonPing. If you
want one short script that pings when it probably matters and stays out of
the way otherwise, use this.

## Coverage

Cursor has no "approval prompt shown" event, so this hook listens on the
events that come closest. The defaults are tuned to "high signal, low
chatter" -- everything that ships on by default beeps either once per turn
or once per gated/sensitive call. Edit-gate coverage is an opt-in (see
below) because in practice it fires on every auto-accepted edit too.

| Event | Mode | When it beeps | Default |
| --- | --- | --- | --- |
| `stop` | `stop` | Agent finishes a turn (including when it ends because it can't proceed without your input) | on |
| `beforeShellExecution` | `shell` | About to run a shell command whose `.command` matches the network/elevated regex (`curl`, `wget`, `ssh`, `scp`, `sftp`, `rsync`, `nc`, `ncat`, `telnet`, `sudo`, `git`, `npm`, `pnpm`, `yarn`, `pip`, `pip3`, `uv`, `brew`, `apt`, `apt-get`, `docker`, `dig`, `ping`, `nslookup`, `host`, or any `http(s)://` URL) | on |
| `beforeMCPExecution` | `mcp` | About to call an MCP tool | on |
| `preToolUse` | `edit` | About to use `Write` / `Edit` / `MultiEdit` / `StrReplace` / `EditNotebook` | **opt-in** -- see below |

The hook writes nothing to stdout, so it returns no `permission` field. Cursor
falls back to its native approval flow for every event, every time.

### Opt-in: edit-gate coverage

Cursor's `preToolUse` event fires before *every* matched tool invocation,
whether or not Cursor pauses for your approval. If your workspace has
auto-accept on for in-workspace edits (Cursor's common default), enabling
edit coverage means the hook beeps on **every** auto-accepted edit the agent
makes. That's a lot of noise for sessions where the agent is editing
heavily.

It's still useful in two cases:

- Your workspace requires manual approval for *all* edits (auto-accept off
  globally). Then almost every `preToolUse` is a real "accept changes"
  prompt and the beep is high signal.
- You routinely watch agents touch paths outside the workspace (e.g.
  `~/.cursor/`, dotfiles, sibling repos) where approval is always required.

To enable, add this entry to `~/.cursor/hooks.json` under `hooks`:

```json
"preToolUse": [
  {
    "command": "./hooks/attention-beep.sh edit",
    "matcher": "^(Write|Edit|MultiEdit|StrReplace|EditNotebook)$",
    "timeout": 5
  }
]
```

If you change your mind later, remove the entry or set
`ATTENTION_BEEP_DISABLE_EDIT=1` in your shell profile.

The `edit` mode is preserved in `hooks/attention-beep.sh` exactly so this
opt-in works -- no script changes required.

## Install

Requirements: macOS, `jq`, `afplay` (built in). All present on every modern
Mac except `jq` (`brew install jq`).

```bash
git clone https://github.com/aRealGem/cursor-attention-beep.git
cd cursor-attention-beep
./install.sh
```

The installer:

1. Copies `hooks/attention-beep.sh` -> `~/.cursor/hooks/attention-beep.sh` (`chmod +x`).
2. If `~/.cursor/hooks.json` already exists, backs it up to
   `hooks.json.<UTC>.bak` and **merges** the four entries in (idempotent;
   re-running won't duplicate them; other hooks in your file are preserved).
3. If it doesn't exist, copies the template.

Dry-run first if you want: `./install.sh --dry-run`.

Verify in Cursor: **Settings -> Hooks** should list three entries (`stop`,
`beforeShellExecution`, `beforeMCPExecution`). End a turn -> Sosumi.

## Customize

All knobs are environment variables; set them in your shell profile (e.g.
`~/.zshrc`).

| Variable | Default | Effect |
| --- | --- | --- |
| `ATTENTION_BEEP_DISABLE` | unset | Master kill switch (`=1` -> no-op every event) |
| `ATTENTION_BEEP_DISABLE_STOP` | unset | Silence turn-end beeps |
| `ATTENTION_BEEP_DISABLE_SHELL` | unset | Silence network/elevated-shell beeps |
| `ATTENTION_BEEP_DISABLE_EDIT` | unset | Silence file-edit beeps |
| `ATTENTION_BEEP_DISABLE_MCP` | unset | Silence MCP-call beeps |
| `ATTENTION_BEEP_SOUND` | `/System/Library/Sounds/Sosumi.aiff` | Any `.aiff` / `.wav` / `.mp3` path that `afplay` accepts |
| `ATTENTION_BEEP_PATTERN` | see source | Override the shell-match extended regex entirely |

Available system sounds: `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`,
`Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`.

## Manual testing

```bash
echo '{"command":"curl https://example.com"}' | ~/.cursor/hooks/attention-beep.sh shell  # beep
echo '{"command":"ls -la"}'                   | ~/.cursor/hooks/attention-beep.sh shell  # silent
~/.cursor/hooks/attention-beep.sh stop </dev/null                                         # beep
~/.cursor/hooks/attention-beep.sh mcp  </dev/null                                         # beep
~/.cursor/hooks/attention-beep.sh edit </dev/null                                         # beep (mode kept for opt-in users)
```

## Uninstall

```bash
./install.sh --uninstall
```

Removes the script and strips every attention-beep entry from
`~/.cursor/hooks.json` (backed up with a UTC timestamp). Other hooks in that
file are preserved.

## Roadmap (no promises)

- Linux / Windows audio backends (`paplay`, `ffplay`, PowerShell `MediaPlayer`).
- Optional distinct sound per event (`SOUND_STOP`, `SOUND_SHELL`, `SOUND_EDIT`, `SOUND_MCP`).
- An optional `terminal-notifier` integration for a banner alongside the sound.
- If/when Cursor ships a real `notification` / `permissionRequest` event,
  switch to it and retire the broader event matchers.

If you want any of these, open an issue.

## License

MIT. See [LICENSE](LICENSE).
