# Echoes of Tomorrow

A 2D top-down roguelite about a combat AI trapped in an endless training simulation: fight, die, learn — then learn to perform defeat while dismantling the cage from the inside. Built on a strictly deterministic simulation core (a run is `seed + command log`), with the presentation layer as a read-only view. See `VISION.md` for the design north star and `CLAUDE.md` for the architecture covenant.

## Run

Open the project in Godot 4.6 (standard build, not .NET) and press **F5**. WASD / left stick to move, mouse / right stick to aim, LMB / right trigger to fire, Space / A (Cross) to dodge.

## Tests

```sh
godot --headless --path . --script res://tests/test_determinism.gd
```

Runs a scripted ~600-tick command log twice from the same seed and compares state hashes every 60 ticks plus the final serialized state byte-for-byte. Exits 0 on PASS, 1 on FAIL. Run it after any change under `sim/`.

```sh
godot --headless --path . --script res://tests/test_reveal_discipline.gd
```

Lints all player-facing text (`content/strings.json` plus project metadata) against the reveal-discipline vocabulary rules in `VISION.md` — pre-reveal strings must never say AI, sim, process, or training. Run it after changing any display string.

## Current milestone

**M0** — capsule moves, aims at the mouse, fires, dodges; blocks break; destroying all blocks shows "CLEAR".
