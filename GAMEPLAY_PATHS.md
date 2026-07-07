# Gameplay Paths — Making the Loop Matter

**Status:** options document, no decision taken. When a path (or combination) is chosen, it gets a dated entry in `DECISIONS.md`.

## 0. The problem

The core loop currently plays as a competent arcade survival game — and that is the problem. The
fantasy we promised (VISION.md, Act 1) is *Edge of Tomorrow*: every death converts into actionable
knowledge of what the enemy will do, so the veteran of forty loops plays a visibly different game
than the rookie of loop one. Today that conversion doesn't happen, because knowledge only matters
when three conditions hold, and the current beach fails all three:

1. **The future must be knowable.** Enemies stream toward the player and react only to the
   player's position. There is no schedule, no set-piece, no committed attack — nothing stable
   enough to *know*.
2. **Ignorance must be lethal.** Nothing in the current assault punishes a player for not knowing
   what comes next; it punishes weak aim and slow feet. Dying teaches you nothing except "shoot
   faster."
3. **Knowledge must be exploitable.** Even if you knew wave 5's composition cold, there is no
   decision that knowledge changes — no positioning choice, no loadout choice, no timing choice.
   The optimal play is always "kite and shoot."

Related gap: the vision's control-phase ladder (Soldier → Ghost → Commander → Director) implies a
battlefield with multiple friendly bodies and a growing command vocabulary. The current sim has
exactly one player-shaped entity, so none of that ladder has anywhere to stand yet.

The three paths below each fix the knowledge loop a different way. They share one prerequisite
(Section 1) and one architectural gift: because the sim is strictly deterministic and re-runnable
from `(seed, loadout, command_log)`, *the future of a run is computable*. Almost no other game can
truthfully show the player what is about to happen; we can, cheaply, by stepping a cloned sim
forward. Every path leans on that unfair advantage somewhere.

---

## 1. Shared foundation: the authored assault (prerequisite for every path)

Whatever path we choose, the beach must stop being a faucet of homogeneous pressure and become a
**script** — a per-seed authored assault timeline with events worth knowing about. This is Act 1
lore made mechanical: the battle *is* a script (it's a training scenario; the player just doesn't
know that yet), so it is canon-correct for the assault to be fixed, learnable, and only
parametrically varied between seeds.

Concretely (all data in `content/`, per the covenant):

- **Set-piece events on the timeline**, not just spawn batches: artillery barrages with impact
  zones computed at schedule time; flanker squads entering from a specific edge at a specific
  tick; a shielded officer whose death breaks a wave; a landing craft that disgorges a heavy
  squad at the water line; a fog pulse that kills visibility for 10 seconds. Each event is a
  thing you die to once and route around forever.
- **Committed, telegraphed enemy attacks.** Every dangerous action gets a windup measured in
  ticks and a commitment window (the mortar *will* land there; the lancer *will* charge along
  that line). Hollow Knight's lesson: telegraphs make death feel like tuition, not theft.
  Reactive micro-movement stays, but lethality moves into committed attacks.
- **Enemy roles beyond "approach and touch":** suppressors that deny an area, bombers that arc
  shots over blocks, shield-bearers that force flanks, spotters that upgrade other enemies'
  accuracy until killed. Roles create the "kill order" and "positioning" decisions that pure
  chasers never can.
- **Terrain that participates:** blocks already exist; add authored cover lines, a choke, a
  high-value exposed zone (where the fragments are rich but the artillery falls). Risk/position
  trade-offs are the cheapest decision generator in the genre.

Estimated cost: content design plus a moderate `sim_core.gd` extension (event queue beside
`pending_spawns`, windup/commit states on enemies). No covenant risk. **This is worth doing even
if we adopted no path at all** — but on its own it only fixes condition 1 and half of 2; the paths
below fix 3.

---

## 2. Path A — **Premonition** (real-time action + true foresight)

*Keep the Hades-feel action game. Deaths grant literal, honest precognition — rendered from
forward-simulation of the deterministic sim.*

### The fantasy

