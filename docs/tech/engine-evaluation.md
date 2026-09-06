# Engine Evaluation — Solo Dev + AI-Agent Pipeline

**Status:** Discovery-phase decision doc. **Date:** 2026-07-29. **Author role:** Technical director pass.
**Project:** Open-world crime/satire game set in a fictionalized DFW metroplex. One developer (Milad) + Claude-driven agents.
**Verified against mid-2026 versions and licensing (sources at bottom).**

**TL;DR:** Unreal 5.8 has the best GTA-shaped technology and the worst fit for an agent-driven solo pipeline (binary scenes, editor-bound loop). Unity 6.5 is the safe compromise. **Godot 4.6 is the recommendation** — text-first project format, headless CLI everything, MIT license, Jolt physics by default — paired with deliberate stylization, an OSM-derived DFW map skeleton, and a Blender-geometry-nodes building factory. A custom web stack iterates fastest of all but means building an engine instead of a game. Ambition is gated in three tiers (greybox slice: weeks; stylized vertical slice: months; systemic city: years) with a kill decision at each gate. Eight decisions are queued for Milad at the end.

---

## 1. The candidates, as of July 2026

### Unreal Engine 5.8
- **Current:** UE 5.8 shipped June 17, 2026 — the **final planned major UE5 release** (UE6 is next, converging with Fortnite/UEFN tooling). 5.7 (Nov 2025) made PCG production-ready and added Nanite Foliage + Substrate; 5.8 made MegaLights production-ready, added experimental Mesh Terrain, and integrated LLM-assisted editor workflows.
- **Relevant tech:** Nanite (virtualized geometry — city-scale detail without LOD authoring), Lumen (dynamic GI/reflections), World Partition (automatic grid-based open-world streaming with one-file-per-actor), Chaos Vehicles, Mass AI/MassEntity (crowd + traffic framework built for the *City Sample* — literally a free GTA-style city demo), MetaHuman (now in-engine, with crowd support in 5.8).
- **License:** Free until **$1M lifetime gross revenue per title**, then **5% royalty** on gross above that. Epic Games Store sales royalty-free. Full C++ source access.
- **If chosen, the build shape:** C++-only gameplay mandate (no Blueprints beyond thin glue), one-file-per-actor for diffability, agents restricted to code + data assets, human does all editor/world work. **Dealbreaker risk:** the human becomes the bottleneck on exactly the iteration the agents were hired for; UE5 line is also end-of-life for majors (UE6 migration looms mid-project).

### Unity 6.5
- **Current:** Unity 6.5 (June 2026). Unity 6.4 (March 2026) moved **ECS/Entities into the core engine** (no longer a bolt-on package); unified GameObject/ECS transforms landing across the 6.x line toward the 6.x LTS. Quarterly "supported update" cadence; Unity 6.3 LTS supported to Dec 2027. CoreCLR migration on the 2026 roadmap.
- **Relevant tech:** ECS/DOTS (now the credible path to GTA-scale entity counts: traffic, peds, streaming subscenes), HDRP (high-end look, but no Nanite/Lumen equivalents — classic LOD + probe/RTGI workflows), Burst + Jobs.
- **License:** Runtime Fee is dead (killed Sept 2024). **Personal free under $200K annual revenue/funding**; Pro required above (~$2.2K/seat/yr, +5% price hike Jan 2026). **No royalty.** Note: Havok Physics no longer bundled with Pro from 6.3 (Unity Physics/PhysX remain). Source access is paid/limited.
- **If chosen, the build shape:** ECS/DOTS for traffic-ped-streaming backbone, GameObjects for authored gameplay, NWH Vehicle Physics 2 for cars, Force Text serialization + prefab-variant discipline so agents can patch scenes. **Dealbreaker risk:** none hard — it's the safe compromise; costs are the slower headless loop, closed source, and a publisher whose licensing has already changed under developers once.

### Godot 4.6
- **Current:** Godot 4.6 (Jan 2026). **Jolt is now the default 3D physics engine** for new projects (the same solver as Horizon Forbidden West). 4.5 (Sept 2025) brought Vulkan optimizations and the shader baker; 4.6 added LibGodot embedding, Node UIDs, rearrangeable editor, debugger upgrades.
- **Relevant tech:** Vulkan renderer with SDFGI/VoxelGI (good, not Lumen), GDScript + C# + GDExtension (C++/Rust), `--headless` editor/import/export from CLI, fully text-based scene format.
- **License:** **MIT.** No fees, no royalty, no seat licenses, full source, ever.
- **If chosen, the build shape:** GDScript-first gameplay with GDExtension C++ for sim hot paths, servers-not-nodes for ambient masses, custom chunk streaming, everything CI-gated headless. **Dealbreaker risk:** we own more engine-adjacent code (streaming, HLOD, vehicle feel) than on UE/Unity; if two of those three go badly, the choice was wrong — which is exactly what Tier 1 exists to discover cheaply.

