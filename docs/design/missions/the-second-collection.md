# THE SECOND COLLECTION

**Mission 2 · Act 1, late.** Implementation: `game/scripts/systems/mission_second_collection.gd`.
Status: **built and playable end to end** (M18). Companion to M3's *Hook and Ladder*.

The title is the whole joke twice: a church takes a second collection, and so does
the collections department. Book is the second collection.

---

## Beat served

The hinge at the end of Act 1, where the day job stops being about neighbors and
starts being about institutions. *Hook and Ladder* had Book pull a truck out of a
cul-de-sac while a drone livestreamed him to a subdivision — a man taking a thing
from a person. **The Second Collection is the first contract where the debtor is
bigger than he is, the paper is completely correct, and he still comes away
feeling like the villain.** That gap is the whole game's thesis in one job:
extraction hides inside correct paperwork.

It also plants the reveal, per the story-direction graft "surface the
Voss/GigaStead pattern in systems before any cutscene states it": the note on this
car is held by a lender **Bolo Capital bought last quarter**, which means Longhorn
Wrecker is repossessing from a church on behalf of its own parent. Book doesn't
know that yet. The kiosk receipt says it, in eight-point type, and nobody reads
receipts.

Satire target is strictly institutional, per canon rule 3: the twelve campuses,
the jet, the giving app that works at 3 a.m., a $90,000 EV booked as "outreach."
**No worshipper appears in this mission, and the church is never staged as a
target of contempt — only its balance sheet is.** The campus is empty because it
is the middle of the night, and the emptiness is the point: nine hundred parking
spaces and one car in them.

---

## Setup — the diegetic hook

No cutscene. No phone call. A **night board** — a lit pole sign reading
`LONGHORN WRECKER — NIGHT BOARD / WE OWN THAT TOO` — stands at the mouth of
Overflow Fellowship's entry drive off the south street bed, where wreckers
already wait. Roll up slow (or walk up) and the order takes itself.

> **ORDER 4471: AMPT WEDGENEER — OVERFLOW FELLOWSHIP, NORTH PLAZA**

The board is 94 m from the car it's about. Longhorn doesn't stage its people far
from the work; it stages them where the debtor can see the truck.

---

## Objective chain (with the *why* attached)

1. **Get to the north plaza.** *Why:* the order is for a specific stall, not a
   specific car — Book has to see the plate, and the game has to show you the
   parking ocean before it asks you to cross it.
2. **Free the Wedgeneer.** It is booted and cabled to a fleet immobiliser
   pedestal. *Why:* this is the mission's actual decision, and it is a decision
   about what kind of repo man you are (below).
3. **Hook it.** *Why:* the Hook is the game. Requires the wrecker — jack a sedan
   and you are a guy in a sedan.
4. **Haul it to the impound.** ~580 m east along the street bed to the Longhorn
   pad. *Why:* the job isn't the theft, it's the delivery — and if you went loud,
   this is where the heat you bought comes to collect.

---

## Freedom axes

Three, and they compose. Every combination is a legal way to finish.

### Axis A — how the boot comes off (loud vs. quiet)

| | **The kiosk (quiet)** | **The pedestal (loud)** |
|---|---|---|
| Verb | On foot, walk to the doors, press G at the **SeedFaith giving kiosk** → *Fleet Services › Courtesy Release* | Shoot it, bat it, or drive through it at ≥6 m/s |
| Cost | Time, and crossing the plaza on foot | +2 heat immediately, campus **LOCKDOWN** |
| Reward | **CLEAN PAPER**: +$550 and +4 Respect | Base pay, +1 Respect, and a chase |
| Satire | The terminal that takes a tithe 24/7 will also print a lien release, because to whoever wrote the firmware both are menu items | An immobiliser is only as good as the thing it's bolted to |

The kiosk is the mission's ATM analogue and it tutorializes the interact verb
through fiction, not a prompt in a menu.

### Axis B — where you leave the truck (vehicle vs. foot)

Three **Watchman** masts sweep the plaza on fixed, learnable phases. Coverage is
what matters:

- **Drive onto the plaza**: all three masts reach you, and a vehicle exposes at
  ×1.5. You are made in about seven seconds. Fast, loud, viable.
- **Park in the parking ocean and walk in**: only one mast reaches that far, and
  its duty cycle loses to the decay outright. The rig is simply safe out there.
  This is the *reason* the parking ocean exists as playable space rather than
  scenery.
- **Crouched** (M16 crouch) cuts exposure to ×0.34 — a crouched man nets +0.2 per
  11.4-second revolution and can cross the plaza at will. Standing, he's made in
  roughly one revolution.