Loop 12. The mortar section hasn't fired yet, but you already see the three impact circles
blooming on the sand — you've died to this barrage twice, and now your body knows. A faint ghost
of the lancer's charge line draws itself a full second before his legs move. You stand in the one
gap that will exist in the crossfire, because for you it isn't prediction. It's memory.

### Lore fit

Pre-L3 this is **battle instinct / déjà vu**: the curse hardening into premononition, named in
human terms ("you've seen this before"). The sentience tree's Cognition branch grows it. Post-L3
it renames to what it really is — you are reading ahead in the training script; the lookahead
buffer was always there, you just gained access. This is the cleanest possible mechanics-as-story
fit for an AI protagonist: *of course* the machine can read the schedule. Reveal discipline is
easy to hold because every overlay wears a human name first.

### Core mechanics

- **Layer 1 — Schedule sense (unlocked by surviving).** Reaching wave N on a seed permanently
  reveals the assault script up to N+1 on future runs of that seed family: pre-wave banners,
  spawn-edge arrows, event countdowns. This is the *Edge of Tomorrow* "I know what comes next"
  queue — and it is sound where the Slay-the-Spire-intent queue was not, because the *schedule*
  is fixed per seed even though enemy micro-behavior reacts to you. You learn the invasion plan,
  not the soldiers' footsteps.
- **Layer 2 — Death sense (unlocked by dying).** Dying to an enemy type unlocks its telegraph
  overlay: windup indicators, committed-attack paths, danger zones, drawn a beat before they
  resolve. First death to the mortar is blind; every death after, you see the circles.
- **Layer 3 — The read (unlocked deep in Cognition).** Hold a button to see 1–2 seconds of
  actual future: a cloned `SimCore` steps ahead from current state (assuming your inputs
  continue), and enemy positions/shots render as fading ghost trails. Because it is recomputed
  continuously, it *reacts to you* — sidestep and the forecast redraws. This resolves the
  objection that killed the naive intent-queue idea: we never promise a fixed future, we render
  the true conditional one. Confidence visibly decays with horizon (trails fuzz out), and the
  horizon length is a tree stat.

### Where the decisions live

