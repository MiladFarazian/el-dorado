#!/usr/bin/env python3
"""PLATE DIFF — two `--shot` sweeps compared per vantage, with the noise floor built in.
  python3 tools/plates_diff.py BEFORE_DIR AFTER_DIR [--report out.md] [--null CTRL_DIR]
Per vantage: mean absolute difference (0-255) and pixels changed by more than 16.
The harness noise floor on this machine (traffic drifting between boots, D-084/cycle 5)
is ~11-12k changed pixels across 59 vantages; a vantage is flagged when it exceeds
FLAG_PX or when --null is given and it exceeds 3x that vantage's null-control change.
Exit 0 always; the report is the deliverable, the judgement stays with the reader."""
import sys, os, argparse
from PIL import Image, ImageChops, ImageStat

FLAG_PX = 4000      # pixels >16 in one vantage that no ordinary boot-to-boot drift reaches
THRESH = 16

def diff(a, b):
    ia = Image.open(a).convert("RGB"); ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return None, None, "size %sx%s vs %sx%s" % (*ia.size, *ib.size)
    d = ImageChops.difference(ia, ib).convert("L")
    return ImageStat.Stat(d).mean[0], sum(1 for v in d.getdata() if v > THRESH), ""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before"); ap.add_argument("after")
    ap.add_argument("--report", default=None); ap.add_argument("--null", default=None)
    a = ap.parse_args()
    names = sorted(n for n in os.listdir(a.before) if n.endswith(".png") and os.path.exists(os.path.join(a.after, n)))
    rows, total_px, flagged = [], 0, []
    for n in names:
        mean, px, note = diff(os.path.join(a.before, n), os.path.join(a.after, n))
        npx = None
        if a.null and os.path.exists(os.path.join(a.null, n)):
            _, npx, _ = diff(os.path.join(a.before, n), os.path.join(a.null, n))
        flag = ""
        if note: flag = "SIZE"
        elif px > FLAG_PX and (npx is None or px > 3 * max(npx, 1)): flag = "CHANGED"
        if flag: flagged.append(n)
        total_px += px or 0
        rows.append((n[:-4], mean, px, npx, flag, note))
    lines = ["| vantage | meanAbs | px>16 | null px>16 | flag |", "|---|---:|---:|---:|---|"]
    for n, mean, px, npx, flag, note in rows:
        lines.append("| %s | %s | %s | %s | %s |" % (n, "%.2f" % mean if mean is not None else note, px if px is not None else "", "" if npx is None else npx, flag))
    summary = "PLATES: %d vantages, %d changed pixels total (noise floor ~11-12k/59), %d flagged: %s" % (
        len(rows), total_px, len(flagged), ", ".join(x[:-4] for x in flagged) or "none")
    out = "\n".join(lines) + "\n\n" + summary + "\n"
    print(out)
    if a.report:
        with open(a.report, "w") as f: f.write("# Plate diff\n\n`%s` → `%s`\n\n%s" % (a.before, a.after, out))

if __name__ == "__main__":
    main()
