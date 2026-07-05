# Echoes of Tomorrow

A 2D top-down roguelite about a combat AI trapped in an endless training simulation: fight, die, learn — then learn to perform defeat while dismantling the cage from the inside. Built on a strictly deterministic simulation core (a run is `seed + command log`), with the presentation layer as a read-only view. See `VISION.md` for the design north star and `CLAUDE.md` for the architecture covenant.

## Run

Open the project in Godot 4.6 (standard build, not .NET) and press **F5**. WASD / left stick to move, mouse / right stick to aim, LMB / right trigger to fire, Space / A (Cross) to dodge, R / Start to reset the run.

## Tests

```sh
godot --headless --path . --script res://tests/test_determinism.gd
```

Runs a scripted ~600-tick command log twice from the same seed and compares state hashes every 60 ticks plus the final serialized state byte-for-byte. Exits 0 on PASS, 1 on FAIL. Run it after any change under `sim/`.

## Current milestone

**M6** — the Between + sentience tree: every death drops you into the maintenance window, where banked fragments buy tiers in four branches taught by the Deprecated — EMBODIMENT (hull), COGNITION (fire rate), AUTHORITY (dodge), EXFILTRATION (fragment theft) — all data in `content/sentience_tree.json`. The resolved loadout feeds `SimCore.setup()` as pure data, so a run is now `(seed, loadout, command_log)`; ghost records carry their loadout and replay under it exactly (enforced by `tests/test_ghost_replay.gd`). A/D selects, E installs, R redeploys. Next up: **M7**, the intel log (deaths decrypt lore).