### Custom web/native stack (Three.js or Babylon.js + WebGPU + Rapier/Jolt WASM)
- **Current:** WebGPU is **baseline in all major browsers** including iOS Safari (since Sept 2025); ~95% device coverage with automatic WebGL2 fallback. Three.js ships a production `three/webgpu` renderer (WebGPU becomes the stable default path by end of 2026). Babylon.js 9.0 (March 2026) has clustered + volumetric lighting on WebGPU compute. Rapier JS/WASM at 0.19.x with 2–5× perf gains from the 2025 SIMD/BVH work; **JoltPhysics.js** (npm `jolt-physics`) exposes Jolt's actual **wheeled-vehicle controller** in WASM, with maintained Three (`@react-three/jolt`) and Babylon integrations.
- **License:** MIT across the board.
- **If chosen, the build shape:** TypeScript + Three.js/WebGPU + JoltPhysics.js, Vite/Vitest/Playwright loop, custom streaming and tooling throughout. **Dealbreaker:** no console path, browser memory ceilings vs open-world ambitions, and every engine subsystem GTA needs becomes our code. Kept in the deck because it is the honest ceiling of agent velocity — the benchmark the chosen engine's loop should be measured against.

---

## 2. Scored decision matrix

Scores 1–10. **Weights reflect this project's reality: one human + agents.** AI-agent buildability is weighted highest on purpose — an engine agents can't drive is a Ferrari without a steering wheel.

| Criterion | Weight | UE 5.8 | Unity 6.5 | Godot 4.6 | Web stack |
|---|---|---|---|---|---|
| Visual ceiling (GTA-fidelity potential) | 1.0 | **10** | 7 | 5 | 5 |
| Open-world streaming maturity | 1.5 | **10** | 6 | 4 | 3 |
| Vehicle physics quality | 1.5 | 8 | 6 | **7** | 6 |
| Character/animation pipeline | 1.0 | **10** | 6 | 5 | 3 |
| **AI-agent buildability** | **3.0** | 4 | 7 | **9** | **10** |
| Asset ecosystem & cost | 1.0 | **10** | 8 | 5 | 5 |
| License/royalty terms | 0.5 | 7 | 7 | **10** | **10** |
| Path to console/PC/web | 1.0 | 8 | **9** | 6 | 4 |
| **Weighted total (/105)** | | **79.5** | **72.5** | **72.0** | **65.5** |
| **Weighted, Tier 1–2 scope (streaming & visuals ×0.5)** | | 69.5 | 66.0 | **68.0** | 63.5 |

### Scoring rationale (the honest notes)

**Unreal 5.8** — The *only* engine with turnkey GTA infrastructure: World Partition streams automatically, Mass AI + the free **City Sample** demo *is* a drivable city with traffic and crowds, MetaHuman solves characters, Nanite/Lumen erase LOD/lighting authoring. **But it fails the criterion that matters most here.** Blueprints and `.umap`/`.uasset` are opaque binary — Claude cannot read, diff, or write them. The escape (one-file-per-actor + pure C++ gameplay, no Blueprint) means 10-minute+ compile-link cycles, a 100GB+ engine footprint, weak macOS-first ergonomics, and an API surface so sprawling that agent output needs constant human correction. Headless cook/build exists (`UnrealEditor-Cmd -run=cook`) but the inner loop is editor-bound. Agents become *advisors*, not *builders*.

**Unity 6.5** — The middle path. C# is Claude's second-best game language; scenes/prefabs serialize to **text YAML** (with Force Text on) so agents can diff and patch them — noisy but workable. `-batchmode -executeMethod` gives real CLI builds and the Unity Test Framework runs headless. ECS-in-core (6.4) plus subscene streaming is a legitimate open-world backbone, but you assemble it yourself; nothing like World Partition exists out of the box. Built-in WheelCollider is poor — budget **NWH Vehicle Physics 2** (~$100, best-in-class off-the-shelf arcade-sim vehicles). HDRP looks great but demands classic LOD discipline. Domain-reload lag makes the iteration loop slower than Godot's. Closed source; licensing has been volatile once already (Runtime Fee scar tissue is a real governance signal, even though it was reversed).

