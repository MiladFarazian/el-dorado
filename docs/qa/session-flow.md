# Session flow — 2026-09-06

User direction: “The whole experience: make it feel like a game.”

The live build had driving, combat, car theft and missions, but opened directly
into a moving simulation without a pause screen or full map. Escape only released
the mouse. The HUD promoted incidental repo work during scripted missions. This
pass connects the existing systems into a navigable session.

Implemented:

- Opening screen with the first dispatch selected; keyboard-focusable entry.
- Escape / M pauses physics and mission clocks, releases the mouse, and opens
  an activity map and persistent controls. Resume restores visible HUD layers.
- Five destinations from actual mission/world coordinates; map clicks set custom
  waypoints, right click clears them. Selecting a location does not teleport the
  player, pay out a mission or bypass its activation rules.
- Downtown AStar street routes, with updates at 2 Hz and display on radar/map.
  Outside the mapped street network only the destination bearing is shown.
- Scripted mission pickup/delivery navigation takes precedence over waypoints;
  incidental repo instructions yield during scripted jobs.
- Opening the menu closes the weapon wheel and releases its slow-motion effect.
  Rendering is capped at 30 fps in menus and restored on resume.
- UI scales with the window. Default window is 1280×720 with a 1600×900 UI canvas.

Verification command:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tools/session_test.gd -- --session-test
```

The integration harness checks actual paused vehicle transforms and playtime,
HUD restoration, keyboard focus, mission target/delivery transitions, street
route geometry, unmapped route fallback, weapon-wheel cleanup, and vehicle
entry/exit after pausing. `--session-test` disables save I/O so tests do not
modify player progress. Windowed screenshots can be captured by adding
`--session-capture=/absolute/path.png` and omitting `--headless`.

Limitations: this is a session/playability pass, not an art-quality signoff.
Procedural character/vehicle/environment art remains prototype quality. GPS
covers downtown streets and the hospital spur; the broader map uses bearings.
Existing saves retain economy/race records, not the player's location or an
in-progress mission. No claim is made that the full GTA-quality bar is met.

Final evidence in `evidence/session-flow/`:

- `integration.log`: 34 checks passed, zero failures or error lines.
- `boot.log`: 900-frame boot, zero error lines; the already documented six-object
  Godot shutdown leak warning is present.
- `smoke-1.log` / `smoke-2.log`: identical expected driving result:
  `SMOKE PASS | pos=(193.000000, 1.097957, 517.465332) moved=40.5m speed=16.7m/s`.
- `opening.png`: rendered opening screen with dispatch selected and street route.
  Windowed integration also passed before the final nearest-marker hit-test fix;
  that fix was then checked by the headless integration harness.
