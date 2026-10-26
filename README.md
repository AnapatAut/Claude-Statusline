# Claude Code custom statusline

Two lines — badges on top, location below:

```
 [ Fable 5 xhigh ] [ Ctx 12% / 467k ] [ Session 4% ↻ 4h3m · Weekly 27% ↻ 1d22h ] [ ⛏ ULTRACAVE ] [ 🎀 ULTRA ]
user@host:~/some/long/project/dir
```

- **model + effort** — from statusline JSON (`.model.display_name`, `.effort.level`)
- **Ctx** — share of the auto-compact budget in use, then the budget itself
  (the token count where auto-compact fires). The percentage is floored and
  clamped, so `100%` shows exactly when compaction fires and never before
  (`99%` means within 1%, about 4.7k tokens, of it). Plain dim text, no tier
  colors: context is informational, not a limit. Checked against the
  Claude Code 2.1.310 bundle.
  - **Count** — what Claude Code's compaction trigger compares, not just the
    last API usage. The anchor is the last real API response in the
    transcript (synthetic, interrupt-stub, unmetered and zero-usage lines are
    skipped; a `compact_boundary` ends the walk). A response spans several
    transcript lines (thinking, text, tool_use) and the anchor is the first of
    them. Count = anchor usage (input + cache-create + cache-read + output,
    from `usage.iterations` when present) + an estimate of every line after
    the anchor, at the trigger's own rule (3 chars per token, 4 for pre-4.7
    models; images 2000; JSON text documents 2) + tokens the server cleared
    by context editing, which the trigger adds back. The transcript is walked
    backwards with `tac` and the walk stops at the anchor, so large
    transcripts stay cheap.
  - **Budget** — mirrors the `/context` auto-compact threshold:
    `min(model window, autoCompactWindow) − min(max output tokens, 20k) − 13k`
    summary buffer. `autoCompactWindow` resolves like Claude Code does: env
    `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (`200k`, `1M` or `500000`, clamped
    100k–1M) first, then settings files from lowest to highest precedence
    (user, project, local, managed). A file that sets the top-level value
    resets the per-model ones from lower files, and
    `modelSettings.<model>.autoCompactWindow` (where `/autocompact` saves)
    overrides the top-level value for this model. `"auto"` or unset means the
    model window. Project files are read from the project root, not the
    current subdirectory. Settings files are read as Claude Code reads them:
    symlinks followed (dotfile managers, Nix home-manager), files over 2 MiB
    skipped. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and
    `CLAUDE_CODE_MAX_OUTPUT_TOKENS` are honored. It adapts on model switch.
  - **Off** — with auto-compact disabled (`autoCompactEnabled: false` in
    settings or the global config `~/.claude.json` (in `$CLAUDE_CONFIG_DIR`
    when that is set), `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`)
    the denominator is the full window and the badge is marked `∅ compact`.
  - **Edges** — before the first API response (fresh session, or right after
    a compaction) the count is the pending estimate alone, as the trigger
    sees it. A response that is in memory but not yet in the transcript
    shows its usage alone until the next repaint.
  - **Not visible to the statusline** — a server-tuned window behind
    `"auto"`, `--settings` flag files, and model aliases (such as `opus`) used
    as `modelSettings` keys. Attachments are estimated from their raw text,
    without the wrapper Claude Code adds.
  - **vs `/context`** — `/context` reports a lower token count: the last
    usage without output tokens or pending lines, and its percentage is of
    the full window, not the compact budget.
- **Session / Weekly limits** — color tiers (<50 green, 50–74 blue, 75–89 yellow, ≥90 red), compact reset countdown (`2d7h` → `3h53m` → `29m` as reset nears).
  All sessions read one shared store refreshed from the OAuth usage endpoint on
  wall-clock 30s boundaries (xx:00/xx:30), so every session shows identical values
  and they update in lockstep. Single-flight lock: exactly one GET per boundary no
  matter how many sessions are open; min 5s between fetches. First session after
  idle fetches on open (instant limits). Expired windows display 0% instead of
  stale pre-reset numbers. Statusline repaints every 5s; a render costs about
  0.15s of CPU, so roughly 3% of one core per open session.
- **caveman badge** — only if the [caveman](https://github.com/JuliusBrussee/caveman) plugin is active; silently absent otherwise.
  Both mode badges double-check `enabledPlugins` in `~/.claude/settings.json`:
  disabling a plugin stops its hooks but leaves the old mode-flag file behind,
  and without that check the flag alone would keep a dead badge on screen.
  (User scope only — per-project plugin enable/disable is not consulted.)
  Mode only, for caveman 4: `caveman` (and legacy `lite`/`full`) shows the
  bare ⛏; `ultracave` (legacy `ultra`) shows `ULTRACAVE`; `megacave` (legacy
  `wenyan*`) shows `MEGACAVE`; `commit`/`review`/`compress` show their name;
  `off` hides the badge. The mode is read from this session's
  `~/.claude/.caveman-sessions/<session_id>.mode`, else the machine-wide
  `~/.claude/.caveman-active`, with caveman's own hardening (session id
  checked before it becomes a path, symlinks refused, 64-byte cap, whitelist).
  No savings number: caveman 4 dropped its estimate (a fixed ratio, not a
  measurement) and reports savings as unknown, so older versions' Stop-hook
  refresh chain is gone too; `./install.sh` removes it if an older install
  added it.
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
`install.sh`, `uninstall.sh` — no docs. The
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
`~/.claude/settings.json` without touching other settings. Upgrading from a
version before v1.3.0, it also removes the caveman stats `Stop` hook entry and
`hooks/caveman-stats-refresh.sh` that version added; other hooks and caveman's
own files stay. If `settings.json` is a symlink (GNU stow, chezmoi), the file
it points to is edited and the link kept; if that file is read-only (Nix
home-manager), install stops and prints the `statusLine` entry to add there.

Requires `jq` (1.6 or newer; 1.5 lacks `round` and `IN`, so the badge skips
the transcript estimate and the env window) and `curl`. Machine must be logged into Claude Code
(`~/.claude/.credentials.json`) for the pre-first-message live limit fetch;
without it the limits segment simply appears after the first message.

If a different `statusline.sh` already exists, install backs it up
(`statusline.sh.pre-install.<timestamp>`) before overwriting.

## Uninstall

```sh
./uninstall.sh
```

Removes only what install added: the script, the `statusLine` key in
`settings.json`, the runtime store file, and the caveman stats `Stop` hook
entry a version before v1.3.0 may have added. Everything else — other
settings keys, other hooks, permissions, credentials, caveman plugin files —
is untouched, and a timestamped `settings.json` backup is written before the
key is removed. A symlinked `settings.json` is edited through the link, as in
install; a read-only one stops the uninstall until the key is removed at its
source, then a rerun finishes.

It refuses (with a message) to delete a `statusline.sh` that differs from the
bundled copy or a `statusLine` setting pointing at some other command;
`./uninstall.sh --force` overrides both checks.
