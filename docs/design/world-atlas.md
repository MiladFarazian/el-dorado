# The World Atlas — what is actually built, and where (D-066, 2026-09-13)

Milad: *"Let's detail the world more so we can then improve the map."*

The Megaplex of `map-concept.md` is twelve regions across a county. What is BUILT is a 2 km × 2 km
slice of it (`greybox_city.MAP_HALF` = 1000; north is −z). This document and
`game/data/world/atlas.json` are the same fact in two forms: the JSON is what `ui/city_map.gd`
draws; this is what a designer reads. **A place that is built but not in the atlas is a canon
bug** (rule 1's cousin: one world, one register).

## 1. The slice, region by region

| Atlas id | Name on the map | World rect (x, z, w, d) | What is there | Canon region |
|---|---|---|---|---|
| `dorado` | DOWNTOWN DORADO | 120, 60 → 688 × 516 | 48 blocks on a 86 m pitch; 7 N–S streets (x 193…709), 6 E–W (z 133…563); Howdy Street is z 305; Cattleman's Trust Tower ("the Green Light", 165 m) on the block at (408, 262); the Candyland strip is the south row (z 477, x 300–780); the impound and Longhorn dispatch in the SE corner (709, 528–558) | 1 · Downtown Dorado |
| `stonebridle` | STONEBRIDLE RANCH | −600, −880 → 1300 × 700 | the gated-HOA archetype: brick houses on a loose 95 × 80 m grid, roofs, pools, trampolines, porch and flood lights; the M20 infill | 7/8 · the north (the HOA satire) |
| `threefork` | THREEFORK FLOODWAY | −710, 100 → 180 × 900 | the Big Empty: a 180 m concrete channel, 13° levees, graffiti registry, outfalls, the Floodway Sprint pad at (−620, 150) | 3 · Westbank & the Floodway |
| `gigastead` | GIGASTEAD | −352, 401 → 184 × 158 | Compute Ranch No. 7: three barns, stacks, Range Wardens, "ECONOMIC MIRACLE IN PROGRESS" | North corridor satire (data-center barns) |
| `overflow` | OVERFLOW CAMPUS | 40, 566 → 205 × 210 | Overflow Fellowship's flagship arena church, the parking ocean, Blessing One, the Second Collection board on the entry drive (142, 596) | 4 · south Dorado satellite |
| `middlington` | MIDDLINGTON | 500, 660 → 300 × 280 | Rustlers Stadium / Colt Bidwell Field (bowl centre 640, 782), the box office, the tailgate lots; the Middlington water tower stands apart at (−300, −140) | 11 · Middlington (this slice's fragment) |
| — | County General | (365, 612) | the hospital campus south of the grid on its own spur | 1 |
| `fairgrounds` | LONE STAR FAIRGROUNDS | 830, 100 → 160 × 330 | **new (D-066)**: the Deco gate at the end of Fair Drive (Howdy Street extended east), the Lone Spur wheel, Tall Tom, the midway's two rows of booths, the lots. Off-season — STATE FAIR OPENS SEPT 26 | 2 · Eastside |
| `harvest` | HARVEST HILLS™ | −980, −880 → 340 × 460 | **new (D-066)**: a Pioneer Vision Development — Pioneer Vision Parkway off the north frontage road, the monument sign, the billboard, mud roads, framing-lumber houses, wrapped houses, bare slabs, five model homes, the sales trailer | 8 · the frontier (the slab-farm satire) |

**The freeway** is I-3 (z 0, x ±800, deck at 9 m) with frontage roads at z ±30 and ramps at |x|
517–582. Traffic drives the downtown grid and the frontage roads only. Three dirt two-tracks cross
the prairie (`wild_dressing`).

## 2. Still prairie (and what canon says goes there)

| Where | Rect | The candidate, by the map concept |
|---|---|---|
| East, south of the fairgrounds | 830, 430 → 160 × 500 | Deep Elm (brick + murals under the Overhead) — needs an elevated road first |
| South-west | −530, 576 → 650 × 400 | Cedar Cliff / Deacon Arts: craftsman blocks, Juárez Boulevard, Teatro Estrella; Gilead Bottoms' horse lots at the floodway's edge |
| South, beyond the church and the hospital | 120, 800 → 400 × 200 | the Threefork Bottoms treeline (forest edge, no buildings) |
| West of the channel | −1000, 100 → 290 × 900 | Westbank: warehouses, the motel strip, Darlin' Field's fence line |
| North of Stonebridle | −600, −1000 → 1300 × 120 | the prairie fade; the Dam Store, Exit 47 belongs on a frontage road, not here |
| North-east | 700, −880 → 300 × 850 | Hyland Glen (mansions, private cops) or Grand Emporia (the mall + the Valley Vista rubble) |

## 3. Rules

1. Every layer that adds a nameable place registers it in `atlas.json` (`places`) and, if it owns
   ground, as a district. The map reads the file; nothing on the map is typed twice.
2. Roads that are not the downtown grid are listed in `roads` with a class: `freeway`, `frontage`,
   `ramp`, `street`, `strip`, `dirt`. The grid stays in `city_dressing.NS_X / EW_Z`.
3. New road names go in the naming bible §4 (Fair Drive, Pioneer Vision Parkway registered 2026-09-13).
4. Layers follow house law: visual-only, a literal seed, MultiMeshes with `custom_aabb`, nothing in
   the smoke corridor, colliders only on masses a car must not pass through.
