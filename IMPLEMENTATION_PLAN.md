# Implementation Plan — The Interesting-Decisions Milestone (M8)

**Source docs:** `GAMEPLAY_PATHS.md` (loop meaning · Path B recommended, Path A riders),
`COMBAT_FEATURES.md` (verb catalog · bullet-time route chosen), `WORLD_DESIGN.md` (world
systems). This document turns those into an ordered burn-down of shippable batches. Each batch
is one branch → tests → merge. Boxes get checked as batches land.

## Ground rules (unchanged, non-negotiable)

- Covenant holds: sim stays pure/deterministic; all new randomness through the sim RNG; all
  tuning in `content/`; view reads state and forwards Commands only.
- Every batch merges only with `test_determinism.gd`, `test_ghost_replay.gd`, and
  `test_reveal_discipline.gd` green plus a clean headless boot.
- Every new player-facing string obeys reveal discipline (human-military vocabulary pre-L3).
- Architectural choices get `DECISIONS.md` entries per batch.

## The design in one paragraph

Enemies gain telegraphed, committed attacks (knowledge becomes readable); the assault becomes
a scripted timeline with artillery that remodels the terrain (knowledge becomes valuable); the
player gains a bullet-time resource to read with, and mines/decoys to spend knowledge on; the
world becomes a wider, banded beach with fixtures worth walking to; loot splits into permanent
(schematics via deep caches, tree via fragments), per-run (salvage buffs from elites/caches),
and knowledge (schedule/death sense from surviving/dying). Later milestones grow echoes
(Path B), the full stall, and the anomaly budget on top of this substrate.

## Economy & permanence (decided)

- **Permanent, fragment-bought:** sentience tree (exists, unchanged).
- **Permanent, location-earned:** schematics — reaching + opening a deep cache once unlocks
  that gear in the Between loadout forever (first: the mine dispenser). Stored in `RunMeta`
  like intel; the sim only reports "cache N opened this run" in end-of-run state.
- **Per-run, dropped:** salvage pickups from elites and caches — repair kit (+20 HP),
  overcharge (+fire rate, rest of run), mine restock (+2). Drop rolls in the sim via seeded
  RNG at kill/open time; pickups are sim entities, contact-collected.
- **Per-run, terrain:** craters, rubble, wrecks — the war builds them, the reset clears them.
- **Knowledge, free but earned:** schedule sense (survive a wave once → its preview banner
  shows forever), death sense (die to a type → its telegraphs render early/bright), fixture
  locations. Lives in `RunMeta`; rendered by the view; sim never knows.

## Burn-down

### ✅ B0 — Design docs & this plan
`WORLD_DESIGN.md`, `IMPLEMENTATION_PLAN.md`, cross-links. Merged first so the plan itself is
in history.

### ☐ B1 — Telegraph framework + enemy rework *(sim, content, view)*
The keystone: enemies get a windup → committed → recover attack state machine, per-type data
in `enemies.json`.
- Drone: short orbit approach, then a telegraphed **dive** along a committed line (drawn
  during windup), long recovery.
- Infantry: committed **3-round volley** (tracer line during windup) then a visible reload
  window; volleys lead the player slightly.
- Heavy: telegraphed **ring slam** (expanding ring indicator) with knockback that also
  shatters adjacent blocks — the first "the enemy edits the map" moment.
- `SimState.Enemy` gains `phase/phase_ticks/attack_dir` (serialize contract grows).
- View: windup/commit indicators drawn from state (no new sim events, diff-based juice as
  established).
**Accept:** every lethal enemy action is visible ≥ 0.4 s before it lands; determinism green.

### ☐ B2 — Assault script: artillery events + flank entries + craters *(sim, content, view)*
`waves.json` grows an `events` timeline alongside waves.
- **Artillery barrage** events: impact circles telegraphed ~2 s, then AoE damage and a
  permanent-for-the-run **crater** (rough ground: slows all ground movers inside).
- **Flank entry** events: squads entering from authored left/right edges at scripted ticks
  (spawn edges become data; today everything spawns top).
- Craters are new sim terrain (`SimState.craters`), capping the slow so stacking stays sane.
**Accept:** wave 3+ has at least one barrage and one flank on the authored timeline; craters
visibly reshape routes; determinism green.

### ☐ B3 — The held breath: reflex slow + telegraph hitch *(view only)*
- Hold input (Shift / L2 / touch button) drains a meter and steps the sim at ¼ wall-clock
  rate; meter regenerates slowly while unused. Pure view-side pacing (pause/hit-stop
  precedent): command logs stay 1:1 with ticks, ghosts/replays untouched.
