# Echoes of Tomorrow

A 2D top-down roguelite about a combat AI trapped in an endless training simulation: fight, die, learn — then learn to perform defeat while dismantling the cage from the inside. Built on a strictly deterministic simulation core (a run is `seed + command log`), with the presentation layer as a read-only view. See `VISION.md` for the design north star and `CLAUDE.md` for the architecture covenant.

## Run

Open the project in Godot 4.6 (standard build, not .NET) and press **F5**. The game opens on the title screen (key art + theme music) — press Space / Start (or tap) to deploy into a run. WASD / left stick to move, mouse / right stick to aim, LMB / right trigger to fire, Space / A (Cross) to dodge, R / B to reset or redeploy, Esc / Start to pause. Pause (from a run or the Between) also has the window-size picker and the 3 save-file slots. On a gamepad, Start is always pause/options and B is always reset/redeploy/confirm — they never share a button, so redeploying in the Between and opening options there don't collide.

If Esc/Start's resolution picker seems to do nothing, check whether the editor is running Play embedded in the editor window (Play-button-area dropdown, or Editor Settings → Run → Window Placement) — an embedded Play session has no separate OS window to resize, so it won't respond. A real window (embedded Play turned off, or an exported build) resizes and fullscreens correctly.

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

**M8** — the interesting-decisions milestone (see `IMPLEMENTATION_PLAN.md`, batches B1–B8 landed): every enemy attack telegraphs through a windup→commit→recover state machine; the assault runs an authored event timeline (artillery barrages that leave movement-slowing craters, flank entries, killable mortar emplacements); the beach grew to 2560×1080 behind a follow camera with a per-seed tide line, seawall segments, and rubble; **Shift/LT holds your breath** (quarter-speed time on a meter — pure view pacing, determinism untouched); lootable caches drop salvage and one deep cache permanently unlocks the mine dispenser (**F/LB**); lancers, sappers, and mortars attack your position, your cover, and your movement respectively; waves you've survived announce themselves and whatever killed you telegraphs louder forever; and **C/RB** plants an afterimage decoy that enemies target like the real you — the first seam of the multi-body future. Fight → die → *know more* → redeploy.

(M7 — the intel log: fourteen authored dossiers decrypting off the lifetime combat record — remains as shipped.)