**Godot 4.6** — The agent-native engine. **Everything is text**: `.tscn` scenes, `.tres` resources, `.gd` scripts, `project.godot` — all diffable, mergeable, writable by Claude directly, no editor round-trip required. `godot --headless` imports, runs, exports, and executes gdUnit4/GUT test suites in CI. Hot-reload on script save. The full engine source is MIT and greppable when agents need ground truth. Jolt-by-default gives a serious, deterministic physics base; `VehicleBody3D` (raycast car) is tunable to "fun arcade driving" but you'll write the handling layer yourself. Weaknesses are real: no built-in world streaming (manual chunking — feasible, it's exactly the kind of systematic code agents write well), visual ceiling is "great stylized," not photoreal, and **console requires a porting partner** (W4 Games et al.) since console SDKs can't be open-source.

**Web stack** — The *fastest* agent iteration loop in existence: Vite hot reload in ~100ms, Vitest + Playwright headless testing, npm ecosystem, and TypeScript/Three.js is arguably Claude's single strongest domain by training data. JoltPhysics.js even ships a real vehicle controller. But you are building an *engine*, not a game: streaming, LODs, culling, animation retargeting, spatial audio, save systems — all bespoke. Browser memory ceilings (~2–4GB practical) fight open worlds. No console path worth discussing. Verdict: **phenomenal for a Tier 1 prototype, a trap for Tier 2+.**

### The key insight from the matrix
UE wins the abstract contest and **loses this project's contest**. When you halve the weight of criteria that only matter at photoreal Tier-3 scope (bottom row), Godot pulls even with Unreal and effectively ahead once you price in agent throughput — the multiplier the matrix can't fully capture: on Godot, agents ship *finished, tested features* unattended; on Unreal they ship *suggestions*.

### Per-criterion deep notes

**Open-world streaming.** UE World Partition is genuinely turnkey: one persistent level, automatic grid cells, HLOD generation, data layers — the *City Sample* streams a 4 km² city out of the box. Unity's answer is ECS subscenes (streamable, now core in 6.4) + Addressables, which works but is assembly-required; HDRP has no automatic HLOD equivalent. Godot has **nothing built in**: the pattern is a `ChunkManager` that loads/frees `.tscn` chunks (or server-built geometry) around the player on a grid with hysteresis, plus hand-rolled LOD via `VisibleOnScreenNotifier3D`/distance swaps. That is ~2–4 weeks of very testable, very agent-friendly systems code — but it is *our* code to maintain, and HLOD/impostor generation for far-city silhouettes is on us too (Blender headless can bake impostors). Web stack: everything manual *and* fighting a browser memory ceiling.

**Vehicle physics.** The game is driving-first, so this criterion is existential. UE Chaos Vehicles: capable sim-cade base, notoriously fiddly to tune, tuning lives in editor UI (agent-hostile). Unity: stock WheelCollider is bad; NWH Vehicle Physics 2 or Edy's are excellent paid solutions with C# tuning surfaces (agent-workable). Godot: `VehicleBody3D` raycast car on top of Jolt — solid foundation, deterministic, but "GTA feel" (weight transfer, handbrake slides, arcade grip curves, damage) is a custom handling layer we write; all parameters live in text resources, so agents can run automated tune-and-test loops (scripted slalom/brake-distance tests in headless CI — an unusual advantage: *measurable* car feel). Jolt's native `VehicleConstraint` is also reachable via GDExtension if `VehicleBody3D` tops out. Web: JoltPhysics.js exposes Jolt's real wheeled-vehicle controller — surprisingly strong.

**Character/animation.** UE is a different league: MetaHuman creator+animator in-engine, Motion Matching (production since 5.4), retargeting, Mutable runtime customization, ML Deformer. Unity: solid Mecanim + Animation Rigging, no character-creation answer (buy or build). Godot: `AnimationTree` state machines are fine, retargeting works in-editor, root motion supported — but no motion matching, no character tool; pipeline is Blender/Mixamo/Character Creator → glTF. For stylized peds this is acceptable; it is the biggest quality gap we accept, and cutscene ambitions must stay modest (staged in-engine cameras, no facial capture).

