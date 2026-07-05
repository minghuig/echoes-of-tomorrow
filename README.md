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

**M3** — ghost replay (the architecture gate): every run records its `(seed, command log)`; the next run re-runs that record through a second SimCore stepped in lockstep with live play, rendered as a translucent cyan echo that derezzes when its log runs out. `tests/test_ghost_replay.gd` proves the replay is tick-for-tick identical (checkpoint hashes + final state bytes) while an unrelated live sim advances beside it. Next up: **M4**, the feel pass (hit-stop, shake).