Positioning against known impact zones; kill-order choices against spotters/officers; pre-run
planning once you can read the script ("wave 4 flanks left — I hold the right choke and let the
blocks eat the frontal push"); spending limited "read" time at the right moments. The action-game
skill layer survives intact underneath.

### Precedents

Slay the Spire (intent as the knowledge currency), Into the Breach (perfect information turns
combat into planning), Hollow Knight (telegraph literacy as progression), **Katana Zero** (the
closest cousin: its entire fiction is that your planning-and-retry *is* precognition — the retries
are diegetic). Our twist over all of them: the foresight is **computed, not authored** — a true
forward simulation only a deterministic sim architecture can afford, so it stays honest even
though enemies react to the player.

### Build cost & architecture

**Lowest of the three.** No new entity kinds, no control changes. Needs: Section 1 foundation;
a `SimState` clone (serialize/deserialize already exists for the determinism test); a forecast
`SimCore` stepped ~90–120 ticks ahead, amortized (e.g. re-forecast every 10 ticks) — the ghost
system already proved parallel SimCores are cheap. Knowledge flags live in `RunMeta` (meta layer,
like intel), overlays live in `view/`. The sim itself barely changes beyond Section 1. One
covenant note: the forecast sim must use a *cloned* RNG state, never the live one.

### Risks / open questions

- It is still fundamentally the same genre; if the Section 1 enemy redesign is weak, foresight
  overlays decorate a game that still doesn't need them.
- Overlay noise: three layers of prediction can bury the actual game. Needs strict visual budget.
- Doesn't by itself deliver the multi-body ladder — it's an Act 1 answer, not an Act 2 one.

---

## 3. Path B — **Echo Platoon** (your past lives fight beside you)

*Death stops resetting you to solo. Every previous life replays its recorded commands into the
shared, live sim as a half-real echo — you are a one-person army assembled from your own failed
attempts. The game is named for this.*

### The fantasy

Life 4 of the sortie. Down the beach, life 1 is already sprinting her doomed sprint toward the
left choke — but this time she isn't doomed, because life 2 is standing where you left him,
shooting the drone that killed her. Life 3 dies in eleven seconds to the mortar you now know
about; you can't save him, but his corpse buys you the timing. You spawn and take the one lane
none of your past selves covered. Four of you, and every one is you.

### Lore fit

Pre-L3 the echoes are the loop fraying: half-real comrades flickering at the edge of vision, "the
other loopers," soldiers the curse shows you — human-explainable, if barely, which is exactly the
unease Act 1 wants. The L3 rug-pull is *built into the verb*: the moment the player gains manual
record-rewind (deliberately acting twice at once, not just inheriting past attempts), the human
self-story becomes untenable — no human exists twice. VISION.md already designates record-rewind
as the L3 delivery mechanism; this path promotes it from Act 2 unlock to the game's spine, which
is also why the title *Echoes of Tomorrow* is this path's argument in two words.

### Core mechanics

- **The sortie.** A run becomes a sortie of up to K lives (K starts at 2–3, grows on the
  Embodiment branch) against the *same seed* — same assault script every life. Die → the world
  rewinds to tick 0, your command log banks as an echo, and you deploy again alongside all
  previous echoes. The sortie ends when lives run out or you extract.
- **Echoes are command sources, not movies.** Each echo is a player-body in the live sim
  consuming its recorded command log tick by tick — exactly the ghost architecture (DECISIONS
  2026-07-05), but *inside* the shared sim: their bullets kill real enemies, they absorb real
  aggro, they take real damage.
- **Desync is the drama.** The world diverges from what an echo experienced (you killed "its"
  enemy early; a drone it never met bodychecks it). Echoes have real HP; an echo that dies
  collapses into static and its remaining contribution is gone. This converts the user-visible
  flaw of replay-based allies ("the recording stops making sense") into the central tension:
  *fight in a way that keeps your past selves' futures true.* Clearing the lane ahead of your
  own doomed charge from two lives ago is the signature play.
- **Roles per life.** Before each deployment, a small choice (carried gear / directive) so lives
  are deliberately differentiated: this life is the breach, this life holds the left. Decision
  point at every death, planning horizon across the whole sortie.
- **The ladder falls out for free.** Ghost phase = mid-sortie *possession*: swap which body is
  live (your old body continues on its recorded log — record-rewind, delivered). Commander
  phase = simple standing orders that override an echo's log ("hold," "follow"). The Act 2/3
  architecture is this path's natural growth, not a new system.

### Where the decisions live

Every death is a planning beat (what does the *next* life need to be?). Every moment of play is
positional reasoning against known coverage (my echoes hold these two lanes; the script flanks
right at wave 3; therefore—). Protecting load-bearing echoes vs. spending them as bait. When to
extract a successful sortie vs. push one more life. This is the densest decision structure of the
three paths, and all of it is *about* the loop.

### Precedents

**Super Time Force** (the anchor: die, rewind, fight alongside your past attempts — proven fun),
The Talos Principle / Braid (recorded selves as tools), Quantum League & Lemnis Gate (time-clone
combat, adversarial), Cursor\*10 (the primordial version). Our twist over Super Time Force: STF's
past selves are invulnerable score-attack decoration on a linear level; ours are mortal simulated
agents in a shared deterministic roguelite world, with desync-death, role loadouts, and a
meta-tree governing echo capacity — and the mechanic carries the story's central reveal instead
of being flavor.

### Build cost & architecture

**Medium-high, but it is the vision's own roadmap.** The sim needs multi-agent player bodies: an
array of soldier entities each fed one `Command` per tick from a source (live input, or a recorded
log) — `Command` likely gains a body index or the sim gains a per-body command list. Enemy
targeting needs a real decision (nearest body? threat score?) — sim-side, deterministic, designed
once. Wave/aggro balance must account for N bodies. The ghost system already proves the replay
half; the new work is "player-shaped entities are plural" — which Commander/Director *require
eventually anyway*, so this cost is prepaid endgame architecture, not path-specific spend.
Covenant-clean: echoes never read save files; a sortie is reproducible as
`(seed, loadout, [command_log_1..n])`.

### Risks / open questions

- Desync rules need real design care: too fragile and echoes feel like wasted effort, too robust
  and they're fire-and-forget turrets. (Likely dial: echoes take reduced damage, and desync only
  threatens them when the divergence is player-caused.)
