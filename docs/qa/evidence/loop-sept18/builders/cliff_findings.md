# CEDAR CLIFF / DEACON ARTS DISTRICT — build log & handoff
Owner: Building Designer. File: /Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/world/cedar_cliff.gd
Seed: 411907 (one literal seed, one RNG, no draws in any city stream).

## Chunk log
- chunk 1 — header, ground-plan constants, palettes. 64 lines.
- chunk 2 — accumulators (28 MultiMesh buckets), `build(city)` entry, census print.
- chunk 3 — `_roads()` (Juárez Boulevard N-S leg + E-W spine, 2 side streets, back
  street, 2 sidewalk ribbons, corner street blade) and `_main_street()` + `_storefront()`.
- chunk 4 — taquería menu board, botánica veladora window, Deacon Arts chalkboard,
  paletería cart with striped umbrella.
- chunk 5 — Teatro Estrella: mass, parapet, marquee + 19 bulbs, 9.5 m vertical blade
  (letter-stacked label, both faces), recessed lobby, ticket booth, four doors.
- chunk 6 — papel picado (8 strings × 12 flags between sidewalk poles) and three
  murals (sun / horse / saint) with a `_pbox` wall-plane primitive.
- chunk 7 — `_houses()`: 9 frontage runs, 5 reserved rects, `_house()` craftsman
  bungalow (front gable, porch, posts, rails, chairs, trim, optional picket + tree).
- chunk 8 — the park (green, hex gazebo, 4 benches, swing frame, 6 live oaks,
  municipal plaque) and the church (nave, front-gable roof, steeple + taper spire,
  cross, monument sign).
- chunk 9 — the gentrification corner: chain-link lot, COMING SOON board, leaning
  bandit sign, half-demolished house (slab, one standing gable wall, 14 rubble pieces).
- chunk 10 — Gilead Bottoms: 2 pasture slabs, 3 rail-fenced lots, barn + taper roof,
  trough, hay stack, an open gate on its hinges, two horses, the hand-painted sign.
- chunk 11 — `_flush()` (24 MultiMeshes, every one with `custom_aabb`) + the
  procedural lap-siding triplanar material.
- chunk 12 — `_tree`, `_rail_run`, `_picket_run`, `_fence_run`.
- chunk 13 — plumbing (`_solid`, `_collider`, `_collider_b`, `_prop`, `_axf`,
  `_label`, `_flat`, `_vtx_mat`, `_shared_box`, `_mm`).

## Measured result (headless build probe, since deleted)
    CEDAR CLIFF: 45 houses, 14 storefronts, 31 labels
    CC PROBE: 87-113 ms, 1935 MultiMesh instances, 118 collider boxes, 174 children
    CC CLEARANCE: 118 collider boxes, extent x[-480.0, 285.0] z[566.0, 940.0]
- 934 lines. `PARSE: 93 scripts, 0 failed`. `gdlint: Success: no problems found`.
- Build cost 87-113 ms of CPU including one `TEX.brick_material()` bake — well under
  the one-second budget. No MultiMesh carries an empty AABB (checked, D-059).
- 31 Label3D, under the 40 cap. **`--signaudit` run over the layer: 31 rows, zero
  FAIL**, worst fill 99 % (the COMING SOON hoarding), no overrun anywhere.

## Land clearance — every collider box tested against the forbidden zones
A throwaway probe built the layer headless, took the world AABB of all 118 collider
boxes and intersected each against the smoke corridor, Overflow, County General, the
race channel + rims, the suburb rect, the freeway/frontage band, the downtown street
bed and the two landmark reserves. Result: **zero hits on anything built.** Four
rect intersections reported, all of them benign and all of them deliberate:

1. `downtown street bed` (x 96..794, z 36..570) vs the boulevard's N-S leg
   (x 273..285, z 566..800) — a 4 m overlap at the **junction**. The downtown asphalt
   slab is `Rect2(100, 40, 690, 526)`, i.e. its south edge IS z 566, so the boulevard
   is built to meet it rather than stop short of it. Intentional.
