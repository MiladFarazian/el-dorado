# Map Concept — The Fictional Metroplex

**Status:** Design canon v1 (late July 2026). Built on `docs/research/dfw-geography.md`, `docs/research/gta-design-dna.md`, `docs/research/satire-targets.md`. City/region names below are RECOMMENDED; final lock happens in the world-building doc. Names already used in satire canon (Middlington, Brisco, Blando, Salvation, ClingTel Colosseum, etc.) are treated as adopted.

---

## 1. Shape & Scale

**Recommendation: ~110 km² bounding box (13 km E–W × 8.5 km N–S), ~85 km² playable land.** Calibration: Los Santos + Blaine County ≈ 80 km². We go slightly wider but *cheaper per km²* — no mountain range, heavy kit reuse (see density tiers), and two-fifths of the map is terrain/water/edge fade.

- **Shape: a wide ellipse containing a dumbbell.** GTA V is a tall island with one core at the bottom; ours is a *landscape-orientation* map with a mass at each end (Dorado east, Fort Verde west), a stadium cluster at the exact midpoint, and the airport as a third mass center-north. E–W is the long axis because the metro's identity is the drive between the downtowns.
- **Linear compression ≈ 1:8.5.** Real downtown-to-downtown is 32 mi / 51.5 km → **6 km center-to-center in game** (~3 min at freeway speed). Matches Rockstar's ~1:8 LA compression and the geography doc's 1:6–1:8 recommendation. Full E–W crossing ≈ 6–7 min; N–S ≈ 4 min. A "road trip" by open-world standards, never a chore.
- **Density budget (solo-dev feasibility):**
  - **Tier A — hand-authored dense (~12 km²):** Downtown Dorado + Uptown, Deep Elm, Fort Verde core + Brandyards, Middlington stadium cluster, DVI terminals. All hero assets live here.
  - **Tier B — grammar-kit urban (~33 km²):** frontage-road strips, boomburb HQ campuses, subdivisions, warehouse fields. Texas sprawl is *authentically repetitive* — the same HollerBurger/Dam Store/strip-mall kit recurring is honest, not lazy. Differentiate by signage, radio reception, and NPC wardrobe.
  - **Tier C — terrain/edge (~40 km²+ incl. water):** floodway, forest, escarpment, lakes, ranch fade, construction frontier. Cheap to build, structurally essential (the geography doc's rule: that emptiness is identity, not dead space).
- **Compression strategy: greatest-hits geography.** Keep the 40-odd places a local would name, in correct *relative* position; delete connective tissue; preserve the seven iconic drives from the geography doc at full fidelity (I-3 skyline-to-skyline, the Tollpike money gradient, Mirror Row, the High Ten + Canyon, the escarpment cut, the Wishbone over the floodway, one canonical frontage strip). Test: 10 DFW locals recognize ≥8 of 10 parody landmarks unprompted (DNA checklist #4).

---

## 2. The Twin-City Problem — Solved

GTA has never shipped two downtowns; the risks are split identity, doubled hero-asset cost, and muddy navigation. The dumbbell is our differentiator, so we keep it — under five rules:

1. **Asymmetry is law.** Dorado: vertical, glass, LED, night-lit — ~2× Fort Verde's footprint and 3× its height. Fort Verde: low, brick, Art Deco, neon signage, dust. They never share palette, silhouette, cop livery, radio mix, or NPC wardrobe. One is a skyline, the other a *streetscape.* A player teleported to either knows instantly which city holds them (DNA checklist #2).
2. **The bar compresses to one band.** The real 32-mile suburb bar becomes ~2.5 km of I-3 with the **Middlington stadium cluster at the exact midpoint** — where other maps put a mountain, we put the Ego Dome's glow. Mid-Cities interiors (Euless/Bedford/Hurst/N. Richland Hills) are deleted entirely, represented by one ~800 m frontage-road band along SH-83 between Middlington and the airport.
3. **The airport is the third mass, not filler.** DVI sits center-north as a city-sized restricted district (terminals, tarmac, cargo city, spotting hill). It gives the map's middle *weight* without needing another downtown, and separates the north-corridor money belt from the bar.
4. **One skyline dominant from any point.** Sightline rule: from anywhere, at most one downtown reads as "primary." Silhouette anchors are non-confusable — Dorado = ball-on-a-stick + green-outlined tower + glass blade; Fort Verde = Deco brick + neon steer sign + Brandyards water tower. The one designed exception: the **Chalk Ridge overlook**, where both skylines read at once at golden hour — the map's vista shrine.
5. **Fuse aggressively, cut ruthlessly.**
   - **Fused:** Arlington + Grand Prairie → Middlington. Plano/Frisco/McKinney/Addison → Blando (inner) + Brisco (outer). FW's three bar districts (Magnolia, West 7th, Camp Bowie) → one Mimosa Avenue constellation. Grapevine + the airport's north shore → one Muscadine district. Benbrook + Lake Worth + Eagle Mountain → one Eagle Bluff Lake.
   - **Cut:** Denton, Rockwall (Lake Holloway is the edge), Forney, Weatherford, Mesquite/Garland interiors (keep one rodeo arena POI), Irving residential (keep Los Espejos + the Spice Belt), everything past US-380 (fades to construction frontier, then prairie).
   - **Archetype rule:** one of each repeated suburb type survives — one boomburb main street (McKinney's square, folded into Brisco), one 80s edge city (Grand Emporia/Galleria), one slab-farm frontier (Harvest Hills™). Radio and signage do the rest.

---

## 3. Naming the World (options; lock in world doc)

| Real | Recommended | Alternates | Reasoning |
|---|---|---|---|
| Dallas | **Dorado** | Bravado; Prospera | El Dorado = the boomtown-gospel thesis in one word; "Big D" survives as "Big Dorado" |
| Fort Worth | **Fort Verde** | Fort Drover; Fort Chisholm | Satire-canon continuity; "Cowtown" nickname survives untouched |
| The Metroplex | **the Megaplex** | the Twinplex; the Big Sprawl | Canon; movie-theater pun fits a region that markets itself |
| Trinity River | **the Threefork River** | the Trinidad; the Baptism | Three forks converge = literal truth + Trinity echo |
| Texas (if ever named) | **implied, unnamed** | — | The state stays offscreen like Rockstar's early "the state of San Andreas"; revisit in world doc |

Adopted from satire canon: **Middlington** (Arlington), **Brisco** (Frisco), **Blando** (Plano), **Salvation** (Celina), **Shorelake** (Southlake), **Muscadine** (Grapevine — a native Texas grape; "Vinewood" is Rockstar's).

---

## 4. Regions (12)

| # | Region | Real inspiration | Visual identity | Gameplay role | Density |
|---|---|---|---|---|---|
| 1 | **Downtown Dorado & Uptown** | Downtown Dallas, Uptown, Victory Park, Arts District | Glass canyon, LED crowns, rooftop bars, the green-outlined tower | Money: finance heists, Howdy Street satire, nightlife, vertical setpieces | Very High |
| 2 | **Dorado Eastside** | Deep Ellum, the Cedars, Fair Park, Lakewood/White Rock | Brick + murals under an elevated freeway; Deco fairground; lake bohemia | Nightlife/music economy, seasonal State Fair event, chill lake pocket | High |
| 3 | **Westbank & the Floodway** | Design District, Trinity floodway, Trinity Groves, Harry Hines, Love Field | Warehouses, levee-walled green void, motel sleaze, small airport | Deal-gone-wrong country, illegal race arena, vice strip, GA aviation | Medium |
| 4 | **Oak Bluff (Southside)** | Oak Cliff, Bishop Arts, Jefferson Blvd, Great Trinity Forest edge | Craftsman blocks, Latino main street, botánicas, forest creeping in | Story soul, gentrification frontier, streetcar, body-dump wilderness | Medium |
| 5 | **Chalk Ridge** | White Rock Escarpment, Cedar Hill, antenna farm, Joe Pool Lake | Limestone ridge, cedar scrub, 450 m blinking TV masts, lake shore | Only hills: canyon roads, overlooks, radio-tower setpiece, state park | Low/Wild |
| 6 | **Hyland Glen & the Trench** | Highland/University Park, SMU, US-75 corridor | Mansion canopy streets, private cops, sunken expressway walls | Gated-wealth zone with its own hostile police response; trench chases | Medium |
| 7 | **Blando** | Plano Legacy, Galleria/Addison, Telecom Corridor, Koreatown | HQ campus row, mirrored mid-rises, mall, K-Row neon | Corporate-heist park, espionage, karaoke nightlife, Texchange satire feeder | Medium-High |
| 8 | **Brisco & the Frontier** | Frisco (The Star, Universal Kids, PGA), McKinney, Prosper/Celina | Sports-city gloss dissolving into framing lumber and mud roads | Hype-economy satire playground; the map's visibly growing edge | Medium → fade |
| 9 | **Los Espejos** | Las Colinas, Irving's Belt Line corridor | Mirror-glass towers over Venetian canals; bronze mustang fountain; sari shops | Jet-ski-in-an-office-park; canal chases; Spice Belt culture pocket | Medium |
| 10 | **DVI Airport & Muscadine** | DFW Airport, Grapevine Main St, Lake Grapevine, Gaylord | Terminal megastructure + tarmac ocean; 1890s main street; wooded lake | Restricted-zone gameplay, cargo heists, tourist-town cover, lake marina | High (airport) / Low |
| 11 | **Middlington** | Arlington Entertainment District, Six Flags, Grand Prairie | Stadium superblock, coaster skyline, tailgate parking seas | Mid-map playground: stadium infiltration, theme park, event crowds; famously zero transit | High (event-driven) |
| 12 | **Fort Verde & the West** | Downtown FW, Stockyards, Cultural District, TCU, Lockheed, Alliance, ranchland | Brick/Deco core, dirt-and-neon stockyards, museum row; then oak scrub, warehouse ocean, speedway | Second full city: rodeo economy, museum heists, defense-plant endgame, logistics heists, ranch fade | High core → Wild |

Region 12's northern belt (**Concord** — Alliance logistics + the Superspeedway) and western belt (**the Tangles** — Cross Timbers ranch edge, named for the historic "impenetrable tangle") function as sub-regions and appear separately on the schematic.

---

## 5. POIs (parody-named, 40+)

### Dorado core & Uptown
| Real | Parody | Hook / role |
|---|---|---|
| Reunion Tower | **Roundup Tower ("the Lollipop")** | Ball-on-a-stick map icon; observation deck, rappel setpiece |
| Bank of America Plaza | **Bank of Dorado Plaza ("the Green Giant")** | Green-outlined night beacon; recolors for events à la Maze Bank |
| Fountain Place | **Prism Court** | Sliced glass blade + fountain plaza; unmistakable in any weather |
| Pegasus sign / Magnolia Bldg | **the Red Stallion, Magnate Building** | Rooftop neon horse; oldest-money rooftop in the city |
| Giant Eyeball sculpture | **Big Iris** | 30-ft eyeball plaza; free surrealism, meet-spot for missions |
| Klyde Warren Park | **the Lid** | Park decked over 8 roaring lanes; picnic above, chase below |
| Texas Stock Exchange | **the Texchange, Howdy Street** | Canon; cattle-horn bell; Y'all Street satire anchor |
| American Airlines Center | **AmeriGlide Arena** | Arena district; adjacent **Gilt Campus** (bank-fortress, opening in-game) |
| Neiman Marcus flagship | **Needlman & Marks** | "Needless markup" retail cathedral; robbable atrium |
| KBH Convention Center demo | **the Convention Crater** | $3.5B demolition mega-site walling downtown's south edge |
| Dealey Plaza geometry | **Trinity Gate & the Triple Underpass** | Geometry only — courthouse plaza + underpass chase funnel; zero assassination content (binding) |
| Union Station + transit mall | **Union Terminal / MART Central** | All rail lines choke through here; ambush geometry |
| Katy Trail | **the Casey Trail** | Car-free jogger ribbon through the richest zips; parkour chase lane |

### Eastside
| Real | Parody | Hook / role |
|---|---|---|
| Deep Ellum + I-345 overhead | **Deep Elm under the Overhead** | Murals, clubs, tattoo shops beneath an elevated freeway slated for teardown (living-map beat) |
| Fair Park / Big Tex / Cotton Bowl | **Lone Star Fairgrounds: Tall Tom, the Lone Spur wheel, Cottonwood Bowl** | Canon Tall Tom (burned twice); fair-season crowds vs. Deco ghost town off-season |
| White Rock Lake + Arboretum | **Whitechalk Lake & the Arbortorium** | Urban jewel: sailing, bike loop, lakefront mansions — the chill zone |
| Lake Ray Hubbard + I-30 bridge | **Lake Holloway & the Long Bridge** | Eastern map edge; freeway-over-water money shot |

### Westbank & Floodway
| Real | Parody | Hook / role |
|---|---|---|
| Margaret Hunt Hill Bridge | **the Wishbone Bridge** | White arch framing the skyline; jump ramp, mission-climax lockdown |
| Trinity floodway | **the Big Empty (Threefork Floodway)** | Mile-wide leveed void; the illegal street-racing arena (real DFW practice) |
| Design District | **the Showrooms** | Chic by day, empty by night — canonical deal-gone-wrong warehouses |
| Harry Hines / Parkland | **Harmon Hines strip & Charity General** | Vice corridor + the hospital respawn anchor |
| Love Field | **Darlin' Field** | Canon Howdy Air fortress hub; downtown GA/small-plane gameplay |
| Fuel City | **Fuel Town Tacos** | Canon; best tacos in the city at a car wash with live longhorns |

### Oak Bluff & Chalk Ridge
| Real | Parody | Hook / role |
|---|---|---|
| Bishop Arts District | **Deacon Arts District** | Gentrification frontier; streetcar terminus; human-scale streets |
| Jefferson Blvd / Texas Theatre | **Zaragoza Boulevard & Teatro Estrella** | Latino main street: quinceañera shops, botánicas, vintage movie house |
| The Potter's House | **Overflow Fellowship flagship** | Canon megachurch: arena sanctuary, TV studio, parking sea |
| Cedar Hill antenna farm | **Signal Ridge mast farm** | Forest of blinking 450 m masts on the map's high point; radio-tower setpiece |
| Joe Pool Lake / Cedar Hill SP | **Lake Barlow & Chalk Ridge State Park** | Escarpment shoreline; overlook of both skylines |
| Great Trinity Forest | **the Threefork Bottoms** | 10-minutes-from-downtown swamp forest: feral hogs, gar, dumped cars |

### North corridor
| Real | Parody | Hook / role |
|---|---|---|
| Galleria + Valley View site | **Grand Emporia Mall & the Valley Vista rubble** | Ice-rink mall interior + arena-candidate demolition field (mid-game redevelop beat) |
| High Five interchange | **the High Ten** | Five levels, 40 m tall, ribbon-pasta ramps — the road as monument |
| Legacy West / Toyota HQ | **Legend Ranch HQ Row (Kaizen Motors campus)** | Canon Kaizen; relocation-subsidy satire; campus heist park |
| The Star (Cowboys HQ) | **the Brand at Brisco** | Rustlers' practice dome; "the Brand" = cattle iron + marketing, one word |
| Universal Kids Resort | **Colossal Kidz Resort** | Canon; toddler park priced like a mortgage |
| PGA Frisco | **Fairway National HQ & Links Ranch** | Golf-industrial complex resort; caddie-cover infiltrations |
| Grandscape / Nebraska Furniture Mart | **Grandiosa & the Great Plains Furniture Dominion** | Big-box retail as theme park |
| Southfork Ranch | **Whitefork Ranch** | White-columned villain estate mid-subdivision — 89 lots of satire |
| Celina / US-380 frontier | **Salvation & Harvest Hills™** | Canon; slab farms, model homes, cul-de-sacs dead-ending into pasture |
| Buc-ee's | **the Dam Store, Exit 47** | Canon; 120 pumps; restroom pilgrimage site on the Tollpike |
| Data-center barns | **GigaStead compute ranch** | Canon; 72 dB hum on the frontier's edge, "ECONOMIC MIRACLE IN PROGRESS" |

### Airport, Los Espejos & Middlington
| Real | Parody | Hook / role |
|---|---|---|
| DFW Airport | **Dorado–Verde International (DVI), "the Third City"** | Five terminals + **Terminal G** under construction; Skyloop train; tarmac restricted zones; cargo city |
| Founders' Plaza spotting hill | **Founders' Overlook** | Plane-spotting hill = stakeout/sniper vantage over the tarmac |
| Las Colinas canals + Mustangs | **Los Espejos canals & the Broncos fountain** | Mirror towers over water taxis; bronze herd; jet-ski office-park chase |
| SH-114 tower corridor | **Mirror Row** | The most cinematic non-downtown drive, preserved at full fidelity |
| Irving Belt Line "Little India" | **the Spice Belt** | Sari shops, chaat cafés, Bollywood cinema, cricket oval venue |
| AT&T Stadium | **ClingTel Colosseum ("the Ego Dome")** | Canon; video board bigger than the field; fresh off hosting the World Semifinal |
| Globe Life Field | **Orb Life Park** | Roofed ballpark; insurance-naming-rights joke |
| Six Flags + Hurricane Harbor | **Eight Flags Over Middlington & Cyclone Cove** | Canon; rideable coasters; "we added two flags to win" |
| Grapevine Main St + vintage RR | **Muscadine Main Street & the Muscadine Cannonball** | 1890s tourist street; rideable steam train to the Brandyards |
| Gaylord Texan | **the Conservatory Grand** | Glass-atrium biome hotel; conference-heist interior |

### Fort Verde & the West
| Real | Parody | Hook / role |
|---|---|---|
| Sundance Square | **Sundown Square** | Brick-plaza walkable core of the second city |
| FW Water Gardens | **the Sinking Gardens** | Brutalist sunken concrete canyon; one-of-a-kind parkour bowl |
| Bass Performance Hall | **Herald Hall** | Trumpeting-angel façade; gala-night heist venue |
| FW Stockyards | **the Brandyards** | Daily longhorn drive (traffic event!), **Drover Coliseum** rodeo, **Wild Wanda's** honky-tonk (indoor bull riding, signature social space) |
| Cultural District + Dickies Arena | **Museum Mile & the Double-Stitch Arena** | Kahn/Ando-grade museum heist row beside the winter Stock Show |
| Panther Island | **Bobcat Island** | Perpetual mega-project: cranes, cofferdams, half-built bridges as evolving terrain |
| TCU / Magnolia / West 7th | **Chisholm Christian University (Horned Toads), Mimosa Avenue, the Seventh Street Corral** | Purple game-day takeovers; three-bar-district nightlife constellation |
| Lockheed F-35 plant + NAS JRB | **Warhawk Dynamics Plant 1 ("the Mile Building") & NAS Verde** | Mile-long assembly fortress; daily fighter overflights; endgame infiltration |
| Texas Motor Speedway | **the Longhorn Superspeedway** | Drivable 1.5-mi oval map toy; race-event venue |
| Alliance Airport + BNSF | **Concord Cargoport & the Iron Yard** | Trains-meet-planes-meet-trucks logistics heist biome |
| Eagle Mountain / Lake Worth | **Eagle Bluff Lake** | Stilt houses, boat bars, party coves; NW water edge |
| Granbury-style crypto mine | **the HashHoller Mine** | Canon; humming in the Tangles, decibel meter reading one below legal |

---

## 6. Road Network

**Grammar: two loops + a bar + spokes, wrapped by a toll arc.** Fictional numbering keeps single digits (readable at speed).

- **I-3 (the bar):** Fort Verde ↔ Middlington ↔ Downtown Dorado ↔ the Long Bridge over Lake Holloway. The spine drive; both skylines bookend it at night, the Ego Dome glows at the midpoint. Preserved at full cinematic fidelity.
- **I-5E / I-5W (twin trunks):** the real 35E/35W split is a gift — one N–S trunk per city. 5E runs the warehouse/motel Westbank corridor; 5W runs Fort Verde → Concord's distribution-center wall.
- **Loop 8 (Dorado) / Loop 2 (Fort Verde):** each downtown gets its ring; Loop 8's northwest quadrant is **the Canyon** — express lanes trenched *below* the free lanes, our signature double-deck chase geometry.
- **I-2 (southern crosstown):** links the two cities across the bottom of the map, cutting Chalk Ridge in a visible limestone notch. Big-rig heist territory.
- **US-7 (the Trench):** sunken, walled expressway north from downtown through Hyland Glen — cross-bridges = jump/roadblock geometry.
- **Dorado North Tollpike:** the money gradient — Uptown → Grand Emporia → Legend Ranch → Brisco → raw frontier, ending where the sod pallets start.
- **The Gantry (outer toll arc)** + **the Sidewinder (diagonal toll):** the anonymous fast getaway ring across the north half; connects every northern playground.
- **Chisholm Pike:** the road that leaves civilization, exiting southwest through the Tangles.
- **Signature interchanges as monuments:** **the High Ten** (US-7 × Loop 8), **the Tangle** (I-3 × I-5E, framing Dorado's skyline), **the Knot** (I-3 × I-5W, framing Fort Verde's), **the Braid** (24-lane funnel north of DVI), **the Canyon** (Loop 8 double-deck).
- **Frontage roads are the core street grammar** (non-negotiable Texas identity): every freeway gets one-way access roads lined with commerce, plus **Texas-turnaround** U-loops under every overpass — built-in 180° chase reversals, parallel low-speed lanes for shootouts and drive-thrus, and the home of the racing scene: frontage sprints, turnaround drift meets, floodway finals.
- **Toll gantries as a mechanic:** the **Grand Tollway Authority** (canon — the acronym is the joke) photographs plates; blowing gantries builds a *civil* "debt heat" ledger (TagMe push-notification dread, boots, collections NPCs) parallel to police heat.
- **Ring-flow test (DNA #3):** full-map circumnavigation at speed via Loop 2 → SH-83 → Loop 8 → I-2, zero dead ends.

---

## 7. Water & Terrain

- **The Threefork River is the map's spine.** West and Clear forks meet at Fort Verde (Bobcat Island's bypass channel under construction); the river runs east inside the mile-wide leveed **Big Empty** floodway past downtown Dorado (Wishbone + Long-arch bridges overhead); then bends southeast into the **Threefork Bottoms** hardwood swamp, which *is* the map's SE edge. One river ties both cities, the race arena, and the wilderness together.
- **Lakes that survive compression (6):** **Lake Muscadine** (wooded, beside the airport), **Whitechalk Lake** (urban jewel), **Lake Holloway** (hard eastern edge, freeway bridge), **Lake Barlow** (SW, under the escarpment), **Eagle Bluff Lake** (NW — Eagle Mountain + Lake Worth + Benbrook fused; stilt houses, boat bars), **Lake Ludlow** (a northern edge sliver standing in for Lewisville/Ray Roberts). All are dammed reservoirs — dams, marinas, party coves, and drought-exposed lakebeds (summer event: water drops, secrets surface) are content. Cut: everything else.
- **Chalk Ridge escarpment:** the metro's only real relief (100–200 ft) becomes the map's 60–90 m ridge — canyon roads, the Signal Ridge mast farm, the twin-skyline overlook, the I-2 notch. All vertical-terrain gameplay concentrates here by design.
- **The western ranch edge:** past Loop 2 the Tangles' gnarled post-oak scrub simply runs out into ranchland — the GTA V desert-fade trick. No wall needed; the world just stops mattering.
- **The northern edge is the only *growing* edge:** Harvest Hills™ framing lumber, mud roads, model homes, then prairie. Cranes and slab farms read as "the map under construction" — which is the satire.
- **Sky is terrain.** Flat land means the skybox does the topography: supercell anvils, shelf clouds, green-black hail light, siren-day tornado events, ice-storm physics flips, and enormous orange sunsets. All designed vistas face west into golden hour.

---

## 8. Transit as Gameplay

- **MART light rail (canon), 3 lines:** all funnel through the one downtown **Union Terminal transit mall** — a deliberate chokepoint for ambushes, pursuits, and "lose the cops by hopping lines." Stations anchor fast travel (always-available, diegetic — fixes GTA's travel friction per DNA §7.3).
- **The Crossline** (Silver Line-alike): east–west commuter train across the wealth belt, Blando → DVI Terminal B. Rob it, ride it, or use it as a moving meeting room.
- **Threefork Rail Express (TRE):** the dumbbell train between Union Terminal and Fort Verde's T&P-alike — the only transit that crosses the whole map; onboard random events, trackside freight corridor = mission land.
- **Verde Rail:** Fort Verde ↔ Muscadine Main ↔ DVI — the airport escape route when roads are hot.
- **Comedy props:** the free **Mule Line trolley** (slow, charming, hijackable), the **Bluff Streetcar** over the floodway viaduct to Deacon Arts, the **Muscadine Cannonball** steam train to the Brandyards, and DVI's internal **Skyloop**.
- **The gap is the joke:** Middlington — stadium city — has *no transit at all* (true to life). Mechanically: event nights strand crowds, surge-priced **Giddyup** rideshares swarm, and the player's getaway options narrow to rubber and asphalt. Satire canon's MART secession referendum ("Now Serving 40% Fewer Cities") can close a line mid-campaign — transit as a *living* system.

---

## 9. Region Adjacency (ASCII schematic)

```
        N: prairie fade — Salvation / Harvest Hills(tm) frontier — Lake Ludlow sliver
  +----------+-----------+--------------+-----------+--------------+
  | CONCORD  | MUSCADINE |  DVI AIRPORT |  BRISCO   |   frontier   |
  | speedway | main st   | "third city" | the Brand |  (GigaStead, |
  | IronYard | L.Muscad. |  Terminal G  | KidzResrt |  Dam Store)  |
  +----------+-----+-----+------+-------+-----+-----+-----+--------+
  |   THE        (SH-83 Mid-Cities      |  BLANDO   | HYLAND GLEN  |
  |  TANGLES      frontage band)        | LegendRch | + Whitechalk |
  | ranch edge+-----------+-------------+-----+-----+-----+--------+
  | Warhawk   |   FORT    | MIDDLINGTON | LOS ESPEJOS all |  DORADO|
  | HashHollr |   VERDE   |  Ego Dome   +-----------------+ EASTSDE|
  | EagleBluff| Brandyards|  8 Flags    |  DOWNTOWN DORADO| DeepElm|
  |           | SundownSq |  Orb Life   |  Howdy St/Uptown| Fairgnd|
  +-----+-----+-----+-----+------+------+--------+--------+--------+
  | ranch fade SW   |  WESTBANK & FLOODWAY (Threefork R. ->E/SE)   |
  | (Chisholm Pike) +------------+--------------+--------+--------+
  |                 | CHALK RIDGE| OAK BLUFF    | THREEFORK BOTTOMS|
  |                 | SignalRidge| DeaconArts   |  forest (SE edge)|
  +-----------------+------------+--------------+------------------+
        S: escarpment / forest edge          E: Lake Holloway hard edge
                 I-3 spine: FORT VERDE == MIDDLINGTON == DOWNTOWN DORADO
```

**Key adjacencies:** Downtown Dorado touches Uptown/Hyland Glen (N), Eastside (E), Westbank/Floodway (W), Oak Bluff across the river (S). Middlington bridges the two cities on I-3, with DVI/Muscadine due north across the SH-83 band. Los Espejos sits between the airport and downtown Dorado on Mirror Row. Blando → Brisco → frontier stack northward along the Tollpike. Fort Verde's core touches the Brandyards (N), Mimosa/Chisholm U (S), Eagle Bluff (NW), the Tangles (W), Concord (N along I-5W). Chalk Ridge and the Bottoms close the south.

---

## 10. Pacing — Chaos, Quiet, Money Shots

- **Where chaos lives:** Downtown Dorado after dark (club district + police density), Deep Elm at 2 a.m., Middlington on scheduled game/event nights (crowd surges, tailgate seas, zero transit), Brisco's daytime hype economy, the Harmon Hines strip, Concord's industrial night shifts, and the Big Empty on race nights. Fair season turns the Fairgrounds into a two-week chaos event.
- **Where quiet lives:** Whitechalk Lake mornings (sailboats, joggers), Muscadine Main Street, the Tangles, Chalk Ridge trails, the Threefork Bottoms (quiet as in *menacing*), Hyland Glen (quiet-but-hostile: enclave cops), off-season Fairgrounds (Deco ghost town). Every 60–90 seconds of driving changes the register (DNA density-gradient rule).
- **Skybox money shots (all face the sunset unless noted):** (1) Chalk Ridge overlook — both skylines at golden hour, mast lights blinking on; (2) I-3 eastbound at night — the Green Giant and the Lollipop rising off the prairie; (3) the Wishbone over the empty floodway, storm light behind; (4) Founders' Overlook — heavies rotating off DVI against the anvil clouds; (5) Mirror Row at golden hour — towers on fire with reflection; (6) Eagle Bluff stilt bars at dusk; (7) the High Ten's ribbon ramps against a supercell (looks NE — the storm is the sunset here); (8) the Long Bridge over Lake Holloway at dawn (the one east-facing shot).
- **Editorial density:** any 60-second drive should deliver ≥3 satirical reads (billboards from satire canon §3c, frontage signage, radio) — DNA checklist #5.

---

## 11. Vertical Slice: Build Downtown Dorado First

**The slice: Downtown Dorado core + Deep Elm + the Floodway/Wishbone — one contiguous ~2.2 km².**

Why this one:
1. **Hardest tech first.** Dense verticality, crowd + traffic density, interior count, night lighting — if the engine survives the glass canyon, everything else on the map is cheaper. A ranch-edge slice would prove nothing about scale limits.
2. **Maximum system coverage in minimum area.** This slice alone contains: skyline landmark navigation (Lollipop, Green Giant, Prism Court), a signature interchange (the Tangle), elevated freeway + frontage + Texas turnaround grammar, the Overhead above Deep Elm, the Union Terminal transit-mall chokepoint (rideable MART segment), the river/floodway race arena, the Wishbone hero bridge, and three legible districts (glass core / brick nightlife / levee void) in one screenshot-testable band.
3. **Satire is playable day one.** Howdy Street + the Texchange, the Convention Crater, billboards, and two radio stations exercise the thesis before any mission exists.
4. **It's the calibration standard.** Every other district's density, palette, and audio get tuned *against* the core — the orientation beacon must exist before the things that orient to it.
5. **Directly scoreable** against DNA checklist #1 (point at downtown, HUD off), #2 (name the district from a screenshot), #5 (three satirical reads per minute), #12 (crash → cops → peds chain), and a mini ring-flow test on the Tangle–Overhead–Woodall-alike loop.

**Runner-up (slice 2): the Brandyards.** It is the map's most *unique* identity — longhorn traffic events, Wild Wanda's interior, rodeo crowd systems — and the strongest demo-wow per square meter, but it proves art direction rather than systems at scale. Build it second, as the proof that the second city feels like a different game.

**Slice exit criteria:** 30 minutes of free-roam produces one unscripted "tell someone" moment (DNA #13) inside the slice boundary.

---

## Next docs this canon feeds
1. **World-building doc:** lock city/metro names (§3 options), define police factions per city, radio-station-to-region mapping.
2. **District art bibles:** one per region, starting with Downtown Dorado (slice) — palette, kit list, signage set.
3. **Mission-geography doc:** map the prep→execute loop onto specific POIs (Texchange, DVI cargo, Warhawk, Museum Mile).
