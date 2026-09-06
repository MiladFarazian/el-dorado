#!/usr/bin/env python3
"""Contact sheets + the measured comparison, from the PNGs skin_compare wrote.

  python3 tools/sheet.py sheet  <pass> <name...>   -> old-vs-new contact sheet
  python3 tools/sheet.py metric                    -> the numbers table

METRICS
  silhouette px   pixels the figure covers at the vantage (matte pass, the
                  background is pure green and nothing else is)
  perimeter px    silhouette boundary length. Ratio to sqrt(area) is a shape
                  complexity index: a smooth body scores low, a body made of
                  crossing balls scores high because every crossing adds notches
  owner edges     adjacent pixel pairs with different part ids in the id pass.
                  This is the project's own "owner-change edges" measure — the
                  visible seam length between rigid parts. One skinned surface
                  scores 0 on the body by construction.
  parts visible   distinct part ids contributing at least one pixel
"""
import sys, os, glob
import numpy as np
from PIL import Image

DIR = "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/shots/skin"
BG = np.array([0, 255, 0])


def load(tag):
    p = os.path.join(DIR, tag + ".png")
    if not os.path.exists(p):
        return None
    return np.array(Image.open(p).convert("RGB"), dtype=np.int16)


def fg_mask(img):
    """Anything that is not the flat green backdrop."""
    return (np.abs(img - BG).sum(axis=2) > 60)


def crop_box(masks, pad=24):
    ys, xs = [], []
    for m in masks:
        if m is None or not m.any():
            continue
        y, x = np.nonzero(m)
        ys += [y.min(), y.max()]
        xs += [x.min(), x.max()]
    if not ys:
        return None
    return (max(0, min(xs) - pad), max(0, min(ys) - pad),
            max(xs) + pad, max(ys) + pad)


def perimeter(m):
    p = np.zeros_like(m)
    p[1:, :] |= m[1:, :] ^ m[:-1, :]
    p[:, 1:] |= m[:, 1:] ^ m[:, :-1]
    return int(p.sum())


def owner_edges(img, m):
    """Adjacent pixel pairs, both on the figure, whose part ids differ."""
    q = (img + 5) // 25            # quantise the 25-step id cube
    n = 0
    a = m[1:, :] & m[:-1, :]
    n += int((a & (q[1:, :] != q[:-1, :]).any(axis=2)).sum())
    a = m[:, 1:] & m[:, :-1]
    n += int((a & (q[:, 1:] != q[:, :-1]).any(axis=2)).sum())
    return n


