#!/bin/zsh
# THE GATE (D-055) — one command, every step, one Godot at a time, correct redirects.
#   game/tools/gate.sh            quick: load check, parse, lint, smoke x2, boot 900, session test
#   game/tools/gate.sh --full     + warm garment cache, 59-plate sweep (watchdog), plate diff, perf
#   game/tools/gate.sh --perf     the two watch stations only (refuses under load)
# Evidence goes to $GATE_OUT (default: a dated dir under the scratchpad or /tmp).
set -u
G=/Applications/Godot.app/Contents/MacOS/Godot
HERE=$(cd "$(dirname "$0")/.." && pwd)          # game/
ROOT=$(cd "$HERE/.." && pwd)                      # repo
OUT=${GATE_OUT:-${SCRATCHPAD:-/tmp}/gate-$(date +%Y%m%d-%H%M%S)}; mkdir -p "$OUT"
MODE=${1:-quick}
pass=0; fail=0; rows=()
row() { rows+=("| $1 | $2 | $3 |"); case "$2" in PASS*) pass=$((pass+1));; INFO*|SKIP*|LOADED*|CONTENDED*) ;; *) fail=$((fail+1));; esac; }
need_quiet() { pgrep -x Godot >/dev/null && { echo "GATE: a Godot process is already running — refusing (one Godot at a time)"; exit 2; }; }
load1() { uptime | sed -E 's/.*load averages?: ([0-9.]+).*/\1/'; }
cd "$HERE"
need_quiet
echo "GATE $MODE → $OUT"
# 0. machine
L=$(load1); TOP=$(ps -Ao %cpu,comm | sort -rn | sed -n 2p | awk '{printf "%s%% %s", $1, $2}' | cut -c1-60)
row "machine" "$( (( $(echo "$L > 2.0" | bc) )) && echo "LOADED load=$L" || echo "PASS load=$L")" "top: $TOP"
# 1. parse (one boot, every script)
$G --headless --script res://tools/parse_all.gd > "$OUT/parse.log" 2>&1; P=$(grep -E '^PARSE:' "$OUT/parse.log")
row "parse" "$([[ "$P" == *", 0 failed" ]] && echo PASS || echo FAIL)" "$P"
# 2. lint (substance only; .gdlintrc)
if [[ -x "$ROOT/.venv/bin/gdlint" ]]; then N=$("$ROOT/.venv/bin/gdlint" scripts tools 2>&1 | grep -cE ':[0-9]+: '); row "lint" "$([[ $N -eq 0 ]] && echo PASS || echo FAIL)" "$N findings"; else row "lint" "SKIP" "no .venv/bin/gdlint"; fi
# 3. smoke x2 — byte-identical, the physics contract
S1=$($G --headless -- --smoke 2>&1 | grep '^SMOKE'); S2=$($G --headless -- --smoke 2>&1 | grep '^SMOKE')
row "smoke x2" "$([[ "$S1" == "$S2" && "$S1" == "SMOKE PASS"* ]] && echo PASS || echo FAIL)" "$S1"
# 4. boot 900 — zero ERROR lines; the D-023 leak warning is the one allowed WARNING
$G --headless --quit-after 900 > "$OUT/boot900.log" 2>&1; E=$(grep -cE '^(ERROR|SCRIPT ERROR)' "$OUT/boot900.log"); W=$(grep -c '^WARNING' "$OUT/boot900.log")
row "boot 900" "$([[ $E -eq 0 && $W -le 1 ]] && echo PASS || echo FAIL)" "ERROR=$E WARN=$W"
# 5. session harness (Codex)
$G --headless --script res://tools/session_test.gd -- --session-test > "$OUT/session.log" 2>&1; ST=$(grep -E 'SESSION TEST' "$OUT/session.log")
row "session" "$([[ "$ST" == *PASS* ]] && echo PASS || echo FAIL)" "$ST"
if [[ "$MODE" == "--full" || "$MODE" == "--perf" ]]; then
  if [[ "$MODE" == "--full" ]]; then
    # 6. warm the garment cache (D-050) so the sweep judges a dressed wardrobe
    $G --headless --quit-after 20000 -- > "$OUT/warm.log" 2>&1; R=$(grep -c 'SKIN LIB.*ready' "$OUT/warm.log"); E=$(grep -cE '^(ERROR|SCRIPT ERROR)' "$OUT/warm.log")
    row "warm cache" "$([[ $E -eq 0 ]] && echo PASS || echo FAIL)" "ERROR=$E, $R buckets baked"
    # 7. the 59-plate sweep under its watchdog, then a diff against the previous accepted sweep
    $G -- --shot > "$OUT/shot.log" 2>&1; N=$(grep -c 'SHOT saved' "$OUT/shot.log"); ST=$(grep -c 'SHOT STALL' "$OUT/shot.log"); E=$(grep -cE '^(ERROR|SCRIPT ERROR)' "$OUT/shot.log")
    mkdir -p "$OUT/plates"; cp "$HERE"/.gate/shots/*.png "$OUT/plates/" 2>/dev/null
    row "sweep" "$([[ $N -eq 59 && $ST -eq 0 && $E -eq 0 ]] && echo PASS || echo FAIL)" "saved=$N stalls=$ST ERROR=$E"
    PREV=${GATE_PREV_PLATES:-}; GATE_NULL=${GATE_NULL:-$HERE/.gate/null/B}
    if [[ -n "$PREV" && -d "$PREV" ]]; then
      python3 tools/plates_diff.py "$PREV" "$OUT/plates" --report "$OUT/plates_diff.md" ${GATE_NULL:+--null "$GATE_NULL"} > "$OUT/plates_diff.txt" 2>&1
      row "plate diff" "INFO" "$(grep '^PLATES:' "$OUT/plates_diff.txt" | cut -c1-110)"
    else
      row "plate diff" "SKIP" "set GATE_PREV_PLATES=<dir>; GATE_NULL defaults to game/.gate/null/B"
    fi
  fi
  # 8. perf — the two watch stations, best of 3, refused under load (§4b needs a quiet machine)
  L=$(load1)
  if (( $(echo "$L > 2.0" | bc) )); then
    row "perf" "CONTENDED" "load=$L — no ruling; re-run when the machine is quiet"
  else
    for S in hospital_door_night downtown_day; do
      $G -- --perf --perf-repeat=3 --perf-only=$S > "$OUT/perf_$S.log" 2>&1
      LINE=$(grep -E "^\| $S" "$OUT/perf_$S.log" | tr -s ' ' | cut -c1-96)
      V=$(echo "$LINE" | grep -oE '(ok|FAIL) *\|$' | grep -oE 'ok|FAIL')
      row "perf $S" "$([[ "$V" == ok ]] && echo PASS || echo FAIL)" "$LINE"
    done
  fi
fi
# summary
echo; echo "| step | result | detail |"; echo "|---|---|---|"; printf '%s\n' "${rows[@]}"
{ echo "# GATE $MODE — $(date '+%Y-%m-%d %H:%M')"; echo; echo "| step | result | detail |"; echo "|---|---|---|"; printf '%s\n' "${rows[@]}"; } > "$OUT/GATE.md"
echo; echo "GATE: $pass pass, $fail fail → $OUT/GATE.md"
[[ $fail -eq 0 ]]
