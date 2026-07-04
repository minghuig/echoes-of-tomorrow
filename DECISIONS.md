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