- Early-life trivialization: if lives 1–2 can clear waves 1–3 alone, life 4 starts bored. The
  assault script must scale pressure with echo count, or fragments/extraction must reward deeper
  waves so echoes are spent pushing frontier, not farming the start.
- Sorties lengthen the run (K lives × 8–12 min is too long); per-life length must shrink, or the
  rewind should offer "skip to your best surviving tick" fast-forward — which is, again, just a
  sim re-run at speed. Parked question "battle fast-forward" becomes load-bearing here.

---

## 4. Path C — **The Stolen Second** (tactical stall + command layer)

*Keep the real-time sim but make decision-making the explicit game: freeze the world the way the
Between froze it, study the field, queue orders — for yourself, and soon for allies. The strategy
pivot, without abandoning the one-control-paradigm covenant.*

### The fantasy

The wave hits the water line and the world *hangs* — spray frozen mid-air, the way everything hung
in that first impossible glitch. You have four stolen seconds. You drag a path around the mortar
zone, mark the spotter for your first three shots, set the dodge for the lancer's charge you know
is coming, and tap the two conscripts you pulled from the surf: *hold the choke.* Time slams back.
The plan executes. It goes wrong at second nine — so you stall again, and fix it.

### Lore fit

The Between debuts as ten frozen seconds where you're somehow still thinking (VISION.md). This
path takes the game's single most evocative image and makes it the combat verb from Act 1: the
stall in battle *is* the Between leaking into the war, which retroactively makes the Between's
debut a payoff instead of a curiosity. Pre-L3 naming: the trance, the held breath, "the world
waits for you" — shell-shock unreality, consistent with the graybox lore. Post-L3: you are
stealing scheduler cycles mid-battle, and the stall meter renames to exactly that. Director-phase
gameplay (choreographing both armies against the Expected Performance Band) is *literally this
mechanic at maximum stat* — Path C is the endgame played early and small.

### Core mechanics

- **Stall.** A meter of frozen seconds per life (starts ~4s, grows on Cognition). While stalled:
  sim is frozen (view-mode freeze, exactly the pause/hit-stop precedent — the sim never learns
  about it), free camera, full tactical readability.
- **Plans compile to commands.** While stalled you queue intents — waypoint path, priority
  target, timed dodge, ability trigger. On resume, a plan-runner in the view translates the queue
  into per-tick `Command`s (the covenant's input path, unchanged; a plan is just another command
  source, which is the same insight that powers ghosts). Manual control instantly overrides;
  stalling again edits the remainder.