- Auto-hitch: ~0.15 s of hit-stop the first moment a *new* telegraph appears on screen
  (diff-based detection), as the free tutorializer.
- HUD meter; strings via `strings.json`; pre-L3 name: **HELD BREATH**.
**Accept:** slow-mo feels deliberate, meter economy forces choices, replay test still green.

### ☐ B4 — The wider beach: camera + zone bands + rubble *(sim, content, view)*
- Arena grows to ~2560×1080 (data change); view gains a follow camera with aim lookahead;
  overlay/touch untouched (already on `CanvasLayer`).
- **Surf band** (top): all ground movement slowed; per-seed **tide level** sets its depth.
- **Seawall line**: authored high-HP cover segments mid-map.
- **Rubble**: destroyed blocks/seawall leave slow-patches instead of vanishing (cover
  economy: authored decays → improvised remains).
- Background renders bands + haze at world edges (horizon fiction seeded, gating later).
**Accept:** the map reads as sea → sand → seawall → flats → trench; camera clean at edges;
determinism green.

### ☐ B5 — Fixtures & loot: caches, salvage, the mine dispenser *(sim, content, view, meta)*
- **Supply caches** (per-seed placement from authored candidate sites): shoot the lock →
  salvage pickups (repair / overcharge / mine restock). Elites (heavy+) roll a salvage drop.
- **Schematic cache** (one, deep and far): first opening permanently unlocks the **mine
  dispenser** in the Between loadout (`RunMeta`, intel-style banking from end-of-run state).
- **Mines**: `Command.place_mine`; limited stock; arm delay; proximity AoE. The knowledge
  weapon — placed where you know they'll walk.
**Accept:** a run can find, earn, and use mines; unlock survives across runs and slots; all
tests green.

### ☐ B6 — New enemy roles: lancer, mortar section, sapper *(sim, content, view)*
- **Lancer**: telegraphed line charge, long vulnerable recovery (phase-step/dodge check).
- **Mortar section**: emplaced spawner that fires scheduled barrages (B2's event tech, now
  killable on the map — walking to it is a tactical objective).
- **Sapper**: ignores the player, demolishes seawall/blocks; its path announces the breach.
- Wave/script data extended so roles appear on the authored timeline.
**Accept:** each new type creates a distinct decision; wave 4+ mixes roles; tests green.

### ☐ B7 — Knowledge layers: schedule sense + death sense *(view/meta only)*
- **Schedule sense**: waves you have survived before show a pre-wave banner (composition +
  entry edges). Per-slot in `RunMeta`.
- **Death sense**: enemy types that have killed you render their telegraphs earlier and
  brighter; mortar impact previews show only for barrages that have killed you.
- Death panel names what this death taught (string additions, reveal-linted).
**Accept:** a veteran's screen visibly out-informs a rookie's on the same seed; sim untouched.

### ☐ B8 — Decoy echo + enemy targeting *(sim, content, view)*
- Enemies target "nearest attention object" (player or decoy) instead of hardcoded player —
  the multi-body seam Path B needs, cut here.
- **Decoy echo** ability (`Command.decoy`, cooldown + charge): static afterimage with HP that
  draws aggro; enemies volley it, teaching their patterns safely. Echo fiction begins.
**Accept:** decoy redirects each archetype correctly; determinism green.

### Parked next (in intended order, not tonight)
- **P1 — Echo Platoon prototype** (GAMEPLAY_PATHS Path B): 2-life sortie, echoes as mortal
  command-log bodies; targeting seam from B8 makes this mostly command-routing work.
- **P2 — Full stall tier** (order queue inside frozen time) on the held-breath meter.
- **P3 — Wrecks & landing craft** (kill-early/kill-late cover economy), gun emplacement,
  comm relay, munition dumps.
- **P4 — Horizon gating** (Cognition-locked play-space rings) once fixtures give expansion
  content.
- **P5 — The Stalker** (your previous run's log as a hostile) + doctrine adaptation
  (meta-fed `setup()` profile) — proto-suspicion.
- **P6 — Salvage depth** (more mod types, rarity), second schematic (rail lance), tree
  branches gaining verb tiers (phase-step on Authority, meter size on Cognition).

## Batch mechanics

Branch `claude/m8-b<N>-<slug>` per batch → implement → run all three tests + headless boot →
merge to `main` (no-ff, batch-scoped message) → push. If a batch fails tests in a way that
can't be fixed within the session, it is dropped, not merged broken.
