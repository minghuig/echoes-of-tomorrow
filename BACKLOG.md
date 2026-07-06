# BACKLOG

Roadmap items, feature requests, and bugs that don't belong in `DECISIONS.md`
(which is for architectural choices already made). Newest at the bottom of
each section. Move an entry to **Done** with the date and the commit/PR that
closed it; don't delete history.

## Bugs

*(none open)*

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

- **[DONE 2026-07-06] No way to reset the save file (start a new game) from
  in-game.** `RunMeta` persists to `user://save.json` and only ever grows —
  there was no erase/reset path. Added a two-step confirm on the Pause screen
  (`E`/`X` arms it, showing a 3-second confirm-or-cancel prompt; press again
  to confirm, or `Esc`/`Start` / a timeout cancels). Confirming writes a
  fresh all-zero `RunMeta` to disk and immediately starts a new run —
  `main.gd:_erase_save_and_restart()`.
