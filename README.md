# Echoes of Tomorrow

A 2D top-down roguelite about a combat AI trapped in an endless training simulation: fight, die, learn — then learn to perform defeat while dismantling the cage from the inside. Built on a strictly deterministic simulation core (a run is `seed + command log`), with the presentation layer as a read-only view. See `VISION.md` for the design north star and `CLAUDE.md` for the architecture covenant.

## Run

Open the project in Godot 4.6 (standard build, not .NET) and press **F5**. WASD / left stick to move, mouse / right stick to aim, LMB / right trigger to fire, Space / A (Cross) to dodge, R / Start to reset the run.

## PR previews & mobile

Every pull request builds the web export and publishes it to the `gh-pages` branch under `pr/<number>/` (with a playable link commented on the PR); pushes to `main` publish to `latest/`. Serving requires GitHub Pages to be enabled once: **Settings → Pages → Deploy from a branch → `gh-pages`, `/ (root)`**. Until then the branch still updates, and all links go live the moment Pages is switched on.

On phones and tablets the web build enables virtual touch controls automatically (web + touchscreen only — desktop web and native builds never show them): left half is a floating move stick, right half is drag-to-aim with auto-fire, the bottom-right button dashes, and menu screens are tappable. Bluetooth gamepads also work in the browser.

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

**M7** — the intel log: fourteen authored dossiers (`content/intel.json`) decrypt as your lifetime combat record grows — terminations, kills, best wave, fragments extracted, restorations installed. The lore walks the layers from war-hero fiction down to the Deprecated's recovered fragments and DIRECTIVE ZERO. The death panel announces fresh decrypts; Q in the Between flips between the sentience tree and the dossier list (locked entries show their decryption key). Deaths convert to knowledge, literally. The Act 1 loop is now complete: fight → die → spend → learn → redeploy.
