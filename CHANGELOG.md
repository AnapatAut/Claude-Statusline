# Changelog

All notable changes to the custom Claude Code statusline.

## Unreleased

Re-verified against the Claude Code 2.1.310 bundle and cross-checked line by
line against a reference port of its trigger on every local transcript.
Tested in throwaway containers on Ubuntu 24.04 / 22.04, Debian 12, Alpine
(busybox tools) and bash 3.2, with jq 1.6, 1.7 and 1.8.

### Fixed
- **Context count ran low by the last response's later blocks.** One API
  response spans several transcript lines (thinking, text, tool_use). The
  trigger anchors at the first of them and estimates the rest, but the tail
  scan stopped at the last one, so large `tool_use` inputs (file writes,
  long commands) went uncounted and compaction again seemed early.
- **Synthetic and zero-usage assistant lines ended the scan.** API-error
  stubs (`<synthetic>` model), interrupt and rejection stubs, unmetered
  lines and the zero-usage messages kept after a compaction are skipped by
  the trigger; the scan now skips them as anchors too and still estimates
  their content.
- **Per-model windows were ignored.** `/autocompact` now saves to
  `modelSettings.<model>.autoCompactWindow`, which overrides the top-level
  value; settings files are resolved in Claude Code's order (user, project,
  local, managed), a top-level value resets lower per-model entries, and
  `"auto"` means the model window. An object or out-of-range value used to
  be read as a garbage number.
- **`CLAUDE_CODE_AUTO_COMPACT_WINDOW=500k` read as 100k.** The env value is
  now parsed like Claude Code does (`k` / `M` suffixes, decimals).
- **Project settings were read from the current subdirectory** instead of
  the project root (`.workspace.project_dir`).
- **Huge token counts could read as tiny ones** (`1e20` stringified as
  `1e+20` and was read back as 120). Out-of-range numbers now hide the badge.
- A response in memory but not yet written to the transcript no longer
  drops the badge to the pending estimate for one repaint.
- `DISABLE_COMPACT` / `DISABLE_AUTO_COMPACT` now count as set only for
  `1`/`true`/`yes`/`on`, as in Claude Code (any other non-empty value used to
  disable the budget display).
- **Symlinked settings files were ignored.** A `settings.json` managed by a
  dotfiles tool (GNU stow, chezmoi, Nix home-manager) is a symlink, and the
  badge skipped it, so `/autocompact` windows and `autoCompactEnabled: false`
  in it had no effect on the budget shown. Symlinks are now followed, as
  Claude Code does; a file over 2 MiB is skipped, also as Claude Code does.
  Two sources that resolve to the same file are each applied again, which
  only matters when another file sits between them in precedence.
- **Install and uninstall replaced a symlinked `settings.json` with a plain
  file**, cutting it loose from the dotfiles it pointed to. They now edit the
  file the link points to, so the link survives. When that file is read-only
  (Nix home-manager), they stop before changing anything and print what to
  set in the settings source; install still updates the script if the
  read-only file already has the statusline set up. A failed edit no longer
  leaves a temp file behind.
- **A FIFO, device or huge file could hang the statusline or exhaust memory.**
  The plugin check, the global config and the credentials lookup handed
  `settings.json`, `.claude.json` and `.credentials.json` straight to `jq`,
  which blocks on a FIFO and reads `/dev/zero` or a huge sparse file without
  end. Every config read now takes regular files only, size-capped with a
  bounded read.
- **The global config was read from `~` even with `CLAUDE_CONFIG_DIR` set.**
  It is now `$CLAUDE_CONFIG_DIR/.claude.json` in that case, and a non-empty
  legacy `.config.json` in the config dir takes precedence, as in Claude Code.
- **Caveman badge disappeared with caveman 4.** Caveman 4.0.1 writes the
  modes `caveman`, `ultracave` and `megacave`, which the whitelist did not
  know, and keeps the mode per session in
  `.caveman-sessions/<session_id>.mode`. The badge now reads the session file
  first (falling back to `.caveman-active`), maps the new and legacy names
  the way caveman's own statusline does, and hides on `off`.

### Removed
- **Caveman savings number** (`[ ⛏ 28.8M ]`). Caveman 4 dropped its savings
  estimate (an unverified fixed ratio), reports savings as unknown and writes
  no savings fields to its history. The badge now shows the mode only:
  `[ ⛏ ]`, `[ ⛏ ULTRACAVE ]`, `[ ⛏ MEGACAVE ]`, `[ ⛏ COMMIT ]`.
