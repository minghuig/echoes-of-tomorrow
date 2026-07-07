# Combat Features & the Tempo Decision

**Status:** options document, companion to `GAMEPLAY_PATHS.md`. That doc chose *what the loop
means*; this one catalogs the verbs (player and enemy) that make moment-to-moment decisions
interesting, and answers the question that gates all of them: **real-time, bullet-time, or
turn-based?**

## 0. The gating insight: tempo sets the verb budget

A feature roster is only as big as the player's decision bandwidth. In pure real-time, a human
can juggle roughly *move + aim + fire + two cooldowns* before extra verbs become noise —
which is why Hades ships four abilities, not fourteen. Every step toward stopped time raises
the ceiling: slow-motion roughly doubles it; a full pause removes it. So "add more weapons and
abilities" and "pick a tempo" are the same decision. The catalog below tags every feature with
its fit per route:

- **RT** — pure real-time (current game, Hades hands)
- **BT** — bullet-time hybrid: real-time baseline plus a scarce, diegetic slow/stall resource
- **TB** — turn-based / WEGO: plan, then the sim executes a fixed tick burst

Ratings: ★★★ shines · ★★☆ works · ★☆☆ strained.

**Architecture note that shapes the whole decision:** under the sim/view covenant, bullet-time
is *almost free*. The sim only ever advances via `step()` at logical 60Hz — nothing says the
view must call it 60 times per wall-clock second. Slow-motion is the view stepping the sim
less often; a full stall is the existing pause/hit-stop precedent. Command logs stay 1:1 with
ticks, determinism and ghosts are untouched, and the sim never learns bullet-time exists.
Turn-based is also implementable on the same sim (a "turn" = plan → compile to commands →
execute 60 ticks), but its real costs are UI and genre identity, not architecture.

---

## 1. Player — movement verbs

**M1. Combat dash** *(exists)* — i-frame burst. The bread-and-butter reflex verb.
`RT ★★★ · BT ★★★ · TB ★☆☆` (turn-based reduces it to a defensive stat).

**M2. Vault** — hop over a block in your move direction; enemies (except drones) can't follow.
Makes terrain a movement network instead of an obstacle course; cheap to build.
`RT ★★★ · BT ★★★ · TB ★★★`

**M3. Phase-step** — short teleport through enemies and shots, long cooldown. Pre-L3 fiction:
a curse-flicker ("you were somehow already there"). The premium escape you save for the charge
you *know* is coming — a knowledge check in a button.
`RT ★★☆ · BT ★★★ · TB ★★☆`

**M4. Brace stance** — hold to plant: heavy frontal damage reduction, +pierce/accuracy, no
movement. Turns positioning into a commitment decision and pairs with cover.
`RT ★★☆ · BT ★★★ · TB ★★★`

**M5. Recall** — snap back to where you stood ~2 seconds ago (position only, not HP).
Deterministic via a small ring buffer of past player positions in `SimState`. Pre-L3: the
curse pulls you backward. The signature loop-flavored movement verb: overextend, strike,
un-happen the overextension.
`RT ★★☆ · BT ★★★ · TB ★★☆`

## 2. Player — weapons (two-slot loadout, chosen in the Between)

**W1. Service rifle** *(exists)* — baseline. `RT ★★★ · BT ★★★ · TB ★★★`

**W2. Rail lance** — charged piercing line; visible windup, punishes you if interrupted.
Built for known geometry: shield-bearers, charge lanes, enemies queued in a choke. The
foresight weapon.
`RT ★★☆ · BT ★★★ · TB ★★★`

**W3. Flak sweep** — short-range cone with knockback. The crowd/panic verb and the drone
answer; also shoves enemies into mines and mortar zones (combo engine).
`RT ★★★ · BT ★★★ · TB ★★☆`

**W4. Mortar tube** — lobbed AoE over blocks, delayed impact, telegraphed to *you*. Mirrors
the enemy artillery; awkward to aim at speed, natural under slow/stall.
`RT ★☆☆ · BT ★★★ · TB ★★★`

**W5. Seeker darts** — lock-on volley, small damage per dart; lock time per target. The
spotter/officer assassination tool: kill-order made mechanical.
`RT ★★☆ · BT ★★★ · TB ★★★`

**W6. Beam projector** — continuous, damage ramps while held on one target, slows you to a
crawl. Brace-synergy boss-killer; a commitment decision every time.
`RT ★★☆ · BT ★★☆ · TB ★☆☆`

**W7. Proximity mines** *(limited stock per life)* — **the Edge-of-Tomorrow weapon.** Worthless
without knowledge, devastating with it: you place them where you *know* the flankers enter at
wave 3. Every mine placement is banked foresight. Cheap to build, huge loop payoff.
`RT ★★★ · BT ★★★ · TB ★★★`

**W8. Auto-turret** *(deployable, limited)* — holds a zone, draws fire, dies. Pre-Commander
taste of "the battlefield fights for me"; pairs with mark-target.
`RT ★★☆ · BT ★★★ · TB ★★★`

## 3. Player — tactical abilities (sentience-tree gated)