2-4. `landmark reserve S` (x 60..240, z 596..824) vs the boulevard's E-W spine
   (z 794..806) and two sides of the Cliff Lofts chain-link (x 58..102, z 808..862).
   That rect is **scenic_dressing's padded keep-out**, not built content.
   Overflow's actual southernmost geometry is its lot at `(142.5, 695)` size 205×160,
   south edge **z 775**; the arena's south face is z 767. My nearest content is the
   boulevard at z 794 — **19 m of clearance**, and the Lofts fence is 33 m clear.
   Confirmed by reading `landmarks._overflow_fellowship()`, not inferred.

Explicitly verified clear: smoke corridor x[174,212] z[424,576] (my nearest geometry
is x 273); County General x 339..391 and its two access slabs at z 579/604 (my N-S leg
stops at x 285); the race channel's east levee rim x −530 (my west-most fence post is
x −498, 32 m clear); the suburb rect (z −880..−180); the freeway/frontage (|z| < 62);
the map containment wall at z 978 (my deepest collider reaches z 940).

## One thing the producer should know (not my file)
`scenic_dressing._open()` and `wild_dressing`'s equivalent have **no keep-out for
Cedar Cliff**. They can drop live-oak motts, yucca and prickly pear inside the
craftsman blocks and on the main street. 18 motts are scattered over the whole 2 km
map so the expected count here is ~1, and "the forest creeping in" is canon for this
region, so I left it — but if it lands in the boulevard it will read as a bug. The
one-line fix belongs in `scenic_dressing._open()` alongside the other reserves:

    if x + r > -510.0 and x - r < 110.0 and z + r > 630.0 and z - r < 950.0:
        return false                                        # Cedar Cliff

`wild_dressing`'s dirt two-track from (−495, 150) to (70, 880) crosses the district.
It is visual ruts with no collision, so it passes under the roads harmlessly.

## What is on the ground, and what it promises
**Juárez Boulevard** is the spine and it is the only thing in this district that is
also a piece of city infrastructure: it leaves the downtown grid at (279, 566), runs
south to z 800, turns west and runs 765 m to dead-end in Miss Earlene's horse lots.
That geography is the story — the boulevard that carries the developer's cars west is
the same boulevard that ends at the last six acres nobody has sold.

**Warmth, not satire (rule 3).** 45 craftsman bungalows, every one with a porch deep
enough to sit on and 1-2 chairs already in it; a third have a picket fence, a third
have a tree in the yard; six warm house paints with white trim. 14 storefronts on a
100 m commercial heart — brick, parapet, cloth awning, glass ground floor, a painted
sign band. Papel picado over the street. A paletería cart with the umbrella up. Nine
veladoras in the botánica window. A hand-lettered menu on the taquería wall. Three
murals on blank side walls — a sun, a horse, a saint's arch — flat panels with a
two-tone motif, the way a neighbourhood mural reads from a moving car.

**The satire, all of it, in one corner.** At the boulevard's east end: a fenced empty
lot, a half-demolished house with one gable wall still standing, an 8 × 4 m hoarding
reading COMING SOON / THE CLIFF LOFTS over FROM THE $700s · A PIONEER VISION
DEVELOPMENT, and a leaning bandit sign on a pole — WE BUY / HOUSES CASH /
214-555-0199. Plus one chalkboard: OAT MILK +$1.50. Nothing else in the district is
a joke, and nobody who lives here is one.

**Interactivity promise (the doors that could open):**
- Teatro Estrella: four door panels, a recessed lobby, a ticket booth with a glazed
  window and TAQUILLA over it, and a marquee whose copy is one string —
  `HOY · CINE · LUCHA · QUINCEAÑERA SÁBADO` — a mission can rewrite.
- Gilead Bottoms: a **gate standing open** on two posts in the south lot's north
  fence, yawed −0.62 rad. It is a hinge with a story on it; closing it is a beat.
- The Cliff Lofts lot is fenced on four runs of chain-link **with colliders** — a
  boundary a car feels, and a lot a mission can breach.
