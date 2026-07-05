# DECISIONS

Architectural choices, dated, with one-line rationale. Newest at the bottom.

- **2026-07-04 — Godot 4.x standard build.** Standard (non-.NET) build keeps web export working and avoids a C# build step.
- **2026-07-04 — Typed GDScript over C#.** C# blocks web export and adds build-step friction for agents; typed GDScript keeps iteration instant.
- **2026-07-04 — 2D top-down.** One control paradigm across all modes per the scope covenants; no camera/perspective complexity.
- **2026-07-04 — 60Hz fixed tick.** Sim advances only in exact 1/60s steps; frame rate never touches game logic.
- **2026-07-04 — Deterministic sim core with command-based input.** A run is `(seed, command_log)`; ghosts, rewind, and replays are re-runs of the sim with different command sources.
- **2026-07-04 — Codename ASSET-7.** Working title per VISION.md.
- **2026-07-04 — Engine version pinned to 4.6.3-stable.** Local binary and CI image (`barichello/godot-ci:4.6.3`) must match so exports and tests behave identically.
- **2026-07-04 — Cross-file sim references use `preload()` consts, not bare `class_name` lookups.** Global class resolution needs the editor's `.godot/` cache; preloads keep headless/CI runs working from a cold checkout.
- **2026-07-05 — Renamed to Echoes of Tomorrow.** ASSET-7 retired as the project title; "ASSET 7" survives only as the player AI's in-fiction designation (the credits stinger in VISION.md).
- **2026-07-05 — Per-run data fragments live in SimState.** The sim is authoritative for what a run earns (1 per destroyed block), and the field is in `serialize()` so earnings sit inside the determinism contract.
- **2026-07-05 — Meta/persistence state lives in the view layer (`view/run_meta.gd` → `user://save.json`), never in the sim.** Lifetime fragments and run count are meta-game knowledge across runs; keeping them (and all disk I/O) outside `sim/` preserves "a run = (seed, command log)" and keeps replays/ghosts from depending on save files. Nothing persisted feeds back into sim behavior yet.
- **2026-07-05 — Seed selection is meta-layer policy: `BASE_SEED + lifetime run index`.** The view picks each run's seed before constructing the sim; the sim never chooses or mutates its own seed, so any run replays from its recorded `(seed, command_log)`.
- **2026-07-05 — M2 win condition is a meta-layer fragment threshold, not sim state.** Lifetime fragments ≥ `meta.win_fragment_target` (tuning data) rolls credits in the view; the sim keeps only the per-run clear, so determinism and the M3 replay substrate are untouched.
- **2026-07-05 — Ghosts are parallel SimCores re-running a recorded `(seed, command_log)`.** The view steps the ghost one recorded command per live tick and renders it translucent; ghost state is never merged into or read by the live sim. First working proof of "everything is a re-run with a different command source".
- **2026-07-05 — Juice dilates view time, never sim time.** Hit-stop skips the entire view tick (no command recorded, no sim step, ghost included), so command logs stay 1:1 with sim ticks; shake jitter uses a view-local RNG, never the sim's.
- **2026-07-05 — SFX are synthesized PCM at startup (`view/sfx.gd`), not asset files.** Square-wave blips keep the repo asset-free and the web export tiny; audio is pure view flavor the sim never sees.
- **2026-07-05 — The beach has no clear condition; waves escalate forever.** Act 1's "unwinnable beach" is mechanical truth: authored waves then linear escalation, all data in `content/waves.json`. Runs end in death (or manual reset), and death banks fragments — losing is the progression loop (Vampire Survivors pressure curve, Hades death-as-return).
- **2026-07-05 — Wave spawn positions are the sim RNG's first consumer.** Spawn x-jitter draws from the seeded RNG at wave-schedule time only, so runs stay reproducible from `(seed, command_log)` and ghost replays get identical assaults.
- **2026-07-05 — Dodge grants i-frames (`dodge_iframe_ticks` tuning).** The dash is the survival verb against an unwinnable screen (Hades); invulnerability lives in sim state so replays honor it exactly.
- **2026-07-05 — A run is `(seed, loadout, command_log)`.** The sentience tree resolves to a flat stat-modifier dict the view passes into `SimCore.setup()`; the sim never reads save files. RunRecords carry their loadout so ghosts replay under the exact stats they were played with.
- **2026-07-05 — Sentience-tree tiers are absolute, not stacking (Hades Mirror of Night model).** Each owned tier fully defines its branch's effect in `content/sentience_tree.json`; resolution is "take the owned tier's effects", which keeps balance authorable in data and loadout resolution trivial.
- **2026-07-05 — Intel is knowledge-gated authored lore (Outer Wilds ship-log model), unlocked by the lifetime combat record.** Conditions (deaths / kills / wave / fragments / upgrades) live with the entries in `content/intel.json`; `RunMeta.evaluate_intel()` is the single evaluator. Pure view/meta + content — the sim knows nothing about lore.
- **2026-07-05 — Run results bank once, at the moment of death (or manual reset), not at redeploy.** `_bank_run_results()` is idempotent per run; banking early lets the death panel announce fresh decrypts while the corpse is still on screen.
