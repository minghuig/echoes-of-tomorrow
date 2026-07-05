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

**M5** — the beach assault (Act 1 begins): endless seeded enemy waves wade out of the sea — drones swarm (Vampire Survivors pressure), infantry advance to range and shoot, heavies soak and crush. The dodge now has i-frames (Hades dash). Blocks are cover that both sides chew through. There is no clear condition anymore: the beach is unwinnable by design — waves escalate forever, you die, and the death banks fragments (deaths convert to knowledge, per VISION). The death panel logs your performance; R redeploys. All enemy stats and the assault schedule are data (`content/enemies.json`, `content/waves.json`). Next up: **M6**, the Between + sentience tree.
