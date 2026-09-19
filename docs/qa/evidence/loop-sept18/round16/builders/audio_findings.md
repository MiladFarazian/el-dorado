# LOOP AUDIO — findings

Files owned and written:
- /Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/systems/loop_audio.gd (621 lines)
- /Users/miladfarazian/Documents/Projects/gta_clone/game/data/mechanics/loop_audio.json

Gates: `parse_all.gd` -> PARSE: 95 scripts, 0 failed. `gdlint loop_audio.gd` -> Success: no problems found.

## Cue table (measured on a Python mirror of the synthesis, scratchpad/loop16/mirror.py)

| cue | what it is | samples | sec | level dB | peak dBFS | RMS dBFS |
|---|---|---|---|---|---|---|
| push | A5 -> E6 (perfect fifth), soft square+sine, decay 11/9 | 7717 | 0.35 | -12 | -17.19 | -27.3 |
| push_bad | same, second note 1 semitone flat = A5 -> Eb6 TRITONE | 7717 | 0.35 | -12 | -17.19 | -27.6 |
| delivered | 60 ms register chink + E5-B5-E6 rise, odd-harmonic table | 15434 | 0.70 | -8 | -12.44 | -26.7 |
| voided | 120 -> 52 Hz phase-accumulated thud + lowpassed noise body | 9922 | 0.45 | -10 | -15.19 | -29.3 |
| expired | push REVERSED (E6 -> A5), 420-sample attack, one-pole LP k=0.25 | 9922 | 0.45 | -14 | -20.94 | -32.3 |
| run | 58 -> 186 Hz crank sweep + 6-tap MA tyre chirp at 0.30 | 13230 | 0.60 | -13 | -18.19 | -27.0 |
| bell | 660 Hz, 4 inharmonic partials (1/2.76/5.40/8.93), per-partial decay | 35280 | 1.60 | -11 | -16.19 | -33.0 |
| chain | 9 x 12 Hz HP noise slaps over 0.8 s, then the push notes verbatim | 25357 | 1.15 | -12 | -17.19 | -31.7 |
| coin | C7+G7 ping + a bounce at 90 ms, odd-harmonic table | 6174 | 0.28 | -13 | -19.94 | -36.7 |
| buzz | clipped 110 Hz square, FLAT envelope, 20 ms edge ramps | 6615 | 0.30 | -15 | -25.46 | -26.5 |
| rankup | G4-B4-D5-G5, saw-ish detuned, 150 ms apart | 19845 | 0.90 | -10 | -15.19 | -28.9 |

Total 157,111 samples = 7.13 s of audio, 314 KB of PCM, built once in setup.

## Two mix bugs the measurement caught
1. **buzz was 7 dB louder than the payoff.** Normalised to the family peak 0.55 it measured
   RMS 0.486 vs delivered's 0.116 — a flat envelope and a decaying one at equal PEAK are not
   at equal LOUDNESS. Held to peak 0.30 and level -15; RMS now -26.5 against delivered's -26.7.
2. **run outran delivered.** -10 dB put it at -24.0 RMS, 2.7 dB over the loop's one payoff.
   Dropped to -13. `delivered` is now the top of the peak column and level with buzz on RMS.

All eleven buffers verified non-silent, DC |offset| <= 0.002, no clipping (normalize is two-way:
`expired` measured raw 0.44 and is scaled UP to 0.45).

## Peers
- `repo_orders.order_pushed(bad: bool)` -> push / push_bad
- `repo_orders.order_closed(outcome: String)` -> delivered / voided / expired (else-branch = expired)
- `repo_orders.state` POLLED each physics tick, == 3 (State.FLEEING) -> run
- `repo_orders.rank` POLLED each physics tick, on increment -> rankup
- `dealer.vehicle_granted(path)` -> bell; `dealer.vehicle_repossessed(path)` -> chain
- `dealer.notes` POLLED at 1 Hz, per-path `paid`/`missed` baselines -> coin / buzz

## Objects
Setup: 11 AudioStreamWAV + 2 AudioStreamPlayer. Quit: `_exit_tree` stops both players, nulls
both `stream` refs and clears `_streams`; the WAVs are RefCounted, so the expected net
contribution to the D-023/D-106 audio-at-quit count is 0. NOT VERIFIED — a boot was out of scope.

## Not verifiable without a boot
- the actual leaked-object count at quit
- that the first-tick wiring finds repo_orders (it sorts AFTER loop_audio in `_load_systems`)
- what any of it sounds like
