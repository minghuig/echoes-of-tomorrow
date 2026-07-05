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

**M4** — feel pass: hit-stop on block hits and kills, screen shake, damage flashes, destruction pops, and procedurally synthesized SFX (`view/sfx.gd` — no audio assets). All of it is view-layer time and flavor: a hit-stop frame skips the whole view tick (no command recorded, no sim step), so command logs stay 1:1 with sim ticks and ghost replays are untouched. The prototype roadmap (M0–M4) is complete; the M3 architecture gate — a recorded run visibly replaying as a ghost — is passed and enforced by `tests/test_ghost_replay.gd`.
