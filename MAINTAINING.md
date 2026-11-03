# Maintaining

Notes for keeping the statusline accurate as Claude Code and the plugins it
reads change. Last full check: Claude Code 2.1.317, caveman 4.0.1
(2026-11-03).

## After a Claude Code update

The context badge copies Claude Code's own compaction trigger, so an update
can move it. Re-check when any of these happen:

- compaction fires while the badge is clearly below 100%, or the badge sits
  at 100% and nothing compacts;
- `/context` shows a different auto-compact buffer or window than the badge;
- the badge disappears (statusline JSON shape changed).

### Where to look

The CLI is a single binary (`~/.local/share/claude/versions/<version>`).
`strings -n 20` on it gives the bundled JavaScript. Minified function names
change every release, so search for stable strings and read the code around
them:

| What | Search for |
|---|---|
| Statusline JSON (`context_window`) | `context_window_size:` |
| Trigger: count compared to the threshold | `autocompact: tokens=` |
| Cleared tokens, `usage.iterations` | `clear_tool_uses_20250919` |
| Anchor walk, `compact_boundary` stop | the function next to the cleared-tokens code that returns `anchorIndex` |
| Per-block estimate (images 2000, JSON docs 2) | `"jsonl"` near `tool_result` / `redacted_thinking` |
| 4-chars-per-token models | `"claude-sonnet-4-6"` in a `new Set([` |
| Threshold (13000 buffer, 20000 output cap) | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `-13000` |
| Window resolution order | `CLAUDE_CODE_AUTO_COMPACT_WINDOW` near `source:"settings"` |
| Settings merge (`modelSettings`) | `autoCompactWindow` near `byModel` |

Some names repeat across bundle chunks; use the definition closest to the
code you came from.

### What to compare

Each of these is described in the header comment of the context block in
`statusline.sh`; check that the bundle still does the same:

1. Trigger = anchor tokens + estimate of lines after the anchor + cleared
   tokens.
2. Anchor: last assistant line with real, non-zero usage (skips
   `<synthetic>`, interrupt/rejection stubs, unmetered); a
   `compact_boundary` gives 0; rewinds to the first line of the same
   `message.id`.
3. Anchor tokens: input + cache creation + cache read + output, from the
   last valid `usage.iterations` entry when present.
4. Estimator: chars / 3 (4 for the older-model set), images and documents
   2000, JSON text documents 2, `tool_use` as name + JSON input.
5. Cleared tokens: sum of `clear_tool_uses_20250919` edits, capped at
   `client_estimated_cleared_input_tokens`.
6. Threshold: `min(window, autoCompactWindow) - min(max output, 20000) -
   13000`; percent override as `min(floor(window * pct / 100), window -
   13000)`.
7. Window: env, then settings (user < project < local < managed; a
   top-level value resets lower per-model entries), then the model default.

### Testing a change

- Write a reference port of the trigger (the version under test, read
  straight from the bundle) and compare its anchor / pending / cleared
  numbers with the statusline's transcript scan on every local transcript.
  A transcript that a live session is writing can differ between the two
  runs; re-check it on a copy.
- Small JSONL fixtures for each rule (cap, negative values, zero-usage
  iterations, boundary, sidechain lines) catch regressions the real
  transcripts never hit.
- Feed the statusline crafted stdin JSON with a throwaway
  `CLAUDE_CONFIG_DIR` and `HOME`, so real settings never leak into the
  result.

## Plugin badges

- **caveman** — mode per session in
  `~/.claude/.caveman-sessions/<session_id>.mode`, else
  `~/.claude/.caveman-active`. If the badge disappears after a caveman
  update, compare the mode names with caveman's own statusline script
  (`src/hooks/caveman-statusline.sh` in the plugin) and `VALID_MODES` in
  `src/hooks/caveman-config.js`.
- **ponytail** — mode in `~/.claude/.ponytail-active`.
- Both badges also require the plugin to be enabled in `enabledPlugins`.

## Usage limits

- Source: `GET https://api.anthropic.com/api/oauth/usage` with the OAuth
  token, at most once per 30 s across all sessions. If it can't be reached,
  the badge uses the `rate_limits` Claude Code sends to the statusline.
- A window the account doesn't report (`null`) is hidden: some accounts
  have only a weekly limit, some both, API-key setups none.
- Polling the endpoint by hand while sessions are open quickly returns
  HTTP 429; the badge then keeps its last stored numbers.

## Releasing

1. Rename the CHANGELOG `Unreleased` heading to `vX.Y.Z — YYYY-MM-DD — <title>`.
2. Commit, then `git tag -a vX.Y.Z -m "..."` and push `main` and the tag.
3. `./make-tarball.sh`, then check it:
   - `tar tvzf claude-statusline.tar.gz` shows owner `0/0`, and the scripts
     have the execute bit;
   - no local user, host or path in the files or the archive.
4. `gh release create vX.Y.Z claude-statusline.tar.gz --title "..." --notes-file <that CHANGELOG section>`.
5. Download the asset again, extract it, and run `./install.sh` against a
   throwaway `CLAUDE_CONFIG_DIR`.
6. Delete the local tarball (it is gitignored, not committed).
