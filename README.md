# Claude Code custom statusline

Two lines — badges on top, location below:

```
 [ Fable 5 xhigh ] [ Ctx 58k/467k ] [ Session 4% ↻ 4h3m · Weekly 27% ↻ 1d22h ] [ ⛏ 28.8M ] [ 🎀 ULTRA ]
user@host:~/some/long/project/dir
```

- **model + effort** — from statusline JSON (`.model.display_name`, `.effort.level`)
- **Ctx** — tokens currently in context / the token count where auto-compact
  fires. Plain dim text, no tier colors: context is informational, not a limit.
  The used figure is what Claude Code's compaction trigger actually compares,
  not just the last API usage: last response tokens (input + cache-create +
  cache-read + output, from `.context_window.current_usage`) plus an estimate
  of everything appended to the transcript since (tool results, hook and
  system-reminder attachments) at the trigger's own chars-per-token rule
  (3, or 4 for pre-4.7 models; images 2000). Only the transcript tail is read
  (`tac` + early exit), so large transcripts stay cheap. The denominator
  mirrors Claude Code's own `/context` auto-compact threshold:
  `min(model window, autoCompactWindow) − min(max output tokens, 20k) − 13k`
  summary buffer, where `autoCompactWindow` resolves env
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (100k–1M) > `settings.json` (project local >
  project > user) > model window, so it adapts on model switch;
  `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_MAX_OUTPUT_TOKENS` are
  honored. A session-only `/autocompact` override is not visible to the
  statusline, so the badge follows the persisted value. With auto-compact off
  (`autoCompactEnabled: false`, `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`) the
  denominator is the full window and the badge is marked `∅ compact`. Absent
  until the first API response. `/context` shows a smaller used figure: it
  reports the last usage without output tokens or pending tool results.
- **Session / Weekly limits** — color tiers (<50 green, 50–74 blue, 75–89 yellow, ≥90 red), compact reset countdown (`2d7h` → `3h53m` → `29m` as reset nears).
  All sessions read one shared store refreshed from the OAuth usage endpoint on
  wall-clock 30s boundaries (xx:00/xx:30), so every session shows identical values
  and they update in lockstep. Single-flight lock: exactly one GET per boundary no
  matter how many sessions are open; min 5s between fetches. First session after
  idle fetches on open (instant limits). Expired windows display 0% instead of
  stale pre-reset numbers. Statusline repaints every 5s (~0.5% of one core).
- **caveman badge** — only if the [caveman](https://github.com/JuliusBrussee/caveman) plugin is active; silently absent otherwise.
  Both mode badges double-check `enabledPlugins` in `~/.claude/settings.json`:
  disabling a plugin stops its hooks but leaves the old mode-flag file behind,
  and without that check the flag alone would keep a dead badge on screen.
  (User scope only — per-project plugin enable/disable is not consulted.)
  The ⛏ tokens-saved number comes from `~/.claude/.caveman-history.jsonl`, kept
  fresh by a chain install.sh wires automatically when caveman is present:
  settings.json `Stop` hook → `hooks/caveman-stats-refresh.sh` (bundled) →
  `node hooks/caveman-stats.js --session-file <transcript>` → history file →
  badge. Without that chain the badge shows the icon/mode only and the number
  updates only when `/caveman-stats` is run manually. If you install caveman
  *after* the statusline, rerun `./install.sh` to wire it (merge is idempotent).
- **ponytail badge** — only if the [ponytail](https://github.com/DietrichGebert/ponytail) plugin is active; silently absent otherwise.
  Reads the mode from `~/.claude/.ponytail-active` (same symlink/whitelist
  hardening as the caveman badge). `full` shows the bare 🎀; `lite`/`ultra`/`review`
  add the label. 🎀 is a color emoji, so it renders in its own fixed pink;
  the ANSI tint colors only the mode label. No numbers: ponytail has no
  per-session stats
  machinery — `/ponytail-gain` reports fixed benchmark medians, not live
  savings — so no refresh chain either; the badge updates on the normal
  5s statusline repaint. Nothing to wire at install time: ponytail's own
  SessionStart hook writes the flag each new session. Gotcha: if ponytail
  was installed mid-session, bare `/ponytail` only *reports* and never
  writes the flag — run `/ponytail full` (any explicit level) once, or
  start a new session, and the badge appears. Same `enabledPlugins` gate
  as the caveman badge: disable the plugin and the badge goes with it,
  stale flag file or not.
- **user@host:dir** — own line, so long paths never crowd the badges. Teal/steel-blue
  instead of the classic green/blue PS1 palette, so it doesn't read as a real shell prompt.

## Sharing

Tarballs ship as GitHub release assets (`claude-statusline.tar.gz`), containing
only what's needed to run, install, and uninstall: `statusline.sh`,
`install.sh`, `uninstall.sh`, `caveman-stats-refresh.sh` — no docs. The
tarball is not committed to the repo (gitignored); grab it from the latest
release, or rebuild consistently with:

```sh
./make-tarball.sh
```

## Install

```sh
./install.sh
```

Copies `statusline.sh` to `~/.claude/` and merges the `statusLine` key into
`~/.claude/settings.json` without touching other settings.

Requires `jq` and `curl`. Machine must be logged into Claude Code
(`~/.claude/.credentials.json`) for the pre-first-message live limit fetch;
without it the limits segment simply appears after the first message.

If a different `statusline.sh` already exists, install backs it up
(`statusline.sh.pre-install.<timestamp>`) before overwriting.

## Uninstall

```sh
./uninstall.sh
```

Removes only what install added: the script, the `statusLine` key in
`settings.json`, and the runtime store file. Everything else — other settings
keys, hooks, permissions, credentials, caveman plugin files — is untouched, and
a timestamped `settings.json` backup is written before the key is removed.

It refuses (with a message) to delete a `statusline.sh` that differs from the
bundled copy or a `statusLine` setting pointing at some other command;
`./uninstall.sh --force` overrides both checks.
