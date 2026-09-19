# The Hook, endless — LONGHORN orders (D-068, 2026-09-18)

**Milad:** *"I need more progress and a faster rate, so much work still needs to be done to get this
game anywhere close to something people actually would want to play."*

The story direction is binding: *"The Hook and the Paper are non-negotiable — they ARE the game."*
Until this round the Hook was three scripted missions and a board of nine derelict junkers in
lots. This is the loop a player lives in between the missions — and it carries the Paper.

## The loop
1. **Quiet** (driving the wrecker, heat ≤ 1, no scripted job, nothing hooked) → after a gap the
   LONGHORN app **pushes an order**: a debtor's name, a vehicle, days past due, the amount, the
   quota count. Bolo Capital's push-notification voice; never a named dispatcher.
2. The **target** is a real parked vehicle at a curb 120–450 m away (a sedan or a pickup),
   towable, ringed on the radar. The objective line reads the order and the distance.
3. At 25 m the **debtor** comes out — a person with a name, who pleads, or calls it in (+1 star
   "THE OWNER CALLED IT IN"), or offers cash to look away, or fights.
4. **The choice.** G by the debtor: walk away (the order VOIDS — respect, rank progress −1) or, on
   an offer, take the cash (+$200, void, respect). Or hook it anyway.
5. **Deliver** on the impound pad → pay = base (sedan $300, pickup $450) × distance bonus × rank
   multiplier; the RECOVERED card; quota +1; rank progress.

## The Paper, v1
One order in five carries **bad paper**, and the push has a tell (LIEN HOLDER: LONGHORN DYNAMICS;
DAYS PAST DUE: 4 (system shows 94); NOTE ORIGINATED: yesterday; VIN: PENDING; ACCOUNT closed
2019; OWNER DECEASED). The debtor's line confirms it. Hook it anyway and LONGHORN pays the same,
the owner always calls it in, respect −3, `paper_taken` +1. Walk and it is `paper_burned` +1,
respect +3. Those two counters are the endings' meter (Take the Money / Burn the Paper) in daily
form, and they persist.

## Rank and quota
ROOKIE → HAND → DRIVER → CLOSER → PARTNER at 0 / 4 / 10 / 18 / 30 deliveries; the pay multiplier
1.0 → 1.6. Three a day is the quota; missing it costs nothing yet but the app remembers
("Yesterday's numbers are visible to the region.").

## What it is built from
`systems/repo_orders.gd` + `data/mechanics/repo_orders.json`. The target body is the stranded
car's recipe; the debtor is `pedestrians.spawn_follower_at` / `spawn_brawler_at`; the words go
through `mission_kit`; the pay through `repo_board.add_money`; the star through
`police.add_heat`. The junker board stands its beam down while an order is live. Persisted by
`save_load` (rank, deliveries, the paper counters, the quota).

## Open
The debtor who runs landed in D-070 (a FLEE reaction: the traffic brain drives the car, the
wrecker hooks it on the move, ×1.5 on delivery). Still open: no order on the player's own truck
(that is Boone Trucks' note); the phone (D-069) reads the paper now.
