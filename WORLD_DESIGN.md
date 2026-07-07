# World Design — Making the Beach a Place

**Status:** options document, companion to `GAMEPLAY_PATHS.md` (what the loop means) and
`COMBAT_FEATURES.md` (the verb catalog). This one is about the *stage*: today the world is a
single fixed rectangle with eight destructible blocks that are usually gone by wave 3, and no
spatial decision survives past the first minute. The scope covenant says ONE map — so the answer
is never "more maps"; it is making the one beach larger, deeper, reactive, and differently
readable every run.

## 1. The five world systems

### A. The render horizon — the world grows with your mind

The beach is authored much wider than the starting play space (target: ~3 screens wide, 1.5
deep). At first you fight inside a narrow slice; beyond its edges the world dissolves into
haze/static — pre-L2 fiction: shell-shock tunnel vision, the war shrinking to what you can hold;
post-L2 retcon: the scenario's render bounds, and your allotment of it. **Cognition tiers push
the horizon outward permanently.** New ground is not empty: each expansion ring contains authored
fixtures (Section D) — the far cache, the flanking route, the emplacement — so buying cognition
*literally buys world*. Enemies always existed out there (mortar fire arcs in from beyond the
haze before you can see its source), so expansion also converts known threats into reachable
ones. No other roguelite grows its map as a stat; ours can because the map's partiality is canon.

### B. Zone bands — depth means something

The beach is a gradient from sea (top) to trench (bottom), and each band has physics that verbs
and enemies interact with:

- **The surf** — movement slowed for everything in it; landing craft ground here; morale-broken
  enemies flee into it (slowed, exposed). Flak knockback shoves attackers back into the water.
  Tide level (per-seed parameter) decides how deep this band reaches — changing which routes and
  fixtures are wet run to run.
- **Open sand** — fast, exposed, mortar-registered (artillery events target registration zones
  here). The fragment-rich hot zones sit in it: greed happens under the guns.
- **The seawall line** — a broken line of authored high-HP cover segments: the spine of every
  defensive plan, and the sappers' primary target.
- **The flats** — the current block field: scattered light cover, the mid game of every wave.
- **The trench line** — player spawn, hard cover shoulders, the fallback position. Being pushed
  back to the trench should feel like losing ground, not like camping.

### C. The war remodels the map — run-scale evolution

The answer to "the barriers are gone by wave 3" is not tougher barriers; it is a **cover
economy** where authored cover decays while improvised cover accumulates:

- **Craters.** Every artillery impact leaves a crater: rough ground that slows ground units
  (players and enemies both) and catches mines nicely. The barrage that nearly killed you also
  redrew the map.
- **Rubble.** Destroyed blocks and seawall segments collapse into rubble patches (slow zone,
  no projectile cover) instead of vanishing — degraded, not deleted.
- **Wrecks.** Heavies and landing craft leave hull wrecks on death: *new* full cover, placed
  by where you chose to kill them. Killing a landing craft in deep surf drowns its cargo but
  wastes the wreck; letting it beach gives you the wreck and the fight. By wave 8 the beach is
  a labyrinth the player co-authored with the artillery.
- **Breaches.** Sappers demolish specific seawall segments (their pathing announces the target),
  opening lanes the assault script then exploits — losing a wall changes *their* plan, not just
  your HP odds.

### D. Fixtures — things on the map worth walking to