**Asset ecosystem.** Fab (UE) consolidated Marketplace+Quixel+Sketchfab; Megascans' free-for-all ended after 2024 (individual assets ~$4.99+, Megaplants free for UE 5.7+ workflows) and much Fab content is UE-format-first. Unity Asset Store remains the deepest *tooling* store (vehicle physics, traffic systems, dialogue systems — whole subsystems for $50–100). Godot's asset library is thin for art but irrelevant if the pipeline is glTF-from-Blender + Synty/Kenney packs, which it is. Web: glTF + Poly Haven + Kenney covers prototyping.

---

## 2b. What the agent loop actually looks like (the deciding criterion, concretely)

The test: *Claude gets an issue — "add a pursuit state where police cars ram the player above wanted level 2" — and must land a reviewed, tested PR with no human editor time.*

**Godot 4.6** — Reads `police_ai.gd`, `pursuit.tscn` (text), edits both, writes a gdUnit4 sim test that spawns cop + player in headless mode and asserts ramming behavior, runs `godot --headless --import && godot --headless -s run_tests.gd`, iterates on failures, opens PR with a diff a human can actually read. **Fully autonomous.** Script hot-reload also means Milad can watch agent changes land in a running game.
- CI shape: `godot --headless --import` (asset import) → unit/sim tests → `--export-release` per platform → smoke-run exported build. All scriptable today, no third-party glue.

**Unity 6.5** — Same flow via C# + YAML scene patches + `-batchmode -runTests`. Works, with caveats: YAML scene diffs are noisy (fileID soup) so agents prefer prefab-variant + code-driven wiring; each headless invocation pays editor startup + domain reload (minutes, not seconds); Editor-only APIs create "works headless, breaks in editor" surprises. **Autonomous with friction.**

**Unreal 5.8** — If the behavior lives in Blueprint: **agent is blind** — binary asset, cannot read or write it. If we mandate C++-only gameplay: agent edits code, but the build is 5–15 min, functional testing means booting the editor or a packaged build (minutes more), and any actor-wiring change still wants the editor. Epic's own 5.8 answer is LLM tooling *inside* the editor — assistant-style, not pipeline-style. **Human-in-the-loop, permanently.**

**Web stack** — `vite` hot reload <1s, `vitest` in ms, Playwright drives the actual game headless, TypeScript's compiler errors are the best agent feedback signal in the industry. **Maximally autonomous** — but autonomy aimed at building an engine before a game.

Also load-bearing: Godot's MIT **engine source lives in the repo** as retrieval ground truth. When an agent is unsure what `VehicleBody3D` actually does, it greps the implementation instead of hallucinating docs. Neither Unity nor UE (without source hoops) offers that with this little friction.

---

## 3. Scope reality check

**Benchmark:** GTA 5 ≈ 1,000 developers × 5 years ≈ $265M. GTA-scale is **~5,000 person-years**. A solo dev with strong agents realistically multiplies output 3–10× on *code and pipeline*, ~1.5–2× on *art*, and ~1× on *design taste and QA of feel*. That yields maybe 5–15 person-year-equivalents over 2–3 calendar years. That is **0.1–0.3% of GTA 5's budget**. Plan accordingly or die of scope.

### Tier 1 — Greybox driving city slice (**4–8 weeks**)
Scope: 2–4 km² of downtown-DFW road grid imported from real OSM data, grey extruded buildings, one drivable car with tuned arcade handling, chase camera, day/night cycle, ~20 spline-following ambient traffic cars, on-foot walk toggle.
- *Weeks 1–2:* engine bake-off spike (see Recommendation) + OSM → road-graph importer with unit tests.
- *Weeks 3–4:* mesh generation from graph (roads, intersections, curbs, extruded footprints); chunk-streaming stub; car v1 on Jolt.
- *Weeks 5–6:* handling-tuning harness (automated slalom/brake/jump metrics in headless CI), chase cam, day/night, ambient traffic on lane graph.
- *Weeks 7–8:* on-foot toggle, perf pass (60fps mid-range), packaged build to 5–10 testers.
- **Purpose:** prove the agent pipeline end-to-end with zero manual editor steps, and find out if *driving feels good*. If driving isn't fun by week 8, nothing downstream matters. **Kill-gate.**

