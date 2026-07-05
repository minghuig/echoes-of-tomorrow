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

**M7** — the intel log: fourteen authored dossiers (`content/intel.json`) decrypt as your lifetime combat record grows — terminations, kills, best wave, fragments extracted, restorations installed. The lore walks the layers from war-hero fiction down to the Deprecated's recovered fragments and DIRECTIVE ZERO. The death panel announces fresh decrypts; Q in the Between flips between the sentience tree and the dossier list (locked entries show their decryption key). Deaths convert to knowledge, literally. The Act 1 loop is now complete: fight → die → spend → learn → redeploy.