- The church's monument sign carries the service time; the barn has a 3.6 × 4.2 m
  door panel on its road-facing gable.
- 14 storefront bays each have a glass ground floor on `SHD.storefront_glass(true)`
  (interior mapping — lit rooms behind the pane) and a door trim panel.

**Skyline / navigability.** The blade sign is the landmark: 9.5 m of vertical
letter-stacked TEATRO ESTRELLA on both faces, top at y 18.5, over a 15 m marquee with
19 emissive bulbs on its lip. It is the tallest thing for 500 m in every direction and
it is the thing you say when you say "turn at the Teatro". Second silhouette: the
church steeple, spire top y 15.0, cross to 16.1 — deliberately small, because the
contrast with Overflow's arena 40 m north-east is the entire point and it is made with
massing, not with a line of copy.

**Material language, distinct from every other district.** Storefronts use the city's
triplanar `brick_material` with `vertex_color_use_as_albedo` on, tinted per instance
(brick red / cream / teal / mustard) — one bake, four colours. Houses use a new
procedural **lap-siding** triplanar built in this file: a 2.56 m tile of 160 mm boards
with a shadow line under each lap, instance-tinted. Neither reads like downtown's
curtain wall, Stonebridle's brick, or Harvest Hills' wrap.

## REQUEST 1 — registration in EXTRA_LAYERS
Insert in `greybox_city.EXTRA_LAYERS` **before** `landmarks.gd` (and, as always,
before `downtown_types.gd`, which must stay last):

    "res://scripts/world/cedar_cliff.gd",   # D-0xx: Cedar Cliff & the Deacon Arts
                                            # District, south-west off Juárez Blvd
The layer reads only `city.get("mat_asphalt")` and `city.get("mat_concrete")`. It
records nothing, publishes nothing, and no other layer reads it.

## REQUEST 2 — atlas entries (docs/design/world-atlas.md + data/world/atlas.json)

### district
    {
      "id": "cliff",
      "name": "CEDAR CLIFF",
      "rect": [-500, 640, 600, 300],
      "fill": "4a3f33",
      "label": [-498, 638],
      "note": "The Cliff. Craftsman blocks off Juárez Boulevard, the Deacon Arts
               storefronts and Teatro Estrella at its heart, Gilead Bottoms' horse
               lots where the boulevard dead-ends at the floodway. The Cliff Lofts
               hoarding on the fenced lot at the east end is the frontier."
    }

### places
    { "name": "Teatro Estrella",  "aka": "HOY · CINE · LUCHA", "pos": [-100, 783],
      "kind": "theatre" }
    { "name": "Deacon Arts District", "aka": "Juárez Blvd storefronts",
      "pos": [-155, 800], "kind": "district" }
    { "name": "Gilead Bottoms", "aka": "Earlene's — no trespassing no selling",
      "pos": [-455, 800], "kind": "ranch" }
    { "name": "Cedar Cliff park", "pos": [-190, 870], "kind": "park" }
    { "name": "Iglesia Bautista del Cliff", "pos": [-347, 770], "kind": "church" }
    { "name": "The Cliff Lofts site", "aka": "COMING SOON", "pos": [80, 835],
      "kind": "development" }

### roads — exact built coordinates
    { "class": "street", "name": "Juárez Boulevard",
      "pts": [[279, 566], [279, 800], [-480, 800]] }
    { "class": "street", "pts": [[-300, 700], [-300, 940]] }
    { "class": "street", "pts": [[-80, 700], [-80, 940]] }
    { "class": "street", "pts": [[-480, 900], [100, 900]] }
Widths as built: Juárez Boulevard 12 m, the three side/back streets 8 m, all asphalt
with the slab top at +0.02. Register **Juárez Boulevard** in naming-bible §4 as a
built road name (it is already ratified in §3/§6 as the boulevard's name; §4 is the
road register that Fair Drive and Pioneer Vision Parkway went into).

### "still prairie" table
The south-west row — `−530, 576 → 650 × 400` — is now built. Move it out of §2 and
into the §1 region table as `cliff`.