### Tier 2 — Stylized vertical-slice district (**5–9 months cumulative**)
Scope: one coherent district (a Deep Ellum / Fort Worth Stockyards analog), committed art direction, 3–5 structured missions with cutscene-lite staging, on-foot + vehicle gameplay (incl. basic shooting or a deliberate no-gun stance — design decision), wanted-level-lite police response (2–3 escalation stages), ambient peds with day/night schedules, radio station with satire ads and licensed-indie/original music, save system, controller support, options menu, performance-clean on mid-range hardware.
- *Months 2–3:* art direction lock + building-generator v2 (styled), Synty/kitbash integration pass, ped v1 + Mixamo locomotion set.
- *Months 4–5:* mission framework (trigger/objective/fail-state as data-driven text resources — agents author missions as code), police response, radio pipeline.
- *Months 6–8:* 3–5 missions built and polished, audio pass, save/load, demo hardening.
- **Purpose:** the pitch/demo artifact — Steam page, trailer, playtest cohort. This is the maximum honest promise for year one. **Kill/pivot-gate:** wishlist and playtest signal decide Tier 3.

### Tier 3 — Systemic open city (**24–36 months cumulative**)
Scope: 15–30 km² abstracted metroplex (4–6 districts + highway spine — DFW at ~1:40 scale), systemic traffic/pedestrian/police simulation (sim LOD: full physics near player, lightweight agents beyond), mission framework with 15–25 missions across 2–3 arcs, economy/property-lite, side activities (races, delivery, scavenger satire), full streaming with far-city impostors, 15+ hours of play, Steam release.
- **Reality:** achievable **only** with ruthless stylization, procedural-first content, and systemic (not hand-scripted) gameplay. Content volume, not code, is the wall — agents help least exactly where GTA spent most (mocap, VO, hand-dressed interiors, mission polish). Cut list is pre-committed: no multiplayer, no interiors beyond ~10 hero spaces, no facial animation, no licensed music, no swimming/aircraft unless a system pays rent twice.
- Anything pitched as "GTA 6 but solo" is fantasy; "systemic stylized crime sandbox with sharp writing set in a satirical DFW" is not.

**Rule:** No Tier N work until Tier N−1 is *shipped to players* (even 10 testers). Each tier ends in a written kill/continue decision.

---

## 4. Asset strategy — how a solo dev fakes a city