def parts_visible(img, m):
    q = ((img + 5) // 25)[m]
    if q.size == 0:
        return 0
    return len(np.unique(q[:, 0] * 10000 + q[:, 1] * 100 + q[:, 2]))


def cmd_sheet(pass_name, names):
    rows = []
    for nm in names:
        o = load("old_%s_%s" % (nm, pass_name))
        n = load("new_%s_%s" % (nm, pass_name))
        if o is None or n is None:
            continue
        box = crop_box([fg_mask(load("old_%s_matte" % nm)),
                        fg_mask(load("new_%s_matte" % nm))])
        if box:
            o = o[box[1]:box[3], box[0]:box[2]]
            n = n[box[1]:box[3], box[0]:box[2]]
        rows.append((nm, o, n))
    if not rows:
        print("no images")
        return
    h = max(r[1].shape[0] for r in rows)
    w = max(r[1].shape[1] for r in rows)
    sheet = Image.new("RGB", (w * 2 * len(rows), h), (20, 20, 22))
    for i, (nm, o, n) in enumerate(rows):
        for j, im in enumerate((o, n)):
            sheet.paste(Image.fromarray(im.astype(np.uint8)),
                        (i * 2 * w + j * w, 0))
    out = os.path.join(DIR, "sheet_%s.png" % pass_name)
    sheet.save(out)
    print(out, "  order: " + " | ".join("%s(old,new)" % r[0] for r in rows))


def cmd_metric():
    names = ["face", "torso", "side", "back", "portrait", "shoulder", "elbow",
             "full"]
    print("%-10s %-5s %9s %9s %7s %8s %7s" %
          ("vantage", "path", "sil_px", "perim_px", "P/sqA", "ownerEdg", "parts"))
    agg = {"old": [0, 0], "new": [0, 0]}
    for nm in names:
        for path in ("old", "new"):
            mt = load("%s_%s_matte" % (path, nm))
            idm = load("%s_%s_id" % (path, nm))
            if mt is None or idm is None:
                continue
            m = fg_mask(mt)
            mi = fg_mask(idm)
            area = int(m.sum())
            per = perimeter(m)
            oe = owner_edges(idm, mi)
            pv = parts_visible(idm, mi)
            agg[path][0] += oe
            agg[path][1] += pv
            print("%-10s %-5s %9d %9d %7.2f %8d %7d" %
                  (nm, path, area, per, per / max(np.sqrt(area), 1), oe, pv))
    print("TOTAL owner edges  old=%d  new=%d" % (agg["old"][0], agg["new"][0]))


def cmd_gait():
    print("%-10s %-5s %-6s %8s %7s" % ("vantage", "path", "phase", "ownerEdg", "parts"))
    for vn in ("shoulder", "elbow"):
        for path in ("old", "new"):
            tot = []
            for gi in range(8):
                idm = load("gait%d_%s_%s_id" % (gi, path, vn))
                if idm is None:
                    continue
                mi = fg_mask(idm)
                tot.append((gi, owner_edges(idm, mi), parts_visible(idm, mi)))
            for gi, oe, pv in tot:
                print("%-10s %-5s %-6d %8d %7d" % (vn, path, gi, oe, pv))
            if tot:
                print("%-10s %-5s %-6s %8.0f %7.1f   <= mean over the cycle" %
                      (vn, path, "MEAN", np.mean([t[1] for t in tot]),
                       np.mean([t[2] for t in tot])))


def cmd_arch():
    """The seam metric per ARCHETYPE, which is the wardrobe cycle's question.

    The body was adopted on one config's numbers. A wardrobe adds a SECOND
    skinned surface, and a second surface can produce owner-change edges where
    its silhouette crosses the body's — so the metric has to be re-earned on
    every archetype rather than assumed to carry over from Book."""
    names = ["CASUAL", "WESTERN", "WORKER", "OFFICE", "SERVICE", "STREET",
             "SCRUBS", "GAMEDAY", "COP"]
    vants = ["torso", "side", "back", "full"]
    print("%-9s %-6s %9s %9s %8s %7s %8s %7s   %s" %
          ("outfit", "vantage", "oldEdge", "newEdge", "delta", "oldPrt",
           "newPrt", "P/sqA", "verdict"))
    to, tn = 0, 0
    rows = []
    for nm in names:
        so, sn = 0, 0
        for vn in vants:
            io = load("arch%s_old_%s_id" % (nm, vn))
            inn = load("arch%s_new_%s_id" % (nm, vn))
            if io is None or inn is None:
                continue
            mo, mn = fg_mask(io), fg_mask(inn)
            oe, ne = owner_edges(io, mo), owner_edges(inn, mn)
            po, pn = parts_visible(io, mo), parts_visible(inn, mn)
            mt = load("arch%s_new_%s_matte" % (nm, vn))
            psa = 0.0
            if mt is not None:
                m = fg_mask(mt)
                psa = perimeter(m) / max(np.sqrt(int(m.sum())), 1)
            so += oe
            sn += ne
            print("%-9s %-6s %9d %9d %7.1f%% %7d %8d %7.2f" %
                  (nm, vn, oe, ne, -100.0 * (oe - ne) / max(oe, 1), po, pn, psa))
        to += so
        tn += sn
        rows.append((nm, so, sn))
        print("%-9s %-6s %9d %9d %7.1f%%" %
              (nm, "ALL", so, sn, -100.0 * (so - sn) / max(so, 1)))
    print("")
    print("TOTAL over 9 archetypes x 4 vantages: old=%d new=%d  %+.1f%%" %
          (to, tn, -100.0 * (to - tn) / max(to, 1)))
    worst = max(rows, key=lambda r: r[2] / max(r[1], 1))
    print("WORST archetype for the skinned path: %s (%d -> %d, %+.1f%%)" %
          (worst[0], worst[1], worst[2],
           -100.0 * (worst[1] - worst[2]) / max(worst[1], 1)))


if __name__ == "__main__":
    if sys.argv[1] == "sheet":
        cmd_sheet(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == "metric":
        cmd_metric()
    elif sys.argv[1] == "gait":
        cmd_gait()
    elif sys.argv[1] == "arch":
        cmd_arch()
