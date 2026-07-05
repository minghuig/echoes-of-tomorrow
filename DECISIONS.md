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