**A1. The held breath** — the bullet-time resource itself (see Section 6): a meter of stolen
time, spent as slow-motion (or full stall, route-dependent). Pre-L3: the world hangs the way
it did in that first impossible glitch. Grows on the Cognition branch until, acts later, it
*is* the Director's frozen choreography.
`RT — · BT ★★★ (defining) · TB — (implicit)`

**A2. Shield surge** — brief bubble that stops projectiles but not contact. The barrage
answer when repositioning isn't possible; protects braced/beaming players.
`RT ★★★ · BT ★★★ · TB ★★☆`

**A3. Decoy echo** — plant a static afterimage that draws aggro for a few seconds. Doubles as
an *intel instrument*: enemies attack it, and you watch their fire patterns from safety —
learning without dying. Lore-free ammunition for the echo fiction.
`RT ★★★ · BT ★★★ · TB ★★☆`

**A4. Pulse jam** — radial interrupt: cancels all enemy windups and resets committed attacks
in range; long cooldown. The counter you time against a *known* volley. Pre-L3: a scavenged
alien disruptor.
`RT ★★☆ · BT ★★★ · TB ★★★`

**A5. Mark target** — paint one enemy; turrets, echoes, and (later) allies focus it. The
Authority branch's first rung — command vocabulary smuggled in as a targeting laser.
`RT ★★★ · BT ★★★ · TB ★★★`

**A6. Requisition cover** — raise a fresh block (limited charges). Terrain editing: build the
choke you wish existed, plug the gap the sappers made. Pre-L3: field fortification.
`RT ★★☆ · BT ★★★ · TB ★★★`

**A7. Commandeer** *(late, Authority deep)* — capture one enemy drone for the rest of the
wave. Pre-L3: a captured control beacon. The Director endgame in miniature; also the first
time the player *feels* the other side is drivable.
`RT ★★☆ · BT ★★★ · TB ★★★`

## 4. Enemy roster (each entry = one decision + one knowledge check)

Existing three, reworked for telegraphs:

**E1. Drone** *(exists)* — swarmer. Rework: brief orbit before a committed dive along a drawn
line. Dodge-bait becomes readable.

**E2. Infantry** *(exists)* — rework: fires committed 3-round volleys with tracer telegraph,
then reloads (a visible window). Volley timing is learnable; the reload is the answer.

**E3. Heavy** *(exists)* — rework: slow tank with a telegraphed ring-shockwave slam that
shatters nearby cover. You choose: burn it down at range or bait the slam away from your wall.

New roles (rough unlock order down the acts):

**E4. Lancer** — telegraphed charge along a committed line; long vulnerable recovery. The
phase-step/vault check.