### Axis C — bought advantage (prep vs. improvise)

Each mast's **flood housing is a shootable frozen prop at 9.15 m**. Kill it and
that mast is dark for the rest of the contract — permanently reducing coverage,
which is exactly how you turn "walk in crouched" into "walk in standing." Costs
ammo, time, and a weapon that reaches (the bat does not go up nine metres).
Pistol/SMG/shotgun all work; the shotgun is a rumour at that range.

**If there were only one way through, this would be a corridor. There are at
minimum six distinct successful runs here**, and the payout distinguishes exactly
one thing: whether anybody woke up.

---

## Geography — "could this only happen HERE?"

Staged entirely on shipped landmark geometry (`scripts/world/landmarks.gd`),
the Overflow Fellowship flagship campus:

| Feature | Where | Use |
|---|---|---|
| Entry drive off the south street bed | x 128–156, z 565–641 | the night board, the approach |
| Entry plaza | x 118–166, z 638–704 | the sweeps, the crossing |
| Arena front + six glass door leafs | z ≈ 703 | the kiosk sits under the canopy |
| Reserved stall | (142, 690) | the Wedgeneer, 13 m off the glass |
| **Parking ocean**, two lots, ~900 painted stalls | x 46–112 and 198–242 | where you leave the rig |
| **Blessing One** on its pad | (60, 745) | the corner of every screenshot |
| The spire | (184, 714) | the skyline you tow away from |
| The impound pad | (709, 558) | the haul |

The "only here" test passes on the parking ocean alone: this is a mission whose
central stealth space is **a suburban megachurch lot at 2 a.m.**, an environment
that exists at this scale in the American Sun Belt and essentially nowhere else.
Nine hundred empty spaces, three security floods, and a private jet parked
where a hedge would be in any other country.

---

## Systems touched

| System | How |
|---|---|
| **The Hook** (`tow_hook`) | the payload verb; the car joins group `towable` only when the boot is off, so the hook physically refuses a locked car — legibility without UI |
| **Wanted level** (`police`) | +2 on the alarm, +1 each time a Watchman fills your meter. At heat ≥2 on foot, `foot_cops` deploys officers — a quiet run that goes wrong turns into a foot pursuit across the parking ocean |
| **Weapons** (`combat`) / **melee** | the pedestal and the three flood housings are frozen props: both a bullet and a bat thaw them, which is exactly how `combat._resolve_hit` and `melee._resolve_strike` already treat any frozen non-person |
| **Crouch** (M16) | reads the `is_crouched` meta; the single biggest lever on the stealth layer |
| **Interact** (G) | the SeedFaith kiosk, an ATM in a chasuble |
| **Radio** | story canon says jobs are soundtracked by the getaway vehicle's own dial. Deliver with the radio *on* → **+$75, "HAULIN' MUSIC."** Diegetic-only mission scoring, no score stem |
| **Economy + Respect** (`repo_board`) | one wallet, one Respect meter, paid through the public API |

---

## Payout

| Line | Amount | Condition |
|---|---|---|
| `ORDER 4471: THE SECOND COLLECTION` | **$1,100** | always |
| `CLEAN PAPER — NOBODY WOKE UP` | **+$550** | no alarm **and** never spotted |
| `HAULIN' MUSIC` | **+$75** | radio on at the drop |
| `OVERFLOW TOOK THE LOSS` | **+4 / +1 Respect** | clean / loud |

Best run $1,725 and 4 Respect; worst successful run $1,100 and 1 Respect plus a
wanted level. Roughly 3× a *Hook and Ladder* contract, which is the point — this
is a bigger debtor.

---

## Fail states — consequences, not game-overs

**Nothing in this mission fails you for being seen, being loud, or being wanted.**

| Event | Consequence |
|---|---|
| A Watchman fills your meter | +1 heat, meter resets, 6 s grace. **CLEAN PAPER is gone.** The contract continues. |
| Alarm (pedestal broken) | +2 heat, lockdown, sweeps speed up ×1.9 and reach +16 m. The contract continues. |
| Wanted at 3–4 stars during the haul | Nothing. Deliver it hot; that's a legal finish. |
| Tow chain snaps | Back to `HOOK_IT`, "RE-HOOK THE WEDGENEER". No progress lost. |
| Leave the campus >600 m for 20 s | **CONTRACT LAPSED** — props clear, night board re-arms *immediately* (no cooldown on a lapse) |
| Book dies | **ORDER 4471 GOES BACK ON THE BOARD** — the order lapses, the hospital handles the rest, re-accept whenever |
| Car falls out of the world | Silently re-parked in its stall |

