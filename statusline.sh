#!/bin/bash
# Custom Claude Code statusline — two lines:
#   [ <model> <effort> ] [ Ctx <pct> / <threshold> ] [ Session <pct> ↻ <reset> · Weekly <pct> ↻ <reset> ] [ ⛏ <mode> ] [ 🎀 <mode> ]
#   <user>@<host>:<dir>
#
# Line 1 badges: model/effort, context usage vs the auto-compact threshold
# (plain, untinted), usage limits (tiers: <50 green, 50-74 blue, 75-89 yellow,
# >=90 red; clock-synced shared fetch, see below), caveman badge, ponytail badge.
# Line 2 prompt-style location in teal/steel-blue — deliberately NOT the classic
# green/blue PS1 palette so it never reads as a real shell prompt. Long paths
# get a whole line, so they can't push the badges off-screen.
#
# The caveman badge mirrors caveman's own hooks/caveman-statusline.sh logic
# (4.x: per-session mode files, caveman/ultracave/megacave modes) so its mode
# whitelist + symlink/escape hardening stay the source of truth.

input=$(cat)

# current dir from Claude's statusline JSON; fall back to workspace dir, then $PWD
cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# abbreviate $HOME -> ~
case "$cwd" in
  "$HOME")   dir="~" ;;
  "$HOME"/*) dir="~${cwd#"$HOME"}" ;;
  *)         dir="$cwd" ;;
esac

user=$(id -un 2>/dev/null)
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null)

# Line 1: badges (model/effort, context, limits, caveman, ponytail). Line 2:
# user@host:dir — printed at the end, so long paths never push the badges around.

# tiers: <50 green, 50-74 blue, 75-89 yellow, >=90 red
_cc() { if [ "${1:-0}" -ge 90 ]; then printf 167; elif [ "${1:-0}" -ge 75 ]; then printf 178; elif [ "${1:-0}" -ge 50 ]; then printf 117; else printf 114; fi; }

# Current model + effort level, e.g. "[ Fable 5 xhigh ]". Effort is absent when
# the model doesn't support the effort parameter, so it's appended conditionally.
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
if [ -n "$model" ]; then
  printf ' \033[1;38;5;252m[\033[0m \033[38;5;141m%s\033[0m' "$model"
  [ -n "$effort" ] && printf ' \033[38;5;245m%s\033[0m' "$effort"
  printf ' \033[1;38;5;252m]\033[0m'
fi

# Context usage: "[ Ctx 12% / 467k ]" — share of the auto-compact budget in
# use (integer, floored, clamped at 100% = compaction fires now) and the
# budget itself, plain dim text (no tier tint — informational).
# The count mirrors what Claude Code's own trigger compares (checked against
# the 2.1.310 bundle), not just the last API usage:
#   anchor = the last real API response in the transcript: skips synthetic
#            (<synthetic> model, interrupt/rejection stubs), unmetered and
#            all-zero-usage assistant lines; stops at a compact_boundary
#            (anchor tokens 0). A response spans several transcript lines
#            (thinking, text, tool_use), all sharing message.id; the anchor is
#            the FIRST of them, so the later blocks count as pending too.
#   tokens = anchor usage input + cache_create + cache_read + output (taken
#            from usage.iterations when present), via
#            .context_window.current_usage, which holds the same message
#   + estimate of every line after the anchor (tool results, attachments,
#     the response's later blocks) at the trigger's chars-per-token rule:
#     3 (4 for pre-4.7 models), images 2000, json text documents 2
#   + tokens the server cleared by context editing (clear_tool_uses), which
#     the trigger adds back
# No transcript, or a response not yet written to it: last usage alone. No
# anchor (fresh session, right after a compaction): pending alone, again
# matching the trigger.
# The threshold mirrors the /context autoCompactThreshold:
#   threshold = min(model window, autoCompactWindow) - min(max_output, 20000) - 13000
# autoCompactWindow resolves like Claude Code's: env CLAUDE_CODE_AUTO_COMPACT_WINDOW
# (200k / 1M / 500000 forms, clamped 100k..1M), else settings files low to
# high (user < project < local < managed): a file that sets the top-level
# value resets the per-model ones, modelSettings.<model>.autoCompactWindow
# (what /autocompact saves) overrides it for this model; "auto" or unset =
# the model window. A server-tuned "auto" window is not visible from here.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# A config file is read only if it is a regular file (symlinks followed) of at
# most $2 bytes, the way Claude Code reads settings. head bounds the check
# itself, so a FIFO, device or huge/sparse target can't hang or flood a render.
_cfg_ok() {
  [ -f "$1" ] || return 1
  local n; n=$(head -c "$(( $2 + 1 ))" "$1" 2>/dev/null | wc -c | tr -cd '0-9')
  [ -n "$n" ] && [ "$n" -le "$2" ]
}
read -r cx_base cx_win <<< "$(printf '%s' "$input" | jq -r '
  # plain integers only: 1e20 would stringify as "1e+20" and read back as 120
  def int: if type == "number" and (isinfinite | not) and . >= 0 and . < 1e12 then floor | tostring else null end;
  .context_window as $c
  | if ($c | type) != "object" then "" else
    [ (if ($c.current_usage | type) == "object" then
         (($c.current_usage.input_tokens // 0) + ($c.current_usage.cache_creation_input_tokens // 0)
          + ($c.current_usage.cache_read_input_tokens // 0) + ($c.current_usage.output_tokens // 0)) | int
       else "0" end),
      ($c.context_window_size | int) ]
    | if all(. != null) then join(" ") else "" end end' 2>/dev/null)"
# digits only past this point: any surprise (floats, "null", missing jq) hides the badge
cx_base=$(printf '%s' "$cx_base" | tr -cd '0-9'); cx_win=$(printf '%s' "$cx_win" | tr -cd '0-9')
if [ -n "$cx_base" ] && [ -n "$cx_win" ] && [ "${#cx_win}" -le 12 ] && [ "${#cx_base}" -le 12 ] && [ "$cx_win" -gt 0 ]; then
  # canonical model key, the way settings keys and the chars/token table match
  # it: lowercase, "claude-..." onward (drops Bedrock/Vertex prefixes), no
  # [1m] / @date / -v1:0 / -YYYYMMDD suffix, dots and underscores as dashes
  mkey=$(printf '%s' "$input" | jq -r '
    def norm: ascii_downcase | sub("\\[[^]]*\\]$"; "")
      | (if test("claude-") then "claude-" + (split("claude-")[1:] | join("claude-")) else . end)
      | sub("@.*$"; "") | sub("-v[0-9]+(:[0-9]+)?$"; "") | sub("-[0-9]{8}$"; "") | gsub("[._]"; "-");
    .model.id // empty | norm' 2>/dev/null)
  case "$mkey" in  # older models tokenize ~4 chars/token, everything newer 3
    claude-3-*|claude-opus-4-[0156]|claude-sonnet-4-[056]|claude-haiku-4-5) cpt=4 ;;
    *) cpt=3 ;;
  esac
  cx_used=$cx_base
  # Pending tokens: walk the transcript backwards (tac, so only the tail is
  # read; jq breaks out once the anchor's first line is behind it) and apply
  # the trigger's estimator. Output: anchor-found tokens pending cleared.
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ] && [ ! -L "$tp" ]; then
    scan=$({ tac "$tp" 2>/dev/null || tail -r "$tp" 2>/dev/null; } | jq -nr -R --argjson cpt "$cpt" '
      def kd($r): if type == "string" then (length / $r | round) else 0 end;
      def kd: kd($cpt);
      def ext: (. // "" | tostring | split(".") | last // "" | ascii_downcase)
        | if . == "json" or . == "jsonl" or . == "jsonc" then 2 else 4 end;
      def zy:
        def blk:
          if type == "string" then kd
          elif type != "object" then 0
          elif .type == "text" then (.text | kd)
          elif .type == "document" and (.source | type) == "object" and .source.type == "text" then
            ([$cpt, (.title | ext)] | min) as $r | (.source.data | kd($r))
          elif .type == "document" and (.source | type) == "object" and .source.type == "content" then
            (.source.content | if type == "array" then map(select(type == "object")) | zy else kd end)
          elif .type == "image" or .type == "document" then 2000
          elif .type == "tool_result" then (.content | zy)
          elif .type == "tool_use" then (((.name // "") | tostring) + ((.input // {}) | tojson) | kd)
          elif .type == "thinking" then (.thinking | kd)
          elif .type == "redacted_thinking" then (.data | kd)
          else (tojson | kd) end;
        if type == "string" then kd elif type == "array" then (map(blk) | add // 0) else 0 end;
      def est:
        if .type == "assistant" or .type == "user" or .type == "api_system" then (.message.content // null | zy)
        elif .type == "attachment" and .attachment then
          ((.attachment.text // .attachment.content // .attachment.prompt // null) | zy)
        else 0 end;
      def m7:  # usage as the trigger reads it: last real iteration when present
        { i: (.input_tokens // 0), o: (.output_tokens // 0),
          cc: (.cache_creation_input_tokens // 0), cr: (.cache_read_input_tokens // 0) } as $n
        | if ($n.i + $n.cc + $n.cr) == 0 or (.iterations | type) != "array" then $n
          else ([.iterations[] | select((type == "object" and (.type == "advisor_message" or .type == "compaction")) | not)] | last) as $s
            | if ($s | type) == "object" and ($s.type == "message" or $s.type == "fallback_message")
                 and ([$s.input_tokens, $s.output_tokens, $s.cache_creation_input_tokens, $s.cache_read_input_tokens] | all(type == "number"))
              then { i: $s.input_tokens, o: $s.output_tokens, cc: $s.cache_creation_input_tokens, cr: $s.cache_read_input_tokens }
              else $n end end;
      def stub: (.message.content | type) == "array" and (.message.content[0] | type) == "object"
        and .message.content[0].type == "text"
        and (.message.content[0].text | IN("[Request interrupted by user]", "[Request interrupted by user for tool use]",
             "No response requested.",
             "The user doesn'"'"'t want to take this action right now. STOP what you are doing and wait for the user to tell you how to proceed.",
             "The user doesn'"'"'t want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed."));
      def real: .type == "assistant" and (.message | type) == "object" and (.message.usage | type) == "object"
        and .message.model != "<synthetic>" and .isUnmetered != true and (stub | not)
        and (.message.usage | m7 | (.i + .cc + .cr) > 0);
      def sbe: if .type == "assistant" and (.message | type) == "object" and (.message | has("id"))
        and .message.model != "<synthetic>" then [.message.id] else null end;
      def cleared:  # server context editing, added back by the trigger; null = look further back
        if (.message.context_management | type) == "object" then
          ([.message.context_management.applied_edits[]?
            | select(type == "object" and .type == "clear_tool_uses_20250919" and (.cleared_input_tokens | type) == "number")
            | .cleared_input_tokens] | add // 0)
        elif .message.stop_reason != null then 0 else null end;
      (last(label $out | foreach (inputs | fromjson? | select(type == "object" and .isSidechain != true)) as $l (
        { pend: 0, tent: 0, id: null, last: 0, tok: 0, anc: false, cl: null, done: false };
        if .done then .
        elif .anc | not then
          if $l.type == "system" and $l.subtype == "compact_boundary" then .done = true
          elif ($l | real) then
            ($l.message.usage | m7) as $u
            | .anc = true | .tok = ($u.i + $u.cc + $u.cr + $u.o) | .cl = ($l | cleared)
            | ($l | sbe) as $s
            | if $s != null and ($s[0] | type) == "string" and ($s[0] | length) > 0
              then .id = $s | .last = ($l | est) else .done = true end
          else .pend += ($l | est) end
        else
          ($l | sbe) as $s
          | if $s == .id then .pend += .tent + .last | .tent = 0 | .last = ($l | est)
              | (if .cl == null and ($l | real) then .cl = ($l | cleared) else . end)
            elif $s != null then .done = true
            else .tent += ($l | est) end
        end;
        if .done then (., break $out) else . end))
        // { anc: false, tok: 0, pend: 0 })   # empty transcript (last/1: null in jq 1.7, nothing in 1.8)
      | [.tok, .pend, (.cl // 0)] as $v
      | if ($v | all(type == "number" and . >= 0 and . < 1e12))
        then "\(if .anc then 1 else 0 end) \($v[0]) \($v[1]) \($v[2])" else "" end' 2>/dev/null)
    read -r s_anc s_tok s_pend s_cl <<< "$scan"
    s_anc=$(printf '%s' "$s_anc" | tr -cd '0-9'); s_tok=$(printf '%s' "$s_tok" | tr -cd '0-9')
    s_pend=$(printf '%s' "$s_pend" | tr -cd '0-9'); s_cl=$(printf '%s' "$s_cl" | tr -cd '0-9')
    # empty transcript, no jq: keep the last usage alone
    if [ -n "$s_anc" ] && [ -n "$s_pend" ] && [ "${#s_tok}" -le 12 ] && [ "${#s_pend}" -le 12 ] && [ "${#s_cl}" -le 12 ]; then
      if [ "$s_anc" = 1 ]; then
        # in-memory usage is fresher than the transcript; fall back to the
        # transcript anchor when the last usage is zero (the trigger skips those)
        [ "$cx_base" -gt 0 ] || cx_base=${s_tok:-0}
        cx_used=$(( cx_base + s_pend + ${s_cl:-0} ))
      elif [ "$cx_base" -eq 0 ]; then
        cx_used=$s_pend  # fresh session or just compacted: only what follows counts
      fi
      # else: a response is in memory but not yet in the transcript; keep the
      # last usage alone until the next repaint catches up
    fi
  fi
  _tk() {  # tokens -> compact: 812 / 58k / 467k / 1.2M
    local n=$1
    if [ "$n" -ge 1000000 ]; then
      local m=$(( (n + 50000) / 100000 ))   # tenths of a million, rounded
      if [ $(( m % 10 )) -eq 0 ]; then printf '%dM' $(( m / 10 )); else printf '%d.%dM' $(( m / 10 )) $(( m % 10 )); fi
    elif [ "$n" -ge 1000 ]; then printf '%dk' $(( (n + 500) / 1000 ))
    else printf '%d' "$n"; fi
  }
  _truthy() {  # env flag the way Claude Code reads it: only 1/true/yes/on, case and spaces ignored
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac
  }
  # Settings, lowest precedence first. Project files live at the project root,
  # not the current subdir. Each source is applied even when two resolve to
  # the same file (project dir = ~), as Claude Code does.
  pdir=$(printf '%s' "$input" | jq -r '.workspace.project_dir // .cwd // empty' 2>/dev/null)
  [ -n "$pdir" ] || pdir=$cwd
  ac_en=""; ac_def=""; ac_mod=""
  for f in "$CFG/settings.json" "$pdir/.claude/settings.json" "$pdir/.claude/settings.local.json" \
           /etc/claude-code/managed-settings.json "/Library/Application Support/ClaudeCode/managed-settings.json"; do
    # Like Claude Code's reader: symlinks are followed (dotfile managers, Nix
    # home-manager), and a file over 2 MiB is not read. Only whitelisted
    # values come out below, nothing raw.
    _cfg_ok "$f" 2097152 || continue
    # "<enabled>\x1f<top-level window>\x1f<this model's window>"; a window is an
    # integer 100k..1M, "auto", "-" when the file leaves it unset; invalid = unset
    IFS=$'\x1f' read -r e top mod <<< "$(jq -r --arg k "$mkey" '
      def norm: ascii_downcase | sub("\\[[^]]*\\]$"; "")
        | (if test("claude-") then "claude-" + (split("claude-")[1:] | join("claude-")) else . end)
        | sub("@.*$"; "") | sub("-v[0-9]+(:[0-9]+)?$"; "") | sub("-[0-9]{8}$"; "") | gsub("[._]"; "-");
      def win: if . == "auto" then "auto"
        elif type == "number" and . == floor and . >= 100000 and . <= 1000000 then tostring else "-" end;
      if type != "object" then "" else
        [ (.autoCompactEnabled | if type == "boolean" then tostring else "" end),
          (.autoCompactWindow // null | if . == null then "-" else win end),
          ((.modelSettings // {}) | if type != "object" or $k == "" then "-" else
             [to_entries[] | select((.value | type) == "object" and (.value.autoCompactWindow != null) and (.key | norm) == $k)]
             | ((map(select(.key == $k)) | first) // first) | if . == null then "-" else (.value.autoCompactWindow | win) end end)
        ] | join("\u001f") end' "$f" 2>/dev/null)"
    [ -n "$e" ] && ac_en=$e
    if [ -n "$top" ] && [ "$top" != - ]; then ac_def=$top; ac_mod=""; fi   # top-level resets per-model
    [ -n "$mod" ] && [ "$mod" != - ] && ac_mod=$mod
  done
  # legacy global config: $CFG/.config.json when non-empty, else .claude.json
  # in CLAUDE_CONFIG_DIR (or ~ when unset), the file Claude Code itself picks
  gcf="$CFG/.config.json"
  [ -f "$gcf" ] && [ -s "$gcf" ] || gcf="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  if [ -z "$ac_en" ] && _cfg_ok "$gcf" 16777216; then
    ac_en=$(jq -r '.autoCompactEnabled | if type == "boolean" then tostring else "" end' "$gcf" 2>/dev/null)
  fi
  cx_on=1
  [ "$ac_en" = false ] && cx_on=0
  { _truthy "${DISABLE_AUTO_COMPACT:-}" || _truthy "${DISABLE_COMPACT:-}"; } && cx_on=0
  if [ "$cx_on" = 1 ]; then
    acw=""
    if [ -n "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" ]; then
      # Claude Code's size parser: 200k / 1.5M / 500000; below 100k -> 100k,
      # above 1M -> 1M, unparsable -> ignored
      acw=$(jq -nr --arg s "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" '
        ($s | gsub("^\\s+|\\s+$"; "")) as $r | ($r[-1:] | ascii_downcase) as $u
        | (if $u == "m" or $u == "k" then ($r[:-1] | tonumber? // null) | (if . == null then null
             else . * (if $u == "m" then 1000000 else 1000 end) end)
           else ($r | tonumber? // null) end) as $w
        | if $w == null or ($w | isnan) or $w < 1 then ""
          elif $w < 100000 then 100000 elif $w > 1000000 then 1000000 else ($w | round) end' 2>/dev/null | tr -cd '0-9')
    fi
    if [ -z "$acw" ]; then
      acw=${ac_mod:-$ac_def}
      [ "$acw" = auto ] && acw=""
    fi
    { [ -z "$acw" ] || [ "$acw" -gt "$cx_win" ]; } && acw=$cx_win
    mo=$(printf '%s' "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}" | tr -cd '0-9' | head -c 12)
    { [ -z "$mo" ] || [ "$mo" -gt 20000 ]; } && mo=20000
    cx_thr=$(( acw - mo - 13000 ))
    # CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (0 < pct <= 100, decimals allowed) can only lower it
    t2=$(awk -v p="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}" -v e="$(( acw - mo ))" \
      'BEGIN { if (p ~ /^[ \t]*[0-9]*\.?[0-9]+/ && p + 0 > 0 && p + 0 <= 100) printf "%d", int(e * (p / 100)) }' 2>/dev/null)
    [ -n "$t2" ] && [ "$t2" -lt "$cx_thr" ] && cx_thr=$t2
    [ "$cx_thr" -lt 1 ] && cx_thr=1
    suffix=""
  else
    cx_thr=$cx_win
    suffix=" ∅ compact"
  fi
  # integer percent, floored so 100% shows only once used >= threshold (the
  # moment compaction fires); clamped because used can overshoot briefly
  cx_pct=$(( cx_used * 100 / cx_thr )); [ "$cx_pct" -gt 100 ] && cx_pct=100
  # no tier tint: context is informational, not a limit — plain dim text
  printf ' \033[1;38;5;252m[\033[0m \033[38;5;250mCtx\033[0m \033[38;5;245m%d%% / %s%s\033[0m \033[1;38;5;252m]\033[0m' \
    "$cx_pct" "$(_tk "$cx_thr")" "$suffix"
fi

# Claude usage limits: 5-hour + weekly (seven_day).
# Color by tier (<50 green, 50-74 blue, 75-89 yellow, >=90 red) + compact reset countdown.
# All sessions show identical values by reading ONE shared store, refreshed from
# the OAuth usage endpoint on wall-clock 30s boundaries (xx:00 / xx:30) so they
# update in lockstep regardless of when each session opened. No explicit
# session-open trigger needed: if another session is active the store is <30s
# fresh and gets reused (no fetch); if this is the only session the store is
# stale, so the boundary check fires on the first render — instant limits
# either way. Never more than one fetch per 5s. Harness rate_limits is fallback
# only — per-session snapshots diverge, which the shared store exists to avoid.
SHARED="$CFG/.statusline-limits-fetch"
now_s=$(date +%s)
last=0
[ -f "$SHARED" ] && [ ! -L "$SHARED" ] && last=$(stat -c %Y "$SHARED" 2>/dev/null || echo 0)
need=0
[ $(( now_s / 30 )) -gt $(( last / 30 )) ] && need=1   # crossed a :00/:30 boundary since last fetch
[ $(( now_s - last )) -lt 5 ] && need=0                # min 5s between fetches
lim=""
if [ "$need" = 1 ]; then
  # single-flight: mkdir is atomic, so exactly one session per boundary does the
  # GET even when several render simultaneously; losers read the store below.
  # A lock left by a session killed mid-fetch is reclaimed after 10s.
  LOCK="$SHARED.lock"
  [ -d "$LOCK" ] && [ $(( now_s - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) )) -ge 10 ] && rmdir "$LOCK" 2>/dev/null
  if mkdir "$LOCK" 2>/dev/null; then
    tok=""
    _cfg_ok "$CFG/.credentials.json" 1048576 \
      && tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CFG/.credentials.json" 2>/dev/null)
    if [ -n "$tok" ]; then
      lim=$(curl -sS -m 2 -H "Authorization: Bearer $tok" \
        -H "anthropic-beta: oauth-2025-04-20" \
        https://api.anthropic.com/api/oauth/usage 2>/dev/null | jq -r '
        def ep(x): if x == null then "" else
          (x | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601 | tostring) end;
        def pc(x): if x == null then "" else (x | round | tostring) end;
        [pc(.five_hour.utilization), ep(.five_hour.resets_at),
         pc(.seven_day.utilization), ep(.seven_day.resets_at)] | join("\u001f")' 2>/dev/null)
      printf '%s' "$lim" | grep -q '[0-9]' && printf '%s' "$lim" > "$SHARED" 2>/dev/null
    fi
    rmdir "$LOCK" 2>/dev/null
  fi
fi
if ! printf '%s' "$lim" | grep -q '[0-9]' && [ -f "$SHARED" ] && [ ! -L "$SHARED" ]; then
  lim=$(head -c 256 "$SHARED" 2>/dev/null | tr -cd '0-9.\037')
fi
if ! printf '%s' "$lim" | grep -q '[0-9]'; then
  # endpoint unreachable and no store yet -> harness data (may lag this session)
  lim=$(printf '%s' "$input" | jq -r '
    def n2s: if . == null then ""
             elif type == "number" then (round | tostring)
             else tostring end;
    [(.rate_limits.five_hour.used_percentage | n2s), (.rate_limits.five_hour.resets_at | n2s),
     (.rate_limits.seven_day.used_percentage | n2s), (.rate_limits.seven_day.resets_at | n2s)]
    | join("\u001f")' 2>/dev/null)
fi
if [ -n "${lim// /}" ] && printf '%s' "$lim" | grep -q '[0-9]'; then
  IFS=$'\x1f' read -r H5 H5R D7 D7R <<< "$lim"
  now=$(date +%s)
  _cd() {  # epoch -> compact countdown to reset
    [ -z "$1" ] && return
    local d=$(( $1 - now ))
    [ "$d" -lt 0 ] && { printf 'now'; return; }
    if   [ "$d" -ge 86400 ]; then printf '%dd%dh' $((d/86400)) $(((d%86400)/3600))
    elif [ "$d" -ge 3600 ];  then printf '%dh%dm' $((d/3600)) $(((d%3600)/60))
    else printf '%dm' $((d/60)); fi
  }
  _seg() {  # label pct epoch -> "label pct ↻ countdown" (label grey, pct bold/threshold, countdown dim)
    local pct=$2 cd; cd=$(_cd "$3")
    # harness only refreshes rate_limits on API responses, so after the window
    # resets it keeps sending stale pre-reset numbers; the window reset means
    # usage is back to 0, and the next reset time is unknown until fresh data
    if [ "$cd" = "now" ]; then pct=0; cd=""; fi
    printf '\033[38;5;250m%s \033[1;38;5;%sm%s%%\033[0m' "$1" "$(_cc "$pct")" "$pct"
    [ -n "$cd" ] && printf ' \033[38;5;245m↻ %s\033[0m' "$cd"
  }
  out=""
  [ -n "$H5" ] && out="$out$(_seg Session "$H5" "$H5R")"
  if [ -n "$D7" ]; then
    [ -n "$out" ] && out="$out \033[38;5;245m·\033[0m "
    out="$out$(_seg Weekly "$D7" "$D7R")"
  fi
  # bright brackets + inner padding for legibility
  [ -n "$out" ] && printf ' \033[1;38;5;252m[\033[0m %b \033[1;38;5;252m]\033[0m' "$out"
fi

# Badges show only while their plugin is still enabled: disabling a plugin
# stops its hooks but leaves the old flag file behind, so the flag alone
# would keep a dead badge on screen forever.
_uset_ok=""
_plugin_on() {  # user-scope settings.json only; per-project enable/disable not checked
  [ -n "$_uset_ok" ] || { _cfg_ok "$CFG/settings.json" 2097152 && _uset_ok=1 || _uset_ok=0; }
  [ "$_uset_ok" = 1 ] && jq -e --arg p "$1" '.enabledPlugins[$p] != false' "$CFG/settings.json" >/dev/null 2>&1
}

# caveman badge: one bracket "[ ⛏ MODE ]", mode only. Caveman 4 dropped its
# savings estimate (an unverified fixed ratio), so there is no number to show.
#   caveman (and legacy lite/full)          -> [ ⛏ ]           (no MODE label)
#   ultracave (legacy ultra)                -> [ ⛏ ULTRACAVE ]
#   megacave (legacy wenyan, wenyan-*)      -> [ ⛏ MEGACAVE ]
#   commit / review / compress              -> [ ⛏ COMMIT ] ...
#   off, unknown, missing                   -> no badge
# Mode comes from this session's file (.caveman-sessions/<session_id>.mode),
# else the machine-wide .caveman-active, with caveman's own hardening:
# session id alphabet + length check (it becomes a path), symlink refusal,
# 64-byte cap, [a-z0-9-] only, whitelist.
mode=""
if _plugin_on caveman@caveman; then
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  case "$sid" in ''|*[!A-Za-z0-9_-]*) sid="" ;; esac
  [ "${#sid}" -gt 128 ] && sid=""
  FLAG="$CFG/.caveman-active"
  [ -n "$sid" ] && [ -f "$CFG/.caveman-sessions/$sid.mode" ] && FLAG="$CFG/.caveman-sessions/$sid.mode"
  if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
    mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  fi
fi
label="-"
case "$mode" in
  caveman|lite|full) label="" ;;
  ultracave|ultra) label="ULTRACAVE" ;;
  megacave|wenyan|wenyan-lite|wenyan-full|wenyan-ultra) label="MEGACAVE" ;;
  commit|review|compress) label=$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]') ;;
esac
if [ "$label" != - ]; then
  inner="⛏"
  [ -n "$label" ] && inner="$inner $label"
  # grey brackets (match limits) + orange caveman content
  printf ' \033[1;38;5;252m[\033[0m \033[38;5;172m%s\033[0m \033[1;38;5;252m]\033[0m' "$inner"
fi

# ponytail badge: one bracket "[ 🎀 MODE ]" (no numbers — ponytail has no
# per-session stats; /ponytail-gain is benchmark medians only).
#   full  -> [ 🎀 ]        (no MODE label)
#   ultra -> [ 🎀 ULTRA ]
# Mode read from ponytail's flag with the same hardening as the caveman badge
# (symlink-refuse, size-cap, whitelist).
PFLAG="$CFG/.ponytail-active"
pmode=""
if [ -f "$PFLAG" ] && [ ! -L "$PFLAG" ] && _plugin_on ponytail@ponytail; then
  pmode=$(head -c 32 "$PFLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z-')
  case "$pmode" in
    lite|full|ultra|review) ;;
    *) pmode="" ;;
  esac
fi
if [ -n "$pmode" ]; then
  # 🎀 U+1F380: color emoji, renders fixed pink regardless of the ANSI
  # tint — the tint only affects the MODE label text after it
  pinner="🎀"
  [ "$pmode" != full ] && pinner="$pinner $(printf '%s' "$pmode" | tr '[:lower:]' '[:upper:]')"
  # grey brackets (match limits) + pink ponytail content
  printf ' \033[1;38;5;252m[\033[0m \033[38;5;218m%s\033[0m \033[1;38;5;252m]\033[0m' "$pinner"
fi

# Line 2: bold teal user@host : bold steel-blue dir — deliberately NOT the
# classic green/blue PS1 palette, so this never reads as a real shell prompt
printf '\n\033[1;38;5;80m%s@%s\033[0m:\033[1;38;5;110m%s\033[0m' "$user" "$host" "$dir"

# Always succeed — Claude Code suppresses the statusline if the command exits non-zero
# (e.g. the trailing `&& printf` of an absent badge leaves a false status behind).
exit 0