**E5. Mortar section** — emplaced artillery; impact circles appear seconds ahead (to those
who've died to them). Attacks *positions*, forcing movement; the anti-camping metronome.

**E6. Shield-bearer** — directional tower shield, immune from the front. Forces a flank, a
vault, or a rail-lance pierce. Walks in front of infantry volleys (formation seed).

**E7. Spotter** — paints you with a visible beam; painted = every enemy leads its shots.
Priority-target decision every time one crests the dune.

**E8. Warden (officer)** — aura-buffs nearby enemies; on death, the wave *falters* (drones
scatter, infantry breaks volley discipline for a few seconds). Kill-order goldmine; the
morale system's anchor.

**E9. Sapper** — ignores you; demolishes blocks/your requisitioned cover. Attacks your
*plan* rather than your body — the terrain-investment tax.

**E10. Bomber** — arcing lobs over cover. The anti-turtle answer; pairs cruelly with E6
fronts.

**E11. Sniper** — long laser-sight telegraph, near-lethal hit, relocates after firing.
Punishes standing still; countered by timing, decoys, cover lines.

**E12. Repair drone** — heals mechanicals, flees when targeted. Classic priority puzzle.

**E13. The Stalker** *(Act 2 flavor, late)* — an enemy that replays **your own recorded
movement and fire patterns from a previous run** against you. Built entirely from tech we
already have (a command log driving a hostile body; fed in at `setup()`, so determinism
holds). Lore payload: *they are learning you too* — and post-L3 it reads as the training
system doing exactly what training systems do. The mirror-match nobody else can ship this
cheaply.

## 5. Enemy & battlefield systems

**S1. The authored assault script** *(prerequisite — GAMEPLAY_PATHS.md §1)* — set-piece
timeline per seed: barrages, flank entries, landing craft, fog pulses.

**S2. Formations** — shield-bearers front, infantry volleying from behind, wardens centered;
scripted pincers on the timeline. Formations are *shapes*, and shapes are knowledge: learnable,
flankable, minable.

**S3. Morale** — officer death, echo intimidation, or overwhelming losses cause falter states
(scatter, retreat to the surf, dropped formation). Gives kills second-order value and makes
"who dies first" the tactical question.

**S4. Doctrine adaptation** — between runs, the *trainers* adjust the script against your
habits: camp the same choke three runs and wave 4 gains bombers; overuse the left flank and
the mortars pre-register it. Implementation is covenant-clean: the meta layer feeds an
"adaptation profile" into `SimCore.setup()` as data, so a run is still exactly reproducible
from its inputs. This is the Edge-of-Tomorrow loop running *both directions* — and it is
proto-suspicion: the Act 2 "you're being watched" system germinating inside Act 1 mechanics.

**S5. Living terrain** — surf slows movement at the waterline (landing-zone pressure);
authored cover lines with destructible seawalls; fragment-rich hot zones sitting exposed under
the mortars (greed vs. safety, every run).

---

## 6. The tempo decision: real-time vs. bullet-time vs. turn-based

### Route 1 — Pure real-time (status quo, harder)

Hades proves the ceiling is high — but Hades spends *years* of feel-tuning to make four verbs
deep. Our complexity budget: 2 weapons + 2 abilities + dash, everything else must live in
**pre-run planning** (loadout, mine placement, route intentions) and enemy design. Knowledge
expresses as reflex ("I know the volley timing") and preparation, never contemplation. The
Slay-the-Spire-style intent display barely fits: no time to read it.

- **Gets us:** action purity, minimal new systems, all juice investment kept.
- **Costs us:** most of the catalog above is uninstallable (W4, W5, A4, A6, A7 strain);
  Commander/Director phases will eventually force a tempo change *anyway* — deferred, not
  avoided.
- **Verdict:** viable only if we accept a small verb set forever.

### Route 2 — Bullet-time hybrid ("the held breath") — **recommended**

Real-time baseline with a scarce diegetic time resource, in two tiers:

1. **Reflex slow** *(cheap tier)* — hold to drop the view's sim-step rate to ~25%; meter
   drains. Aim the mortar, read the intent pips, thread the volley. Optionally auto-pulsed
   for a half-second when a new telegraph appears ("the world hitches when death looks at
   you" — a beautiful pre-L3 line and a free tutorializer).
2. **Full stall** *(deep tier, later acts)* — meter-capped complete freeze with order-queuing
   (GAMEPLAY_PATHS.md Path C), unlocked up the Cognition branch. The stall *grows into*
   Commander/Director play; no second tempo migration ever needed.

- **Gets us:** the verb ceiling roughly doubles immediately (the full catalog installs);
  enemy-intent display becomes readable (deterministic lookahead, shown honestly); echoes
  (Path B) become coordinable; gamepad and touch stay first-class (slow-mo is the great
  input equalizer); the tempo verb *is the story's central image* (stolen time).
- **Costs us:** meter economy is a real tuning burden; slow-mo audio/visual treatment is a
  feel pass of its own; risk of players resenting a "mandatory" crutch (mitigate: meter is
  generous early, and pure-reflex play remains possible for style points).
- **Architecture:** nearly free (view-side step pacing; pause precedent already merged).
- **Verdict:** the only route where the loop fantasy, the verb catalog, the phase ladder,
  and the existing action game all fit in one tempo.

### Route 3 — Turn-based / WEGO

Frozen-Synapse-style: plan simultaneous orders, execute a 1-second (60-tick) burst, repeat.
Maximum decision density; every feature above installs trivially; intent display becomes the
whole game (Into the Breach).

- **Gets us:** deepest tactics, easiest balancing, lowest execution-skill floor.
- **Costs us:** the action game we've built (dodge, aim, juice — all demoted or deleted);
  the Hades-feel pillar; run pacing balloons (8–12 min battles become 25+); tactical order
  UI is the *most* expensive UI of the three routes, on gamepad and touch especially; and the
  genre's audience expects content breadth (maps, units) that our one-beach covenant refuses.
- **Verdict:** a different, worthy game — but it abandons more than it adds, and the stall
  tier of Route 2 captures most of its decision density without the genre reset.

### Recommendation

**Route 2.** Ship the reflex slow early (it is days of work under this architecture, not
weeks), grow it into the full stall along the Cognition branch, and let turn-based die as a
route by making its virtues (readable intent, unhurried decisions, multi-unit orders)
unlockable *inside* the real-time game. This also settles GAMEPLAY_PATHS.md cleanly: Path B
(echoes) remains the core-loop bet, Path A's knowledge layers render inside the slow, and
Path C stops being a separate path — it's just what the held breath becomes by Act 3.

## 7. Suggested first slice (next milestone bite)

Everything above is a menu, not a backlog. A coherent first bite that proves the tempo and
the decision density together:

- **Tempo:** reflex slow (A1 tier 1) with a visible meter.
- **Movement:** dash *(kept)* + vault (M2).
- **Weapons:** rifle *(kept)* + proximity mines (W7) as the second slot.
- **Ability:** decoy echo (A3).
- **Enemies:** reworked drone dive + infantry volley (E1/E2 telegraphs), plus lancer (E4)
  and mortar section (E5).
- **Systems:** assault script v1 (S1) — three authored waves with one artillery event and
  one flank entry.

That slice makes every death teach something (volley timing, dive tells, barrage schedule,
flank tick), gives knowledge two spending outlets (mine placement, slow-time usage), and
keeps total new sim surface small enough to hold the determinism line comfortably.
