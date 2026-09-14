# COMIN' DOWN

**Mission 3 · Act 1, the Slow Lane.** Implementation: `game/scripts/systems/mission_comin_down.gd`.
Status: **built and playable end to end**; the probe (`--mech-probe` stage 10) runs its state
machine with the night shortened to one pass. Story bible §7 #4: *"earn Candyland respect in a
reverse-race: a slab cruise where speed loses points, ending in a takeover as the Street Racing
Task Force escalates tier by tier."*

## Beat served

The strip inverts the genre: a driving mission that rewards patience. Book is not the fastest
thing on the road here; he is the slowest thing on purpose, with the law on his bumper, and the
respect he earns is the community's, not the game's. Canon rule 3 in one job: Candyland C.C. is
rendered with warmth — the club talks, the club tips, nobody on the strip is the joke. The Task
Force is.

## Setup — the diegetic hook

A lit candy-magenta pole sign, **CANDYLAND C.C.**, south of the strip's west gate. Roll up slow
**in the Candyland Slab** (TAB runs through your rigs; in anything else the club says *"Nice
truck. Come back in the slab."*). The club speaks through the mission kit as CANDYLAND C.C.:

> Comin' down. Three passes, gate to gate, trunk up, elbows out. Keep it under thirty — speed
> loses here. The Task Force will show. They ride your bumper; you don't ride the gas.

## Objective chain

1. **Three passes, gate to gate** (x 312 ↔ 768 on the strip, z 464–490), under 13 m/s (~29 mph).
   Going over is a BREAK — it costs respect and the medal, never the mission (*"Speed loses.
   Bring it down."*). Leave the strip for 20 s and the night is over. Each pass lights a star
   ("STREET RACING TASK FORCE"): at one and two stars the cruisers **tail** a slow driver (D-064:
   police falls in 7 m behind a driver under 8 m/s and matches speed instead of ramming), at
   three they hunt. The club calls each pass.
2. **The takeover.** Park on the lot south-west of the west gate, trunk up.
3. **Slide out.** *"Slow is done — now you drive."* The mission completes when the law loses you.

## Ending

The card: PASSES, BREAKS, TASK FORCE TIER, RESPECT (+4 per pass, +1 per strip tick, −2 per
break), THE CLUB'S THANKS $250, TIME; GOLD with no breaks, SILVER with two or fewer.
*"Candyland remembers. Come down again when the sun's gone."* (Night doubles the strip's ticks —
that is `slab_cruise`'s rule, and it makes the night the better time to come down.)

## Failing forward

Out of the slab mid-cruise, off the strip for 20 s, busted or down: a line, the board re-arms.
Heat earned stays earned.