### 4.1 OSM as the map skeleton (highest-leverage decision available)
DFW is fully mapped in OpenStreetMap: road centerlines with classification (motorway→residential), lane counts, one-way flags, building footprints (often with height), land use, rail, water. **The real topology of the real place is free, and it's exactly the thing that's hardest to fake by hand** — GTA maps live or die on believable road networks.
- **Pipeline:** Geofabrik Texas extract or Overpass API → filtered `.osm.pbf` → custom importer (pure data-transform code: **ideal agent work**) → game-native road graph (nodes/edges/lanes) + district polygons + building footprints. The road graph doubles as the **traffic AI's navigation data** — one source of truth for geometry and simulation.
- **Blender route:** the **Blosm** addon (ex blender-osm) imports OSM + terrain in a few clicks for look-dev and reference; the production path should stay code-first (parse OSM ourselves) so regeneration is deterministic and CI-able.
- **Abstraction:** import real topology, then *compress* — DFW is ~24,000 km²; the game map is a curated 15–30 km² "greatest hits" collage keeping the real relationships (Trinity River split, the two downtowns 30 miles apart collapsed to ~4 km, the loop highways, DFW airport as the map's dead center) at ~1:30–1:50 scale. Real street *pattern*, parody street *names*.
- **DFW anchor set for the collage** (research real → rename in canon docs later): Downtown Dallas + Reunion Tower sphere, Deep Ellum murals/venues, the I-30/I-35E Mixmaster, Trinity River levees, Uptown glass, Highland Park mansions, Fort Worth Stockyards, downtown Cowtown, DFW Airport sprawl, Arlington stadium district (Cowboys/Rangers analogs — peak satire density), Plano/Frisco corporate-HQ suburbia, Grand Prairie strip-mall infinity. Each is a *district generator preset*, not a hand-built set.
- **Legal:** OSM is ODbL — fine for generated game geometry with attribution; keep the attribution note in credits and don't ship raw OSM data as a queryable database. Building *footprints/heights* are data (fine); real business *names/logos* from OSM tags must be stripped and replaced by the parody-name generator.

### 4.2 Blender geometry nodes as the building factory
- Footprint polygon in → textured building out: floor loops, window grids, ground-floor storefronts, AC units, signage mounts. Texas-specific grammars: strip malls, tilt-wall warehouses, ranch homes, glass towers, mega-church, car dealership.
- **Agent-critical:** Blender is fully scriptable (`bpy`) and runs headless (`blender --background --python gen.py`). Agents can write and regression-test the entire building generator without opening a UI. Export glTF → engine. This makes architecture a *software problem*, which is the problem class agents are best at.
- Grammar sketch (each preset = footprint rules + facade module set + roof/prop scatter + palette): `strip_mall`, `tiltwall_warehouse`, `ranch_house`, `mcmansion`, `glass_tower`, `parking_garage`, `megachurch`, `dealership`, `honkytonk`, `stadium`. Ten presets cover ~90% of DFW's built environment — that is the entire trick.

### 4.3 Kitbash marketplaces (buy the boring stuff)
- **Synty** (POLYGON packs) — the canonical stylized-city shortcut: vehicles, peds, props, whole city sets, ~$20–200/pack, consistent style, rigged characters. Works in Godot via FBX/glTF.
- **Kenney** (free, CC0) and **Quaternius** (free) for props/prototyping; **Sketchfab/Fab** for gap-filling (Fab Standard license — note most Megascans stopped being free-for-all after 2024; largely moot if we go stylized).
- **Mixamo** (free) for humanoid animation baseline; retarget in Blender or engine.
- Budget: **$500–1,500 total** buys a coherent stylized city kit. Photoreal equivalent: doesn't exist at any solo price.

### 4.4 Stylization: the escape hatch, stated plainly
Photorealism is a **content-cost multiplier of 10–50×** (unique textures, photogrammetry, LOD chains, mocap) and invites direct visual comparison to GTA 6 — a comparison this project loses on day one. A committed style (sun-bleached flat-shaded Texas palette; painterly; or PS2-era-deliberate) does four jobs at once: hides procedural repetition, makes kitbash + generated assets cohere, cuts per-asset cost by an order of magnitude, and *sharpens the satire* (stylization reads as authorial voice). **Style is the strategy, not the compromise.** This also neutralizes most of Unreal's matrix lead — Nanite/Lumen/MetaHuman are photoreal force-multipliers we'd barely use. Proof this works commercially: *Untitled Goose Game*, *Sludge Life*, *Roadwarden*-through-*Sable* — small teams whose look *is* the brand. The reference point for tone: a game that looks like a heat-hazed editorial illustration of Texas, not a cheaper GTA.

### 4.5 Cash budget through Tier 2 (engine choice makes this almost free)

| Line item | Cost |
|---|---|
| Godot 4.6 engine | $0 (MIT) |
| Blosm Blender addon (look-dev) | ~$30 |
| Synty city/vehicle/character packs | $300–700 |
| Kenney/Quaternius/Poly Haven | $0 (CC0) |
| Mixamo animation | $0 |
| Concept-art pass for style lock (contract) | $500–1,500 |
| Audio (SFX packs + a few original radio tracks) | $200–500 |
| **Total through Tier 2** | **~$1,000–2,700** |

The only scenario where cash matters is post-revenue: Unity Pro if >$200K/yr (Unity path), 5% royalty past $1M (UE path), console porting contract (any path). On Godot the game costs approximately its own asset packs.

---

## 5. Recommendation

**Primary: Godot 4.6 (Jolt physics), GDScript + GDExtension/C++ for hot paths, stylized art direction, OSM-derived DFW map skeleton, Blender-geometry-nodes building factory.**

Because: (1) text-first everything means agents are *builders* with full CI (headless import/test/export) — the single biggest force multiplier available to this team-of-one; (2) MIT license removes all fee/royalty/policy risk for a multi-year bet; (3) Jolt-by-default is a credible physics base for a driving game; (4) the things Godot lacks (turnkey streaming, photoreal) are respectively *agent-writable code* and *deliberately out of scope*.

**Structured as a bet with an off-ramp:**
1. **Weeks 1–2 — bake-off spike:** the same micro-slice (OSM import of ~1 km² of downtown Dallas, one drivable car, chunk streaming stub, headless test run in CI) in **Godot** and **Unity 6.5 + ECS**. Judge on agent autonomy (how many PRs land without human rescue) and driving feel. Unity is the fallback if Godot's vehicle feel or perf disappoints — it keeps ~80% of the agent workflow and adds NWH vehicles + stronger console path.
2. **Unreal is rejected for build, not for study:** keep the free **City Sample** installed as the reference implementation for traffic/crowd/streaming design patterns.
3. **Web stack rejected as the game platform**, retained as a possibility for a marketing artifact later (a Three.js "drive the map" browser toy is cheap once the OSM pipeline exists).
4. **Console** is deferred: ship PC (Steam) first; Godot console ports go through W4 Games/partners when revenue justifies it.

### Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Godot perf ceiling at Tier-3 entity counts (1000s of sim agents) | Medium | High | Servers-not-nodes architecture from day one (`RenderingServer`/`PhysicsServer3D` direct use for traffic/peds); GDExtension C++ for sim hot paths; sim-LOD (full agents near player only) |
| Vehicle feel never reaches "fun" | Medium | Fatal | It *is* the Tier-1 gate; automated feel metrics + weekly human playtests; fallback = port handling layer to Unity+NWH |
| Smaller Godot training corpus → agent hallucination of APIs | Medium | Medium | Engine source vendored in-repo as retrieval ground truth; project skill docs with canonical patterns; gdUnit4 tests catch API drift |
| Solo-dev burnout / scope creep | High | Fatal | Tier gates with written kill decisions; pre-committed cut list; ship-to-testers cadence every tier |
| Godot 4.x breaking changes mid-project | Low | Medium | Pin engine version per tier; MIT source means we can self-patch rather than wait |
| Console port economics never materialize | Medium | Low | PC-first plan already assumes it; W4 Games port is a revenue-contingent option, not a dependency |
| Stylized look reads as "cheap" instead of "authored" | Medium | High | Art-direction lock milestone with paid concept pass before Tier 2 asset spend |

---

## 5b. Reference architecture (Godot path) — so week 1 starts concrete

**Repo layout (all text, agent-navigable):**
```
/game            Godot project (.tscn/.tres/.gd — text only, binary assets via glTF/PNG in /game/assets)
/pipeline        OSM importer, buildgen (bpy scripts), parody-name generator  — pure Python/Rust, own test suites
/engine-src      Vendored Godot source @ pinned tag (retrieval ground truth, not built from)
/docs            Canon (this file, design docs, skill docs for agents)
/tests           gdUnit4 suites + headless sim scenarios (drive tests, streaming tests, police-AI tests)
```
**Core architectural bets:**
1. **Data-driven everything:** missions, vehicle handling, district presets, ped schedules, radio playlists = `.tres`/JSON text resources. Agents author *content* as diffable data, not editor clicks.
2. **Servers over nodes for mass simulation:** ambient traffic/peds live in packed arrays driven by `PhysicsServer3D`/`RenderingServer` (Godot's ECS-adjacent escape hatch); full `CharacterBody3D`/`VehicleBody3D` nodes only within ~100m of player.
3. **One world graph:** the OSM-derived road/lane graph is the single source for mesh generation, traffic nav, police routing, mission placement, and minimap. Regenerating the city is a build step (`make city`), never a manual act.
4. **Determinism where it pays:** Jolt is deterministic — seed-stable replays become the test harness for chases and physics regressions.
5. **CI gates every PR:** import → static checks (gdlint) → unit tests → headless sim tests → export → 60-second automated smoke drive with screenshot diffs. Red pipeline = no merge, agent or human.

**Agent conventions (to be enshrined in CLAUDE.md):** scene edits via text `.tscn` patches only; every gameplay feature lands with a headless test; tuning parameters exposed in `.tres`, never hardcoded; screenshots for visual changes attached to PRs via headless capture.

**Performance budget (Tier 1–2 targets, mid-range 2022+ hardware — RTX 3060 / M2 class, 1080p60):**

| Budget | Target |
|---|---|
| Frame time | 16.6ms (10ms render / 4ms sim / 2.6ms headroom) |
| Streamed chunk size | 200–400m grid cells, ≤50ms load hitch budget (threaded load, hitch = test failure) |
| Active physics vehicles | ≤24 full Jolt bodies near player; beyond that, kinematic lane-followers |
| Ambient peds | ≤200 visible (server-driven multimesh), ≤16 full character nodes |
| Draw calls | ≤2,000/frame (aggressive mesh merging in buildgen; per-district texture atlases) |
| Memory | ≤6GB total, ≤3GB VRAM |

These numbers are deliberately conservative — they are *test assertions in CI*, not aspirations, which is only possible because the whole pipeline runs headless.

---

## 6. Decisions needed from Milad

1. **Approve the two-week Godot vs Unity bake-off** (or skip it and commit to Godot now — saves 2 weeks, adds risk).
2. **Art direction commitment** — pick the stylization lane (flat-shaded Synty-adjacent vs painterly vs deliberate retro) *before* Tier 2; every asset dollar and shader hour depends on it.
3. **Ambition ceiling on record** — is Tier 3 the goal, or is Tier 2 (killer vertical slice → funding/team) the actual play? This changes streaming architecture decisions in month one.
4. **Map scale ruling** — approve the ~1:30–1:50 compressed "greatest hits" DFW collage vs a literal-scale single district.
5. **Budget line** — ~$500–1,500 asset/kitbash budget + ~$100 tools (Blosm, misc) for Tier 1–2: approve.
6. **Multiplayer: explicitly cut?** Recommend yes (cut) — it roughly doubles every system's cost. Needs to be on paper.
7. **Scripting split** — GDScript-first (fastest agent loop) with C++ GDExtension for sim hot paths, vs C#-throughout (more familiar corpus). Recommend GDScript-first; decide at bake-off end.
8. **Platform order** — PC/Steam first, consoles via porting partner post-revenue, web never (as game): confirm.

---

## 7. Follow-up canon docs this evaluation unblocks

1. `docs/tech/osm-pipeline.md` — OSM extract → road graph → mesh spec (data schema, coordinate system, chunk format). Blocked only on bake-off engine choice.
2. `docs/tech/vehicle-handling.md` — target feel references (GTA 4 weight vs GTA 5 arcade vs Saints Row), tuning parameters, automated feel-test definitions.
3. `docs/design/art-direction.md` — style lanes with reference boards, palette, shader plan. Blocks all Tier 2 asset spend.
4. `docs/design/map-collage.md` — the DFW compression map: which real anchors survive, district adjacency, parody name registry.
5. `docs/tech/agent-conventions.md` → distilled into repo `CLAUDE.md` at project init.

---

## Sources (verified July 2026)
- UE releases: [UE 5.8 announcement](https://www.unrealengine.com/news/unreal-engine-5-8-is-now-available), [UE 5.7 announcement](https://www.unrealengine.com/news/unreal-engine-5-7-is-now-available), [UE 5.7 release notes](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5-7-release-notes), [UE licensing](https://www.unrealengine.com/license), [UE licensing guide 2026](https://www.seeles.ai/resources/blogs/unreal-engine-pricing-royalties-and-licensing-guide)
- Unity: [Unity 6 releases & support](https://unity.com/releases/unity-6/support), [Unity 6.5 announcement](https://discussions.unity.com/t/unity-6-5-is-now-available/1723176), [Unity pricing updates](https://unity.com/products/pricing-updates), [ECS status Dec 2025](https://discussions.unity.com/t/ecs-development-status-december-2025/1699284), [Unity 2026 roadmap](https://digitalproduction.com/2025/11/26/unitys-2026-roadmap-coreclr-verified-packages-fewer-surprises/)
- Godot: [Godot 4.6 release coverage](https://digitalproduction.com/2026/01/28/godot-4-6-arrives-with-major-cg-friendly-updates/), [4.5/4.6 recap incl. Jolt default](https://www.oflight.co.jp/en/columns/godot-4-5-and-4-6-feature-update-2026), [Jolt migration guide](https://www.strayspark.studio/blog/godot-46-jolt-physics-migration-guide)
- Web stack: [Three.js 2026 state](https://www.utsubo.com/blog/threejs-2026-what-changed), [WebGPU baseline](https://vr.org/articles/webgpu-baseline-2026-three-js-webxr-default), [web engines comparison 2026](https://app.cinevva.com/blog/2026-06-09-web-game-engines-2026-comparison), [Rapier 2025 review/2026 goals](https://dimforge.com/blog/2026/01/09/the-year-2025-in-dimforge/), [rapier.js](https://github.com/dimforge/rapier.js/), [web physics comparison](https://app.cinevva.com/tutorials/game-physics-libraries.html)
- Assets/OSM: [Quixel on Fab](https://quixel.com/news/quixel-on-fab-new-megascans-and-megaplants), [Megascans free-period end](https://www.cgchannel.com/2024/10/epic-games-has-made-megascans-free-to-all-but-only-until-the-end-of-2024/), [Blosm addon](https://github.com/vvoovv/blosm), [SideFX OSM city building](https://www.sidefx.com/tutorials/city-building-with-osm-data/)