**Checkpointing:** the contract is the checkpoint. There is no mid-mission save
state to lose and no re-do of a drive you already made — a lapse costs you the
trip back and nothing else. Completion puts the board on a 30 s cooldown and then
it re-arms, so the mission is fully replayable.

---

## The set piece

**Towing a gold-wrapped Wedgeneer backwards across nine hundred empty parking
spaces at two in the morning**, three floodlight fingers hunting across the paint
behind you, the spire lit on your left, and *Blessing One* sitting on its pad in
the corner of the frame with its name in gold on the flank.

If you went loud, the floods are pulsing red and there are cruisers coming up the
entry drive; if you went clean, the only sound is the chain.

---

## Cut-scene budget

**Zero.** Every line is an objective line, a flash, or a physical object:

- `LONGHORN WRECKER — NIGHT BOARD / WE OWN THAT TOO` (the sign)
- `OVERFLOW FLEET · CHARGE + IMMOBILISER / UNIT 3 · HOLD 4471` (the pedestal)
- `SEEDFAITH / GIVE 24/7 · TAP TO SOW` (the kiosk)
- `OVERFLOW FELLOWSHIP / OUTREACH FLEET · UNIT 3` (on the car's flanks)
- `IT'S BOOTED. PRINT A RELEASE AT THE KIOSK, OR BREAK THE PEDESTAL`
- `[G] SEEDFAITH KIOSK — FLEET SERVICES › COURTESY RELEASE`
- `RELEASE PRINTED. THE LORD PROVIDES A ROUTING NUMBER.`
- `LOCKDOWN — TWELVE CAMPUSES, ONE ALARM`
- `A WATCHMAN HAS YOU. SMILE, FRIEND.`
- `CLEAN PAPER — NOBODY WOKE UP`

---

## Naming — pending World Builder ratification

One new proper noun ships in this mission and needs a row in
`docs/design/naming-bible.md` §8 before it can be reused:

- **the Watchmen** — Overflow Fellowship's volunteer parking-and-security
  ministry; "Watchman masts" are the campus floods. Fits the existing
  ear-pieced-greeters faction layer from story canon (the people who arrive
  before police).

Everything else is already registered: **Overflow Fellowship**, **SeedFaith**,
**Ampt Motors / the Wedgeneer** (§7), **Longhorn Wrecker & Recovery** (§8),
**Bolo Capital**, **Blessing One**, **La Jefa 104.5**.

**One canon note:** the Wedgeneer ships here as a *mission prop*, not a drivable
profile, so §7a's "every drivable vehicle's canon name lives in its JSON" rule is
not yet engaged. If it ever becomes drivable it needs `data/vehicles/wedgeneer.json`
and a §7a row on the same day.

---

## Tuning notes for whoever balances this next

Every number is a named const at the top of the script. The three that actually
decide how the mission feels:

- `EXPOSE_DECAY` (0.20/s) — **the meter deliberately accumulates across sweep
  passes.** One pass of one mast lasts `2·SWEEP_HALF/SWEEP_RATE` = 1.53 s; if the
  meter reset between passes, no amount of standing in the open could ever get
  you caught. This was the first tuning error found in playtest instrumentation
  and it is the one to re-check if the stealth ever stops biting.
- `CROUCH_FACTOR` (0.34) — the difference between "the plaza is a wall" and "the
  plaza is a puzzle."
- `WATCH_RANGE` (46 m) — sets which masts reach the parking ocean, and therefore
  whether leaving the rig out there is actually the smart play. It currently is.

`SWEEP_HALF` (0.42 rad) and the spotlight's `spot_angle` (24°) are kept in sync on
purpose: **what you see is the rule.** Change one, change both.


---

## Presentation (D-063, 2026-09-13)

The LONGHORN app (Bolo Capital's push-notification voice, shared `mission_kit.gd`) now carries the
order: *"ORDER 4471 · AMPT WEDGENEER · Overflow Fellowship, north plaza, stall 9. Booted to a fleet
immobiliser. Lienholder of record: Bolo Capital (acquired Q2)."* — the reveal-planting line, said
out loud in eight-point type — then *"Quiet work pays better."* The quiet release and the alarm each
get a line. The contract ends on the card: RECOVERY $1,100, CLEAN PAPER +$550 if nobody woke up,
HAULIN' MUSIC +$75 with the radio on, RESPECT +4/+1, the total, GOLD for clean and SILVER for loud;
and the app's closing line: *"The receipt lists the lienholder in eight-point type. Nobody reads
receipts."* The night board is an **N** on the radar; a live target is a gold ring.
