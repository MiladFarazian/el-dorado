#!/bin/zsh
# GPU FRAME TIME for one perf station via Metal System Trace (D-055).
#   game/tools/gpu_trace.sh STATION [SECONDS]      default 12 s attached window
# Boots Godot normally (its own log keeps the harness table), ATTACHES Instruments the
# moment the harness prints PERF HARNESS: (city built, warm-up starting), records the
# measured frames, exports metal-gpu-intervals and prints GPU wall/busy per frame
# (tools/gpu_frame.py). Instruments adds overhead: read the GPU/CPU split and the
# channel mix, not the absolute number against bar §4b.
set -u
G=/Applications/Godot.app/Contents/MacOS/Godot
HERE=$(cd "$(dirname "$0")/.." && pwd)
STATION=${1:?station name, e.g. hospital_door_night}; SECS=${2:-12}
OUT=${GATE_OUT:-${SCRATCHPAD:-/tmp}}/gpu-$STATION-$(date +%H%M%S); mkdir -p "$OUT"
pgrep -x Godot >/dev/null && { echo "GPU TRACE: a Godot process is already running — refusing"; exit 2; }
cd "$HERE"
"$G" -- --perf --perf-only="$STATION" --perf-repeat=1 --perf-frames=900 > "$OUT/godot.log" 2>&1 &
GPID=$!
for i in $(seq 1 120); do sleep 0.5; grep -q 'PERF HARNESS' "$OUT/godot.log" && break; kill -0 $GPID 2>/dev/null || break; done
if ! grep -q 'PERF HARNESS' "$OUT/godot.log"; then echo "GPU TRACE: harness never started"; kill $GPID 2>/dev/null; exit 1; fi
sleep 2   # past the 90 warm-up frames
xcrun xctrace record --template 'Metal System Trace' --time-limit "${SECS}s" --attach "$GPID" --output "$OUT/trace.trace" > "$OUT/record.log" 2>&1
wait $GPID 2>/dev/null
xcrun xctrace export --input "$OUT/trace.trace" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' > "$OUT/gpu.xml" 2>/dev/null
grep -E "^\| $STATION" "$OUT/godot.log" | tr -s ' ' | cut -c1-100
python3 "$HERE/tools/gpu_frame.py" "$OUT/gpu.xml" --skip 0
echo "GPU TRACE: $OUT"
