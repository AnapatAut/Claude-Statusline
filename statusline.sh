#!/bin/bash
# Custom Claude Code statusline — two lines:
#   [ <model> <effort> ] [ Ctx <pct> / <threshold> ] [ Session <pct> ↻ <reset> · Weekly <pct> ↻ <reset> ] [ ⛏ <saved> ] [ 🎀 <mode> ]
#   <user>@<host>:<dir>
#
# Line 1 badges: model/effort, context usage vs the auto-compact threshold
# (plain, untinted), usage limits (tiers: <50 green, 50-74 blue, 75-89 yellow,
# >=90 red; clock-synced shared fetch, see below), caveman badge, ponytail badge.
# Line 2 prompt-style location in teal/steel-blue — deliberately NOT the classic
# green/blue PS1 palette so it never reads as a real shell prompt. Long paths
# get a whole line, so they can't push the badges off-screen.
#
# The caveman badge mirrors caveman's own hooks/caveman-statusline.sh logic so its
# mode whitelist + symlink/escape hardening stay the source of truth and keep
# working across caveman updates.

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
# "Now" is what Claude Code's own trigger compares, not just the last usage:
#   last response (input + cache_create + cache_read + OUTPUT tokens, from
#   .context_window.current_usage)
#   + estimate of everything appended to the transcript since that response
#     (tool results, hook/system-reminder attachments) at the same chars/token
#     rule the trigger uses: 3 chars/token (4 for pre-4.7 models), images 2000
# Without the extra terms the badge reads ~2k low and compaction seems early.
# No API response yet (fresh session, or right after a compaction) counts as
# 0 + pending, again matching the trigger.
# The threshold mirrors the /context autoCompactThreshold:
#   threshold = min(model window, autoCompactWindow) - min(max_output, 20000) - 13000
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
read -r cx_used cx_win <<< "$(printf '%s' "$input" | jq -r '
  .context_window as $c
  | if ($c | type) != "object" or (($c.context_window_size // 0) | type) != "number" then "" else
    (if ($c.current_usage | type) == "object" then
       (($c.current_usage.input_tokens // 0) + ($c.current_usage.cache_creation_input_tokens // 0)
        + ($c.current_usage.cache_read_input_tokens // 0) + ($c.current_usage.output_tokens // 0))
     else 0 end | floor | tostring)
    + " " + ($c.context_window_size | floor | tostring) end' 2>/dev/null)"
# digits only past this point: any surprise (floats, "null", missing jq) hides the badge
cx_used=$(printf '%s' "$cx_used" | tr -cd '0-9'); cx_win=$(printf '%s' "$cx_win" | tr -cd '0-9')
if [ -n "$cx_used" ] && [ -n "$cx_win" ] && [ "${#cx_win}" -le 12 ] && [ "${#cx_used}" -le 12 ] && [ "$cx_win" -gt 0 ]; then
  # Pending tokens: transcript lines after the last assistant entry or the
  # last compaction boundary (tool results, attachments, a fresh prompt, the
  # compaction summary) estimated the way the trigger does. tac + early-exit
  # awk reads only the tail, so a multi-MB transcript stays cheap.
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ] && [ ! -L "$tp" ]; then
    mid=$(printf '%s' "$input" | jq -r '.model.id // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr '._' '--')
    mid=${mid##*/}; mid=${mid%\[1m\]}; mid=$(printf '%s' "$mid" | sed -E 's/-v[0-9]+(:[0-9]+)?$//; s/-[0-9]{8}$//')
    case "$mid" in  # older models tokenize ~4 chars/token, everything newer 3
      *claude-3-*|*claude-opus-4-[0156]|*claude-sonnet-4-[056]|*claude-haiku-4-5) cpt=4 ;;
      *) cpt=3 ;;
    esac
    pend=$({ tac "$tp" 2>/dev/null || tail -r "$tp" 2>/dev/null; } \
      | awk '/"type":"assistant"/ || /"subtype":"compact_boundary"/ {exit} {print}' \
      | jq -n -R --argjson cpt "$cpt" '
      def est:
        if type == "string" then (length / $cpt | round)
        elif type == "array" then (map(
            if type == "string" then (length / $cpt | round)
            elif .type == "text" then ((.text // "") | length / $cpt | round)
            elif .type == "image" or .type == "document" then 2000
            elif .type == "tool_result" then (.content | est)
            elif .type == "tool_use" then (((.name // "") + ((.input // {}) | tojson)) | length / $cpt | round)
            elif .type == "thinking" then ((.thinking // "") | length / $cpt | round)
            else (tojson | length / $cpt | round) end) | add // 0)
        elif type == "null" then 0
        else (tojson | length / $cpt | round) end;
      reduce (inputs | fromjson? // empty) as $l (0;
        . + (if $l.type == "user" or $l.type == "assistant" then ($l.message.content | est)
             elif $l.type == "attachment" then (($l.attachment.text // $l.attachment.content // $l.attachment.prompt // null) | est)
             else 0 end))' 2>/dev/null | tr -cd '0-9')
    [ -n "$pend" ] && [ "${#pend}" -le 12 ] && cx_used=$(( cx_used + pend ))
  fi
  _tk() {  # tokens -> compact: 812 / 58k / 467k / 1.2M
    local n=$1
    if [ "$n" -ge 1000000 ]; then
      local m=$(( (n + 50000) / 100000 ))   # tenths of a million, rounded
      if [ $(( m % 10 )) -eq 0 ]; then printf '%dM' $(( m / 10 )); else printf '%d.%dM' $(( m / 10 )) $(( m % 10 )); fi
    elif [ "$n" -ge 1000 ]; then printf '%dk' $(( (n + 500) / 1000 ))
    else printf '%d' "$n"; fi
  }
  _truthy() {  # env flag set the way Claude Code reads it (1/true/yes/on); 0/false/no/off/"" = unset
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in ''|0|false|no|off) return 1 ;; *) return 0 ;; esac
  }
  # autoCompactEnabled / autoCompactWindow from settings, most specific scope
  # wins per key: project local > project > user. One jq per existing file;
  # a malformed file is skipped, not fatal. `false` must survive, so no `//`.
  ac_en=""; ac_win=""
  for f in "$cwd/.claude/settings.local.json" "$cwd/.claude/settings.json" "$CFG/settings.json"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    IFS=$'\x1f' read -r e w <<< "$(jq -r '
      def v(k): if has(k) and .[k] != null then (.[k] | tostring) else "" end;
      if type == "object" then [v("autoCompactEnabled"), v("autoCompactWindow")] | join("") else "" end
    ' "$f" 2>/dev/null)"
    [ -z "$ac_en" ]  && ac_en=$e
    [ -z "$ac_win" ] && ac_win=$(printf '%s' "$w" | tr -cd '0-9')
    [ -n "$ac_en" ] && [ -n "$ac_win" ] && break
  done
  cx_on=1
  [ "$ac_en" = false ] && cx_on=0
  { _truthy "${DISABLE_AUTO_COMPACT:-}" || _truthy "${DISABLE_COMPACT:-}"; } && cx_on=0
  if [ "$cx_on" = 1 ]; then
    # window: env (Claude Code accepts 100k..1M) > settings > model window; never above model window
    acw=$(printf '%s' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}" | tr -cd '0-9' | head -c 12)
    if [ -n "$acw" ]; then
      [ "$acw" -lt 100000 ] && acw=100000
      [ "$acw" -gt 1000000 ] && acw=1000000
    fi
    [ -z "$acw" ] && acw=$(printf '%s' "$ac_win" | head -c 12)
    { [ -z "$acw" ] || [ "$acw" -gt "$cx_win" ]; } && acw=$cx_win
    mo=$(printf '%s' "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}" | tr -cd '0-9' | head -c 12)
    { [ -z "$mo" ] || [ "$mo" -gt 20000 ]; } && mo=20000
    cx_thr=$(( acw - mo - 13000 ))
    pct_ov=$(printf '%s' "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}" | tr -cd '0-9' | head -c 3)
    if [ -n "$pct_ov" ] && [ "$pct_ov" -gt 0 ] && [ "$pct_ov" -le 100 ]; then
      t2=$(( (acw - mo) * pct_ov / 100 )); [ "$t2" -lt "$cx_thr" ] && cx_thr=$t2
    fi
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
# Color by threshold (>=90 red, >=70 amber, else blue-grey) + compact reset countdown.
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
    tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CFG/.credentials.json" 2>/dev/null)
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
_plugin_on() {  # ponytail: user-scope settings.json only; per-project enable/disable not checked
  jq -e --arg p "$1" '.enabledPlugins[$p] != false' "$CFG/settings.json" >/dev/null 2>&1
}

# caveman badge: one bracket "[ ⛏ MODE saved (pct) ]".
#   full  -> [ ⛏ 28.8M ]        (no MODE label)
#   ultra -> [ ⛏ ULTRA 28.8M ]
#   lite  -> [ ⛏ LITE ]         (number suppressed — lite has no benchmark)
# Mode read from caveman's flag with its hardening (symlink-refuse, size-cap, whitelist).
FLAG="$CFG/.caveman-active"
mode=""
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ] && _plugin_on caveman@caveman; then
  mode=$(head -c 32 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z-')
  case "$mode" in
    lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
    *) mode="" ;;
  esac
fi
if [ -n "$mode" ]; then
  # est. tokens saved + % (high-water per session) from caveman history
  sav=""
  HIST="$CFG/.caveman-history.jsonl"
  if [ -f "$HIST" ] && [ ! -L "$HIST" ]; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    sav=$(jq -rs --arg sid "$sid" '
      map(select($sid != "" and .session_id == $sid))
      | (group_by(.session_id) | map(max_by(.est_saved_tokens // 0))) as $L
      | ($L | map(.est_saved_tokens // 0) | add // 0) as $s
      | ($L | map(.output_tokens // 0) | add // 0) as $o
      | if $s > 0 then
          (if $s >= 1000000 then (($s/1000000*10|round)/10|tostring)+"M"
           elif $s >= 1000 then (($s/1000*10|round)/10|tostring)+"k"
           else ($s|tostring) end)
        else "" end
    ' "$HIST" 2>/dev/null)
  fi
  label=""; [ "$mode" != full ] && label=$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')
  [ "$mode" = lite ] && sav=""          # lite: label only, no token number
  inner="⛏"
  [ -n "$label" ] && inner="$inner $label"
  [ -n "$sav" ]   && inner="$inner $sav"
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
# (e.g. a new session has no savings yet, so the trailing `&& printf` above is false).
exit 0
