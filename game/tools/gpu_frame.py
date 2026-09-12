#!/usr/bin/env python3
"""GPU FRAME TIME from a Metal System Trace (D-055) — the column the perf harness never had.
  xcrun xctrace record --template 'Metal System Trace' --time-limit 20s --output T.trace \
      --launch -- /Applications/Godot.app/Contents/MacOS/Godot --path game -- --perf --perf-only=STATION --perf-repeat=1
  xcrun xctrace export --input T.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' > gpu.xml
  python3 tools/gpu_frame.py gpu.xml [--process Godot]
Per frame (the trace's own frame numbers, Godot's process only): WALL = last encoder end minus
first encoder start; BUSY = union of encoder intervals (Apple GPUs overlap vertex and fragment
work, so a plain sum over-counts). Prints median/p95 of both, the per-channel busy split, and
frames/s presented. Godot 4.7's Metal backend reports 0 for its own GPU timestamps; this is the
measurement the harness's `gpu ms` column has always said n/a for."""
import sys, re, argparse, statistics
from xml.etree import ElementTree as ET

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("xml"); ap.add_argument("--process", default="Godot")
    ap.add_argument("--skip", type=int, default=90, help="frames to skip (warm-up)")
    a = ap.parse_args()
    tree = ET.parse(a.xml); root = tree.getroot()
    refs = {}   # id -> element; xctrace de-duplicates repeated cells by id/ref, anywhere in the row
    def res(e):
        return refs.get(e.attrib["ref"]) if "ref" in e.attrib else e
    frames = {}   # frame -> list of (start, end, channel)
    for row in root.iter("row"):
        for e in row.iter():
            if "id" in e.attrib:
                refs[e.attrib["id"]] = e
        kids = list(row)
        # columns, in schema order: start, duration, channel, frame, latency, depth,
        # label, state, uuid, colour, PROCESS (a direct column — the label's own
        # <process> is the compositor's), device, ...
        st = res(kids[0]); du = res(kids[1]); ch = res(kids[2]); fr = res(kids[3])
        proc = None
        for k in kids:
            if k.tag == "process":
                p = res(k)
                if p is not None: proc = p.attrib.get("fmt", p.text or "")
                break
        if proc is None or a.process not in proc: continue
        try:
            s = int(st.text); d = int(du.text); f = int(fr.text)
        except Exception: continue
        frames.setdefault(f, []).append((s, s + d, (ch.text or "?")))
    if not frames:
        print("GPU FRAME: no rows for process '%s'" % a.process); return
    keys = sorted(frames)[a.skip:]
    wall, busy, chan = [], [], {}
    for f in keys:
        iv = sorted(frames[f])
        wall.append((max(e for _, e, _ in iv) - min(s for s, _, _ in iv)) / 1e6)
        merged, cur = 0, None
        for s, e, c in iv:
            chan[c] = chan.get(c, 0) + (e - s)
            if cur is None or s > cur[1]:
                if cur: merged += cur[1] - cur[0]
                cur = [s, e]
            else: cur[1] = max(cur[1], e)
        if cur: merged += cur[1] - cur[0]
        busy.append(merged / 1e6)
    def p95(x): x = sorted(x); return x[int(0.95 * (len(x) - 1))]
    print("GPU FRAME (%s, %d frames after %d warm-up): wall med %.2f ms p95 %.2f | busy med %.2f ms p95 %.2f"
          % (a.process, len(keys), a.skip, statistics.median(wall), p95(wall), statistics.median(busy), p95(busy)))
    tot = sum(chan.values()) or 1
    print("  channels: " + ", ".join("%s %.0f%%" % (c, 100.0 * v / tot) for c, v in sorted(chan.items(), key=lambda kv: -kv[1])))

if __name__ == "__main__":
    main()