- **Enemy intent, done right.** While stalled, enemy types that have killed you before display
  their *actual* forthcoming moves — a deterministic lookahead (Path A's forecast tech) rendered
  as Into-the-Breach-style order pips and path arrows. Recomputed at every stall, so it is
  truthful under reactivity: this is Slay the Spire intent relocated to the one place it can't
  lie, inside a pause where you can actually respond to it.
- **Allies and possession.** Conscripts rescued on the beach (human-readable in Act 1; other
  instances, later) accept orders only during stall and run simple doctrine otherwise. You
  inhabit one body directly; *swap* during stall (possession — the Ghost-phase verb, and the
  user's "control one, AI runs the rest, switch when you know more" ask, delivered exactly).
- **Full turn-based variant (assessed, not recommended).** WEGO 1-second simultaneous turns
  (Frozen Synapse) is buildable on this same sim — but it abandons the action feel, the Hades
  reference, the dodge verb, and most work done to date, for a genre with a smaller hook. The
  stall keeps the strategy brain *and* the arcade hands.

### Where the decisions live

Everything the user asked for lives here explicitly: discrete decision points (stalls), tactic
changes mid-execution, multi-unit choices, kill-order and positioning puzzles against visible
enemy intent, a scarce resource (stall seconds) governing how much thinking you can afford. The
knowledge loop gates *information inside the stall* — a veteran's pause shows a battle plan, a
rookie's pause shows frozen chaos.

### Precedents

Transistor (Turn(): plan bar inside an action game — the closest model), Frozen Synapse / Door
Kickers (plan-and-execute readability), FTL/RimWorld (pause as the strategy enabler), Into the
Breach (visible enemy intent as the whole game), BG3/RTwP lineage for ally orders. Our twist: the
pause is a *diegetic, scarce, upgradeable resource that is also the story's central mystery*, and
enemy intent shown during it is computed truth from the deterministic sim, not authored hints.

### Build cost & architecture

**Highest.** Needs: Section 1 foundation; the plan-runner (order queue → per-tick commands —
architecture-friendly, view-side); ally bodies in the sim (the same multi-agent work as Path B);
enemy lookahead (the same forecast work as Path A); and — the real cost — a tactical UI (order
gizmos, path dragging, target marking, intent display) that must work on gamepad and touch too.
UI is where this path's budget goes to die; scope it ruthlessly (e.g. orders are only
waypoint + focus-target + stance, nothing else, for the whole first milestone).

### Risks / open questions

- Pacing: stall-spam turns the game into a slideshow; too little stall and the tactical layer is
  vestigial. The meter economy is the whole game and will take real tuning.
- Two-audience risk: action players resent stopping, tactics players resent the action skill
  floor. Transistor threaded this needle; most RTwP games don't.
- Heaviest lift with the most UI risk, on a two-dev hobby cadence. If chosen, it should be
  chosen *because* we've accepted the game is a tactics game wearing an action shell.

---

## 5. Comparison and recommendation

| | A — Premonition | B — Echo Platoon | C — Stolen Second |
|---|---|---|---|
| Fixes "knowledge is irrelevant" | Directly (foresight) | Directly (coverage planning) | Directly (intent + planning) |
| New decision density | Moderate | High | Highest |
| Multi-body ladder progress | None | Large (echoes = bodies) | Large (allies = bodies) |
| Lore/reveal fit | Excellent | Excellent — it's the title & the L3 vehicle | Excellent — it's the Between & the Director endgame |
| Distance from current build | Small | Medium | Large |
| Biggest risk | Still the same genre underneath | Desync/balance design | UI scope & pacing |
| Unique tech it forces | Forecast sim | Multi-agent sim | Plan-runner + tactical UI + both of the others' tech |

Two observations before the recommendation:

1. **These paths are not mutually exclusive — they are roughly the three acts.** A is an Act 1
   (Soldier) answer, B is the Act 2 (Ghost) mechanic made central, C is Act 2/3
   (Commander/Director) played early. The vision already sequences them; the real question is
   which one to pull forward into the core loop *now*.
2. **They share components.** Section 1 (authored assault) feeds all three. The forecast sim
   (A) is reused by C's intent display. The multi-agent sim (B) is required by C's allies.
   Building A then B strictly reduces the cost of C later.

**Recommendation: Section 1 + Path B as the core-loop bet, with Path A's Layer 1–2 (schedule
sense + death sense) as cheap riders.** Reasoning: B is the only path where the *time loop
itself* is the mechanic rather than a UI over the mechanic; it is the game the title promises;
it delivers the user's multiple-characters/swap request with bodies that are narratively *free*
(they're you — no new characters to write); it forces the multi-agent sim work the endgame needs
anyway; and its anchor precedent (Super Time Force) proves the fun exists. A's knowledge layers
cost little on top and give the Edge-of-Tomorrow "I know what comes next" texture between echo
decisions. C stays on the roadmap as what the Commander/Director phases grow into, built on B's
agents and A's forecasts, rather than a bet we place today.

Suggested proving step (cheap, honest): prototype a **2-life sortie** — die once, rewind, fight
alongside one mortal echo against the Section 1 scripted wave 1–3, with desync-death on. If
protecting/exploiting a single past self at a single choke isn't already interesting, B is
falsified for a few weeks' work and A becomes the default.
