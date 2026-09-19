# The loop — 2026-09-18 (D-068)

Milad: *"I need more progress and a faster rate, so much work still needs to be done to get this
game anywhere close to something people actually would want to play."*

- `mech_probe.log` — 79/79. Stage 11: the app pushes an order (after clearing the one the loop
  had already pushed on its own), the target is towable and rings on the radar, the debtor comes
  out, hook, haul, deliver (+$675 on a pickup hauled 547 m), the RECOVERED card; a bad-paper
  order pushed, walked away from: respect +3, paper burned. Stage 12: a note on the Brisket
  ($0 down), the first $392 draft, broke, two returned drafts, LONGHORN recovers the Brisket and
  leaves the wrecker; the sedan bought for cash. Zero script errors (two 4.7 freed-instance casts
  in pedestrians.gd were found and guarded on the way — probe4.log has 284 of them).
- `plates/boone_lot.png`, `plates/cliff_boulevard.png`, `plates/gilead_bottoms.png` — the three
  new vantages; `plates/map.png` — the pause map with Boone Trucks and Cedar Cliff on it.
- `gate_quick.md`, `shot.log` — the gate and the 66-plate sweep on this tree. (The first sweep's
  `gilead_bottoms` plate was the pause menu: it opened for one vantage and closed again, with no
  code path that does so on its own — a keypress into the focused window is the likely cause. The
  plate filed is from a second sweep.)
- `builders/` — the three builders' findings files (orders, dealer, cliff): the tunables, the
  peer calls, the judgement calls, what could not be verified without a boot.

Not measured: perf (the machine was never quiet); the balance hypotheses in
`builders/orders_findings.md` are numbers to playtest against, not rulings.
