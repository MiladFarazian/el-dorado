# The atlas and two districts — 2026-09-13 (D-066)

Milad: *"Let's detail the world more so we can then improve the map."* His screenshot of the pause
map (18:00, not filed) showed three names — STONEBRIDLE, DORADO, THREEFORK — five gold numbers and
a freeway line on a 2 km square.

- `map_after.png` — `godot -- --mapshot=PATH` at 1280×720: the map drawn from
  `data/world/atlas.json` (8 districts, 15 roads, 11 places), the job key from the session's list,
  a 500 m bar. Place names appear once the panel is large enough (Milad's window is ~2×); at this
  size the map shows district names and dots.
- `plates/fair_gate.png` — Fair Drive at 13:00: the Deco gate, the Lone Spur behind it, the
  midway's awnings. (Tall Tom stands 23 degrees left of this camera's axis and the sweep's field
  of view is ~36 degrees wide, which is how he was "missing" from the first plate — the boot line
  `TALL TOM: 17 m tall at (868, 1.35, 258)` said otherwise.)
- `plates/tall_tom.png` — his plinth from Fair Drive at 15:00.
- `plates/fair_wheel_night.png` — the concourse at 21:30: the wheel's bulbs and gondolas.
- `plates/harvest_edge.png` — Pioneer Vision Parkway at 17:30: the monument, the billboard,
  the sales trailer, framing-lumber houses on the horizon.
- `gate_quick.md`, `shot.log` — the gate on this tree; the 63-plate sweep's log (0 stalls,
  0 errors).

Layers: `world/fairgrounds.gd` (406 lines), `world/harvest_hills.gd` (395 lines); the map
`ui/city_map.gd`; the register `data/world/atlas.json` + `docs/design/world-atlas.md`.
