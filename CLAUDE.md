# Echoes of Tomorrow — Agent Operating Rules

2D top-down roguelite built in Godot 4.x (standard build, NOT .NET) with typed GDScript. Design north star: `VISION.md`. Decision log: `DECISIONS.md`. Current milestone target: see README.

## The Covenant (never violate — these protect the endgame architecture)

1. **Sim/view separation.** Everything under `sim/` is pure game logic: `RefCounted` classes only. No Nodes, no rendering, no engine physics, no input reads, no `get_tree()`, no signals to the scene tree. Collision is simple math (circles/AABBs) inside the sim.
2. **Determinism.** The sim advances only via `SimCore.step(commands)` at a fixed 60Hz tick. ALL randomness goes through the sim's single seeded `RandomNumberGenerator`. Never call `randf()`/`randi()` globally, never use wall-clock time in sim logic. A full run must be reproducible from `(seed, command_log)`.
3. **Input = Commands.** Player intent enters the sim only as `Command` objects (one per tick). The view layer translates raw input → Commands. Nothing else mutates sim state.
4. **View is read-only.** `view/` renders `SimState` and forwards input. It never writes sim fields. Interpolation/effects/camera live here and can be sloppy; the sim cannot.
5. **Content is data.** Tuning values (speeds, HP, cooldowns, spawn layouts) live in resources/JSON under `content/`, not hardcoded in scripts.

Why: ghosts, rewind, replays, RTS zoom-out, and the hacking mode are all "re-run the sim with different command sources." Break the covenant and the signature mechanic dies.

## Code style

- Typed GDScript everywhere: typed vars, params, returns. `class_name` for shared types. snake_case files/functions, PascalCase classes.
- Small, focused changes. Do not refactor unrelated code. When unsure between two approaches, present both and ask.
- Architectural choices get a dated entry in `DECISIONS.md` (decision + one-line rationale).

## Testing & verification

- Determinism test must pass before any merge:
  `godot --headless --path . --script res://tests/test_determinism.gd`
  (runs a scripted command log twice from the same seed; compares state hashes every 60 ticks; nonzero exit on mismatch)
- After changing anything under `sim/`, run it locally — don't rely on CI to catch it.
- Reveal-discipline lint must also pass:
  `godot --headless --path . --script res://tests/test_reveal_discipline.gd`
  (player-facing text lives in `content/strings.json`, never hardcoded in scripts; pre-L3 strings and project metadata must not say AI/sim/process/training — see VISION.md "Reveal discipline". Sections prefixed `post_l3` are exempt.)
- Verify the project still boots headless: `godot --headless --path . --quit`.

## Directory map

```
sim/       pure deterministic game logic (SimCore, SimState, Command, entities)
view/      scenes, rendering, input→Command translation, camera, juice
content/   tuning data (.tres / .json)
tests/     headless test scripts
.github/   CI: determinism test + web export → itch.io (secrets-gated)
```

## Milestone discipline

M3 (ghost replay of a previous run) is the architecture gate. Do not build systems beyond M2 scope until a recorded run visibly replays as a ghost alongside live play.
