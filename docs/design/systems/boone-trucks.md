# Boone Trucks — "Appreciate You!" (D-068, 2026-09-18)

Wade "The Bullet" Boone's lot on the north frontage of I-3: 96-month notes, $0 down, your
signature is your credit. The first money sink in the game, and the theme literalised: buy a
truck on paper you can't carry, miss two drafts, and LONGHORN WRECKER & RECOVERY recovers it.
We own that too.

## The lot
x −180..−40, z −110..−44 with a drive to the frontage band at x −110. A showroom with a glass
front, a 14 m pylon (BOONE TRUCKS / APPRECIATE YOU! / 96 MONTHS · $0 DOWN · YOUR SIGNATURE IS
YOUR CREDIT), pennant strings, lot lights, and the stock on display: the Baron Brisket
($28,700), the sedan ($14,900), the Candyland Slab ($39,900).

## Buying
Walk up to a display rig. **G** signs the note: $0 down, a monthly draft of price × 1.31 / 96
for 96 in-game days (a day is 600 s). **Hold G** pays cash. The rig is yours: TAB cycles the
rigs you OWN now (the wrecker is always Book's; the dev tools still cycle every profile).
Wade speaks — pitchman warmth with the cracks showing.

## The note
Once an in-game day, BOONE FINANCIAL drafts. Short of money → "draft returned. That's one."
Two misses → the rig is recovered when Book is out of it and 30 m away (or at once if he is in
another): LONGHORN says so, the wrecker is left in its place, the note voids, the stock goes
back on the lot. 96 drafts → TITLE CLEAR.

## What it is built from
`systems/dealer.gd` + `data/mechanics/dealer.json`; `main.owned_paths` with `grant_vehicle` /
`revoke_vehicle`; persisted by `save_load` (owned, notes). The atlas has the lot; the radar a `$`.

## Open
No trade-ins; no upgrades; no Wade in person (a voice for now); the repossession is a swap, not a
LONGHORN order you could watch — the loop's own orders should someday come for your own truck.