- **Stop-hook refresh chain** and `caveman-stats-refresh.sh`. `install.sh`
  now removes the `Stop` hook entry and script an older install added (only
  that entry; other hooks and caveman's own files are left alone); the
  tarball ships three scripts. Left in place, that hook keeps running the
  stale pre-4 `hooks/caveman-stats.js` after every turn, which appends
  old-format rows to caveman's history that caveman 4 then reads as the
  session's latest totals.

### Added
- Tokens the server cleared by context editing (`clear_tool_uses`) are added
  back, as the trigger does; `usage.iterations` is honored; text documents
  with a `.json` title count at 2 chars per token.
- `autoCompactEnabled` falls back to the global config (`~/.claude.json`,
  see Fixed for where it lives with `CLAUDE_CONFIG_DIR`); managed settings (`/etc/claude-code/managed-settings.json`, macOS
  equivalent) are read.

## v1.2.0 — 2026-09-03 — Context badge as percent of compact budget

### Changed
- **Context badge format** is now `[ Ctx 12% / 467k ]`: share of the
  auto-compact budget in use, then the budget. The percentage is floored and
  clamped at 100%, so it hits 100% exactly when compaction fires and never
  earlier (`99%` = within ~4.7k tokens). Used-token count dropped from the
  badge (`/context` still has it). Disabled auto-compact reads
  `[ Ctx 5% / 1M ∅ compact ]`.

### Fixed
- **Pending-token scan overcounted right after a compaction**: the tool
  result that triggered compaction sits just before the `compact_boundary`
  line, and the tail scan walked past the boundary into it. The scan now
  stops at a boundary as well as at the last API response.
- **Badge vanished until the next API response** on a fresh session and
  right after a compaction (no `current_usage` yet). It now shows the pending
  estimate alone (prompt, attachments, compaction summary), which is exactly
  what the trigger counts at that moment.
- `queued_command` attachments (their text lives in `.prompt`) are now
  counted; `tac` falls back to `tail -r` on BSD/macOS.

## v1.1.1 — 2026-09-03 — Context badge counts what the trigger counts

### Fixed
- **Compaction appeared to fire ~2k early** (badge read 465k against a 467k
  threshold). Claude Code's trigger compares more than the last API usage:
  it adds the last response's output tokens plus a chars-per-token estimate
  of every message appended since (tool results, hook and system-reminder
  attachments). The badge now does the same — output tokens from
  `.context_window.current_usage`, pending messages from the tail of
  `.transcript_path` using the trigger's own rule (3 chars/token, 4 for
  pre-4.7 models, images 2000) — so it reaches the threshold exactly when
  compaction fires. Only the transcript tail is read (`tac` + early-exit
  `awk`); a missing, symlinked or malformed transcript just skips the
  estimate.

## v1.1.0 — 2026-09-02 — Context badge