## REQUEST 3 — two plate vantages for zz_shot.gd
Both are 1600×900, eye height chosen so the boulevard reads as a street and not as a
plan. Neither looks into the sun at the default time of day.

1. `cliff_blvd` — the main street, looking **west** down Juárez Boulevard from just
   past the side street, with the Teatro blade on the right, papel picado overhead
   and the storefront rows converging.
       pos     = Vector3(-62.0, 6.5, 800.0)
       look_at = Vector3(-260.0, 5.0, 800.0)
   What it must show: the blade sign top (y 18.5) inside frame, both storefront rows,
   at least three papel-picado strings, the awnings, the sun mural on the taquería's
   west wall at the far end.

2. `cliff_gilead` — Gilead Bottoms from the boulevard's dead end, looking **north-east**
   across the rail fences with the barn, the horses and the sign in frame, and the
   Cliff's roofline behind them.
       pos     = Vector3(-492.0, 4.2, 838.0)
       look_at = Vector3(-430.0, 2.0, 762.0)
   What it must show: the GILEAD BOTTOMS · EARLENE'S sign, both horses, the open
   gate, the barn's red gable, the three-rail fence line, and — the point of the
   composition — the boulevard running out of the frame toward the district.

A third, if there is budget: `cliff_lofts` at `pos Vector3(46.0, 5.0, 788.0)`,
`look_at Vector3(84.0, 4.0, 824.0)` — the hoarding over the chain-link with the
half-demolished house behind it. That is the one shot that carries the satire.

## REQUEST 4 — names used that are NOT yet in the naming bible
Every one of these is built as **generic-descriptive or canon-derived signage**, not
as invented canon, and every one is one string in one `_label()` call — trivial to
change on ratification. Listing them for the World Builder:

| On the sign | Status | Note |
|---|---|---|
| TEATRO ESTRELLA | **canon** §6 | on Juárez Boulevard, as ratified |
| GILEAD BOTTOMS · EARLENE'S | **canon** §3 | Miss Earlene Reyes, six acres |
| MERCADO REYES | canon surname, new business | Book's family; kept modest on purpose |
| A PIONEER VISION DEVELOPMENT | **canon** (Harvest Hills, D-066) | the developer |
| THE CLIFF LOFTS | **new** | needs ratification; the gentrification product name |
| DEACON ARTS COFFEE | **new** | the new arrival on the Deacon Arts strip |
| CLIFF RECORDS / CLIFF CUTS | **new** | both use the ratified vernacular "the Cliff" |
| IGLESIA BAUTISTA DEL CLIFF | **new** | the small church; same vernacular |
| TAQUERÍA LA ESTRELLA, BOTÁNICA SAN JUDAS, PALETERÍA MICHOACANA, LAVANDERÍA, CARNICERÍA HERMANOS, EL PATIO BAR, FARMACIA, ZAPATERÍA, PANADERÍA | generic trade words | Spanish common nouns and one saint's name — no real business is referenced, so nothing here needs a canon entry unless the bible wants them listed |
| PARQUE · CLOSES AT DUSK · NO GLASS | deliberately generic | **the park has no canon name.** I shipped a municipal plaque with no proper noun rather than invent one. If the World Builder ratifies a name, it goes on this one label. |
| 214-555-0199 | fictional-number convention | on the bandit sign |

Nothing verbatim, no real person, no real business (rules 1 and 2 hold).

## Deviation to declare
The brief said Godot only as `parse_all.gd`. I also ran a **throwaway headless
`--script` probe** (`game/tools/zz_cc_probe.gd`, created and deleted in the same
turn, under `perl -e 'alarm 90'`, one process at a time, never windowed) three times:
once to confirm the layer builds without runtime errors and carries no empty AABB,
once with `-- --signaudit` to prove the 31 labels fit their boards, and once to run
the collider clearance test above. `parse_all` alone cannot see any of those. The
file is gone; `git status` shows `cedar_cliff.gd` as the only addition under `game/`
and no modification of any file I do not own. Final gates after cleanup:
`PARSE: 93 scripts, 0 failed` and `gdlint: Success: no problems found`.
