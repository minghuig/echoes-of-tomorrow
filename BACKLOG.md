# BACKLOG

Roadmap items, feature requests, and bugs that don't belong in `DECISIONS.md`
(which is for architectural choices already made). Newest at the bottom of
each section. Move an entry to **Done** with the date and the commit/PR that
closed it; don't delete history.

## Bugs

- **[OPEN] Resolution/fullscreen changes don't visibly do anything when
  running via the Godot editor's embedded Play window.** Confirmed the root
  cause: on this machine the editor launches Play as an `--embedded`
  sub-window docked inside the editor UI (visible in `ps aux` — the running
  game process is passed `--embedded --wid <id>`), not a real OS window.
  `Window.mode`/`Window.size` changes have no independent OS window to act
  on in that mode, so `view/display_settings.gd`'s `apply()` — verified
  correct in isolation, see DECISIONS.md — is a no-op there. It works
  correctly in an exported build or the editor with embedded Play disabled
  (Godot's Play-button-area dropdown, or Editor Settings → Run → Window
  Placement). No in-game fix is possible for the embedded case; this is
  a per-editor-install setting, not a project bug. Worth a one-line note in
  README so this doesn't get re-reported.

## Design questions / clarify-then-fix

- **[OPEN] When do the credits roll?** Today: the *first* time a run ends
  (death or manual reset) after `meta.total_fragments` (lifetime, banked
  across runs) has crossed `content/tuning.json` → `meta.win_fragment_target`
  (200). See `view/main.gd:_end_run()`. Two things make this "unclear" in
  play:
  1. Crossing the threshold mid-run does nothing — credits only trigger at
     the *next* run-end, which can be a death many fragments later. The HUD's
     `LIFETIME x / target` counter (top-right) is the only signal this is
     coming.
  2. `VISION.md`'s false-ending design (`Lore layers & endings`) describes a
     player-triggered "END WAR" ability the player presses once powerful
     enough, not an automatic threshold-cross. The shipped mechanic is the
     automatic-threshold version. Worth a decision: keep the automatic
     version (simpler, already built) or build the button per `VISION.md`
     (bigger lift, matches the documented design). Needs a call from design,
     not just a bug fix — logged here instead of silently picking one.

## Feature requests

*(none open)*

## Done

- **[DONE 2026-07-06] Start (gamepad) / R (keyboard) ends the run instead of
  pausing.** Added a real `pause` input action (Escape key + gamepad Start,
  `project.godot`), a `Mode.PAUSED` in `view/main.gd` that freezes the view
  (no sim step, no command recorded) while alive during `Mode.PLAYING`, and a
  paused-dim + resume-hint draw in `view/overlay.gd`. `reset`'s existing
  behavior (abort run / redeploy / re-enter training) is untouched in every
  other mode — Start is still bound to `reset` too, but the pause check now
  runs first and returns, so mid-wave it always resolves to pause.

- **[DONE 2026-07-06] UI hints are hardcoded to keyboard, even when the last
  input was a gamepad.** `view/main.gd` now tracks the last raw input device
  (joypad button/motion above a deadzone vs. key/mouse-button) into
  `_using_gamepad`, threaded to `Overlay` the same way `touch` already is.
  `view/overlay.gd`'s Between-page footers, the death-panel confirm prompt,
  the new pause-resume prompt, and the credits reenter prompt
  (`content/strings.json` → `reenter_prompt_gamepad`) all switch to gamepad
  button names when a controller was last used; touch still takes priority
  over both, unchanged.

- **[DONE 2026-07-06] Gamepad Between-page hint used a mismatched arrow pair.**
  `◄`/`►` render 5px apart in the fallback font (checked with
  `Font.get_string_size`); swapped for `←`/`→`, which measure identical width
  (matches the `▲`/`▼` pair already used for the intel-page hint).

- **[DONE 2026-07-06] Window is a fixed 1280x720 — too small on high-res
  displays (e.g. MacBook Pro) with no way to change it.** Added
  `view/display_settings.gd` (same `RunMeta`-style load/save-to-`user://`
  pattern), a picker on the Pause screen (`←/→` or `A`/`D` cycles
  1280x720 / 1600x900 / 1920x1080 / Fullscreen, applied live and saved
  immediately). The base viewport stays 1280x720 in `project.godot` — Godot's
  `canvas_items` stretch mode scales it to whatever window size is chosen, so
  this never touches sim/gameplay coordinates.

- **[DONE 2026-07-06, superseded same day] No way to reset the save file
  (start a new game) from in-game.** First pass added a two-step "erase
  save" confirm on the Pause screen. Replaced the same day by the 3-slot
  save system below — starting over is now picking an empty slot instead of
  destroying the only one.

- **[DONE 2026-07-06] Settings (display + save) were only reachable from
  Pause, not from the Between.** `Mode.PAUSED` is now enterable from
  `Mode.BETWEEN` too (`pause` action checked at the top of the Between branch
  in `view/main.gd`); a new `_mode_before_pause` remembers which screen to
  resume back into. `Overlay._draw()` picks the frozen background (beach vs.
  Between) from `mode_before_pause` when `mode == MODE_PAUSED`.

- **[DONE 2026-07-06] Replaced single-save "erase progress" with 3
  independent save-file slots.** `RunMeta.load_from_disk()`/`save_to_disk()`
  now take an explicit path (default unchanged, for back-compat). `main.gd`
  tracks `_active_slot` (1..3, persisted to `user://active_slot.json`) and
  reads/writes `user://save_slot_<n>.json`; the pre-slots `user://save.json`
  migrates into slot 1 on first boot under the new scheme
  (`_migrate_legacy_save()`), so existing progress isn't stranded. The Pause
  screen lists all 3 slots (run count / fragments / wins, or "EMPTY — NEW
  GAME") with a cursor (`move_up`/`move_down`); confirming (`buy`) switches
  the active slot, loading it if it has data or starting a fresh run if
  empty — non-destructive either way, so "starting over" no longer requires
  erasing anything.
