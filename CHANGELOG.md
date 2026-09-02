# Changelog

All notable changes to the custom Claude Code statusline.

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