Every fixture is a positional decision generator (go there, under fire, or don't):

- **Supply caches** — authored crates; crack them (shoot the lock or channel briefly) for
  salvage pickups (Section 3). Positions drawn per-seed from authored candidate sites.
- **Schematic caches** — deep, far, badly placed on purpose. Opening one the *first* time
  permanently adds a weapon/gear option to the Between loadout (the mine dispenser, the rail
  lance...). Acquisition is location knowledge: the Outer Wilds move, done with loot.
- **The gun emplacement** — a fixed heavy gun; stand at it to man it (huge damage, no
  mobility, you are a spotter's dream). Manning/abandoning it is a live tactical toggle.
- **The comm relay** — channel at it to intercept the assault plan: reveals the next two
  waves' composition and entry edges. Schedule-sense as a map verb — intel costs standing
  still in the open.
- **Munition dumps** — shoot to detonate: massive AoE that also deletes nearby cover, yours
  included. The classic double-edged barrel, placed where the temptation hurts.
- **The still pool** *(late Act 1, rare)* — a shimmer where the world hangs wrong (the Between
  leaking into the battle). Standing in it refills the held-breath meter. First diegetic
  breadcrumb that the frozen seconds are *a place*.

### E. Seed parameters & the anomaly budget — different reads, then authored edits

Per-seed scenario parameters (all canon-justified as scenario variation): tide level, fog
events on the timeline, mortar registration zones, cache site draws, breach points, entry
edges. Same beach, different plan every run — parametric variation per the covenant.

Later (Act 2 material, designed now so nothing blocks it): the **anomaly budget** from
VISION.md's battle loop — spend heavily in the Between to make *persistent* edits to the
scenario itself: a seawall segment that was "always there," a pre-registered friendly barrage
at tick 5400, a cache relocated closer. Pre-L3 these read as scavenged preparations the curse
preserves; post-L3 they are what they are — tampering with the script. Anomalies are the
natural suspicion currency for Act 2: every edit is a thing the overseers might notice.

## 2. Interaction weave (why these aren't five separate features)

- Artillery (script) → craters (world) → slow zones that catch enemies → mine placement (verb)
  gets a natural home; flak (verb) shoves divers into craters.
- Sappers (enemy) → breach the seawall (world) → the script's next flank uses the gap →
  requisition-cover (verb) can plug it — terrain as a contested resource, both sides editing it.
- Landing craft (script) → kill early = drowned cargo / kill late = wreck cover (world) → wreck
  position feeds the *next* wave's fight; spotters climb wrecks for range.
- Tide (seed) → decides whether the west cache is wet (slow approach) → changes whether the
  emplacement or the relay is the wave-4 play → knowledge of this seed's tide is itself loot.
- Horizon expansion (meta) → reveals the mortar sections that were always shelling you → makes
  the artillery *killable*, converting a script event into a tactical objective.

## 3. Acquisition, permanence, and the economy

Three currencies/permanence tiers, extending what already exists (fragments + tree, intel):

| Tier | What | How acquired | Examples |
|---|---|---|---|
| **Permanent** | Sentience tree (exists); schematics; horizon rings; anomalies (later) | Fragments at the tree; reaching schematic caches once; Cognition tiers; anomaly budget | Hull, fire rate; mine dispenser unlock; play-space expansion; the extra seawall |
| **Per-run** | Salvage buffs; mine stock; manned guns; craters/rubble/wrecks | Drops from elites & caches (sim RNG, deterministic); fixtures used in the moment | +fire-rate overcharge, repair kit, mine restock; everything the war builds and breaks |
| **Knowledge** | Schedule sense; death sense; fixture locations; tide/fog reads | Surviving waves; dying to types; having walked there before | "wave 4 flanks left"; visible mortar impact previews; "the far cache exists" |

Loot drop rules (determinism-clean): drop rolls happen in the sim via the seeded RNG at kill
time; pickups are sim entities collected by contact; their effects mutate run state only.
Nothing persistent is written by the sim — the view/meta layer reads end-of-run state and banks
schematics/knowledge, exactly like fragments today.

## 4. What this fixes

Wave 3 today: cover gone, open rectangle, kite forever. Wave 3 with these systems: the seawall
is breached on the left, two craters slow the middle, the first heavy's wreck sits where you
dropped it guarding the trench approach, the tide is out so the east cache is dry, the comm
relay says wave 4 comes in on the west edge with a lancer screen — and you have two mines left
and a decision to make. Same beach. An actual place, with an actual plan happening on it.
