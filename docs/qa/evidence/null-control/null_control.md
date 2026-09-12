# Null control — 2026-09-12 (two identical --shot sweeps, load average ~8, D-055)

Plates: game/.gate/null/A and /B (machine-local). Pass B to plates_diff.py --null. Regenerate after any change to traffic, spawning, or the sweep.

`/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/tool9/null/A` → `/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/tool9/null/B`

| vantage | meanAbs | px>16 | null px>16 | flag |
|---|---:|---:|---:|---|
| aerial | 1.10 | 10137 |  | CHANGED |
| back | 1.24 | 18027 |  | CHANGED |
| billboard | 0.90 | 8414 |  | CHANGED |
| car_34 | 1.85 | 31100 |  | CHANGED |
| car_rear34 | 1.63 | 28374 |  | CHANGED |
| car_side | 2.30 | 39855 |  | CHANGED |
| car_wheel | 2.04 | 33031 |  | CHANGED |
| face | 1.02 | 16503 |  | CHANGED |
| floodway | 0.77 | 2967 |  |  |
| freeway_deck | 0.89 | 7556 |  | CHANGED |
| freeway_night | 0.89 | 3306 |  |  |
| frontage_signs | 0.94 | 3279 |  |  |
| hero_pickup | 1.20 | 20841 |  | CHANGED |
| hero_police | 1.95 | 35680 |  | CHANGED |
| hero_slab | 1.51 | 25442 |  | CHANGED |
| hero_wrecker | 1.43 | 28153 |  | CHANGED |
| hospital | 0.59 | 4324 |  | CHANGED |
| hospital_night | 1.10 | 6367 |  | CHANGED |
| landmark_church | 0.77 | 11511 |  | CHANGED |
| landmark_stadium | 0.53 | 3587 |  |  |
| plaza | 0.93 | 2678 |  |  |
| portrait | 0.87 | 11569 |  | CHANGED |
| sg_blade | 0.93 | 6415 |  | CHANGED |
| sg_candyland | 0.45 | 1192 |  |  |
| sg_clingtel | 0.81 | 5244 |  | CHANGED |
| sg_clingtel_night | 0.80 | 1867 |  |  |
| sg_gantry | 0.67 | 6082 |  | CHANGED |
| sg_ghost | 0.78 | 3201 |  |  |
| sg_gigagate | 0.70 | 9680 |  | CHANGED |
| sg_gigastead | 0.29 | 2085 |  |  |
| sg_hosp_drive | 0.65 | 10255 |  | CHANGED |
| sg_hosp_road | 0.67 | 5254 |  | CHANGED |
| sg_hosp_stack | 1.39 | 26302 |  | CHANGED |
| sg_howdy | 1.48 | 21628 |  | CHANGED |
| sg_marquee | 0.82 | 4713 |  | CHANGED |
| sg_payhut | 2.62 | 52806 |  | CHANGED |
| sg_rooftops | 0.33 | 1603 |  |  |
| sg_rooftops_night | 0.31 | 1446 |  |  |
| sg_storefront | 0.71 | 5896 |  | CHANGED |
| sg_trust | 0.42 | 2021 |  |  |
| sg_trust_night | 0.34 | 2129 |  |  |
| sg_watertower | 0.72 | 11487 |  | CHANGED |
| showcase_cars | 1.12 | 18246 |  | CHANGED |
| showcase_people | 0.76 | 11368 |  | CHANGED |
| side | 1.29 | 21686 |  | CHANGED |
| sky_night | 0.79 | 3973 |  |  |
| sky_wide | 0.79 | 6129 |  | CHANGED |
| skyline_from_freeway | 1.17 | 9513 |  | CHANGED |
| skyline_night | 0.41 | 6405 |  | CHANGED |
| slab_34 | 2.52 | 48699 |  | CHANGED |
| slab_rear | 0.80 | 12502 |  | CHANGED |
| slab_side | 2.16 | 42144 |  | CHANGED |
| street_detail | 0.97 | 10993 |  | CHANGED |
| street_night | 2.32 | 35015 |  | CHANGED |
| street_north | 2.24 | 5961 |  | CHANGED |
| suburb_night | 0.48 | 908 |  |  |
| suburb_street | 0.77 | 19098 |  | CHANGED |
| torso | 0.77 | 13239 |  | CHANGED |
| trust_tower | 1.39 | 1454 |  |  |

PLATES: 59 vantages, 801340 changed pixels total (noise floor ~11-12k/59), 43 flagged: aerial, back, billboard, car_34, car_rear34, car_side, car_wheel, face, freeway_deck, hero_pickup, hero_police, hero_slab, hero_wrecker, hospital, hospital_night, landmark_church, portrait, sg_blade, sg_clingtel, sg_gantry, sg_gigagate, sg_hosp_drive, sg_hosp_road, sg_hosp_stack, sg_howdy, sg_marquee, sg_payhut, sg_storefront, sg_watertower, showcase_cars, showcase_people, side, sky_wide, skyline_from_freeway, skyline_night, slab_34, slab_rear, slab_side, street_detail, street_night, street_north, suburb_street, torso
