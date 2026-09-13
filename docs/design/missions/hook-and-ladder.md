# HOOK AND LADDER

**Mission 1 · Act 1, the tutorial repo.** Implementation: `game/scripts/systems/mission_hook_and_ladder.gd`.
Status: **built and playable end to end**; the probe (`--mech-probe` stage 9) runs it in one breath.

## Beat served

The first job. A man taking a thing from a person, in daylight, in a subdivision, with the
subdivision watching. The HOA drone is the joke and the lesson: Porchlight posts the clip, the
clip becomes a star. Nothing about the paperwork is wrong. That is the point the whole game will
make later; here it is only a feeling.

## Setup — the diegetic hook

No cutscene. A lit pole sign, **LONGHORN DISPATCH**, 30 m north of the impound pad. Roll in under
3 m/s and the order takes itself. The LONGHORN app speaks (D-063) — Bolo Capital bought Longhorn
and "installed quotas and an app" (story bible), so the dispatcher is a push notification:

> ORDER 3319 · BARON BRISKET · 96-month note, four payments behind. STONEBRIDLE RANCH, the
> cul-de-sac. Recovery window 6:00. Your rating: 4.7★
> HOA cameras on file. Longhorn Wrecker & Recovery is not liable for what Porchlight posts.

## Objective chain

1. **Drive to Stonebridle Ranch** (~900 m; the target is a gold ring on the radar, the route is on
   the map). Inside 35 m: *"Unit located. Back to the tailgate and hook. Do not engage the debtor."*
2. **Hook the Brisket.** The moment the chain goes taut, two things happen: the Porchlight drone
   rises out of the court and starts filming (11 s in view = a clip posted = +1 heat, and it keeps
   filming), and **the owner comes out of the house** — a walker who goes to the truck and stands at
   arm's length: *"That's my truck! I'm four days late, not four months — who told you four
   months?!"* Stay within 20 m of her for 14 s and she calls it in (+1 heat, "THE OWNER CALLED IT
   IN"). Leave, and she gives up at 40 m.
3. **Deliver to Longhorn Impound** (the pad; ~900 m back). The drone loses signal past 120 m.

## Ending

Release on the pad → the **contract card**: RECOVERY $600, and the bonuses that landed —
NO CLIPS POSTED +$150, INSIDE THE WINDOW (≤ 6:00) +$100, NO HEAT DRAWN +$100 — the time, the
total, and a medal (GOLD under 4:00 with no clips; SILVER under 6:00; BRONZE). The app signs off:
*"Recovery logged. Payout net of platform fee (0% this quarter). Bolo Capital thanks you for your hustle."*

## Failing forward

- Lapse (20 s beyond 600 m after the first approach): *"Order 3319 reassigned. Recovery window
  exceeded. Rating impact: −0.3★"* — the board re-arms at once.
- Busted mid-contract: *"A Longhorn unit in the county impound is a Longhorn problem."*
- Down mid-contract: *"Get well soon."* Heat earned stays earned.

## Tunables

`ORDER_NO`, `OWNER_CALL_SECONDS` 14, `OWNER_RANGE` 20, `BONUS_*`, `TIME_GOLD` 240, `TIME_SILVER` 360,
`EXPOSURE_SECONDS` 11, `PAYOUT` 600, `COOLDOWN_SECONDS` 30 — all at the top of the file.