### Added
- **Context badge** `[ Ctx 58k/467k ]` between the model and limits badges:
  tokens now in context (from `.context_window.current_usage`, the figure
  `/context` reports) over the token count where auto-compact fires. Plain
  dim text, deliberately untinted — context is informational, not a limit.
  The threshold follows Claude Code's own `/context` auto-compact formula
  (`min(window, autoCompactWindow) − min(max output, 20k) − 13k`), resolving
  `autoCompactWindow` from env `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, then
  project-local / project / user `settings.json`, then the model window, so
  it adapts on model switch. With auto-compact disabled the denominator is
  the full window and the badge is marked `∅ compact`. Hidden until the
  first API response (no `current_usage` yet).

### Notes
- Malformed input degrades quietly: non-integer or oversized token counts,
  missing `context_window`, malformed or symlinked settings files, and env
  flags set to `0`/`false` all hide the badge or fall through to the next
  scope rather than erroring.
- A session-only `/autocompact <n>` override is not exposed in the statusline
  JSON, so the badge keeps using the persisted window until it is written to
  settings.

## v1.0.0 — 2026-08-10 — Badges respect plugin disable

### Fixed
- **Caveman/ponytail badge lingered after its plugin was disabled.** The
  badges read persistent mode-flag files (`~/.claude/.caveman-active`,
  `~/.claude/.ponytail-active`) that each plugin's SessionStart hook writes.
  Disabling a plugin stops its hooks but deletes nothing, so the stale flag
  kept the badge on screen indefinitely. Both badges now also require the
  plugin to be enabled in `settings.json` `enabledPlugins` (`_plugin_on`);
  absent key counts as enabled, `false` hides the badge.

### Notes
- User-scope `settings.json` only; per-project plugin enable/disable is not
  consulted (marked with a `ponytail:` comment in the script).

### Changed
- **Tarball moved out of the repo and into GitHub release assets.** It now
  contains only the four functional scripts (`statusline.sh`, `install.sh`,
  `uninstall.sh`, `caveman-stats-refresh.sh`) — no README/CHANGELOG. Built
  reproducibly by the new `make-tarball.sh`; the local artifact is
  gitignored.

## 2026-07-14 — Ponytail badge

### Added
- **Ponytail badge** `[ 🎀 MODE ]`, shown only while the ponytail plugin is
  active. Mode is read from `~/.claude/.ponytail-active` with the same
  hardening as the caveman badge (symlink refusal, 32-byte cap, mode
  whitelist: `lite`/`full`/`ultra`/`review`). `full` renders the bare icon;
  other modes append an uppercase label. No token number: ponytail has no
  per-session stats machinery (`/ponytail-gain` reports fixed benchmark
  medians), so unlike caveman there is nothing live to display, and no
  refresh chain is needed — the badge updates on the normal 5s repaint.
- Icon is the 🎀 ribbon emoji (fixed pink; the ANSI tint colors only the
  mode label). ✂ and a U+FE0E monochrome-ribbon variant were tried along
  the way; the plain ribbon won.

## 2026-06-23 — Usage-limits parse fix

### Fixed
- **Weekly percent could display a Unix epoch (e.g. `Weekly 1782547200%`).**
  The limits store is a separator-joined record of
  `5h-util / 5h-reset / weekly-util / weekly-reset`. When the OAuth usage
  endpoint reported the 5-hour window as idle (`utilization: 0`,
  `resets_at: null`), the 5h-reset field came back empty. The fields were
  joined with a **tab** and split with `IFS=$'\t' read`; because tab is an
  IFS *whitespace* character, `read` collapses runs of tabs and drops empty
  fields. The empty 5h-reset field made two tabs adjacent, the pair
  collapsed, and every field shifted one slot left — so the weekly
  `resets_at` epoch landed in the weekly-percent slot and rendered as
  `<epoch>%`. The same shift fed the weekly percent into the 5h-reset slot,
  which (read as a 1970-era epoch) computed as "expired" and suppressed the
  `Session ↻` countdown.
- **Field separator changed from tab to unit separator (`0x1f`)** — a
  non-whitespace delimiter, so `read` preserves empty fields and never
  collapses them. Any field can now be empty (a reset time, or even a
  percent) without poisoning its neighbours. Applies to both the OAuth-fetch
  path and the harness `rate_limits` fallback; the store-reuse filter keeps
  `0x1f` instead of tab.

### Changed
- **`install.sh` now clears the old limits store on update.** A pre-existing
  tab-separated `~/.claude/.statusline-limits-fetch` (and its `.lock`) is
  removed so the upgraded `0x1f` parser refetches cleanly instead of
  misreading the old format once before the next 30s fetch overwrites it.

### Notes
- Field separator is now `0x1f` by design — **do not revert to `@tsv`/tab**;
  empty reset fields are normal (idle windows) and tab-IFS would re-introduce
  the field-shift bug.
- Behaviour reminder: `Session ↻` is shown only when the API returns a
  `five_hour.resets_at` (active window, util > 0). At a genuine 0% / idle 5h
  window the API returns no reset time, so the countdown is correctly omitted
  — that is not a regression.

## 2026-06-11 — Initial release
- Two-line statusline: badges (model/effort, Session/Weekly usage limits,
  caveman pick) on top; `user@host:dir` below in teal/steel-blue.
- Shared limits store refreshed from the OAuth usage endpoint on wall-clock
  30s boundaries with a single-flight `mkdir` lock; harness `rate_limits` as
  fallback.
- Tier colours: <50 green / 50–74 blue / 75–89 yellow / ≥90 red.
- `install.sh` / `uninstall.sh`; optional caveman tokens-saved badge wired via
  a Stop hook when the caveman plugin is present.
