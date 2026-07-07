extends Node2D
## Screen-space overlay on its own CanvasLayer (immune to world shake):
## vignette, scanlines, a rolling holo-refresh band, the diegetic training-sim
## HUD, the hurt flash, wave banner, death panel, touch chrome, and the two
## non-combat modes (the Between and the credits roll). Read-only over sim and
## meta state — everything it needs is handed in by main.gd.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const RunMetaScript := preload("res://view/run_meta.gd")
const TouchInputScript := preload("res://view/touch_input.gd")

# Mode ids mirror main.gd's Mode enum (pushed in as an int).
const MODE_PLAYING: int = 0
const MODE_BETWEEN: int = 1
const MODE_CREDITS: int = 2
const MODE_PAUSED: int = 3

const HURT_FRAMES: int = 18

const COLOR_HUD := Color("3fd0d4")
const COLOR_FRAG := Color("ffd75e")
const COLOR_HP := Color("6ee08a")
const COLOR_HP_LOW := Color("ff6f61")
const COLOR_HP_BACK := Color(0.05, 0.07, 0.11, 0.7)
const COLOR_CLEAR := Color("aef2f4")
const COLOR_HUD_TEXT := Color("8fa3ad")
const COLOR_AIM := Color("3fd0d4")
const COLOR_SEA := Color("16283c")
const COLOR_DOWN_TEXT := Color("ff6f61")
const COLOR_HURT := Color(0.85, 0.15, 0.12, 1.0)
const COLOR_BG := Color("0b0d13")
const COLOR_PROJECTILE := Color("ffd75e")

## Tap targets for the Between on touch devices (must match main.gd).
const BETWEEN_BTN_TOGGLE := Rect2(320.0, 636.0, 280.0, 56.0)
const BETWEEN_BTN_DEPLOY := Rect2(680.0, 636.0, 280.0, 56.0)

const CREDITS_SCROLL_PER_TICK: float = 1.1
const CREDITS_LINE_SPACING: float = 44.0
const CREDITS_TITLE_FONT_SIZE: int = 64
const CREDITS_FONT_SIZE: int = 24
# Credits text is the post-reveal false-ending stinger, so it lives in
# content/strings.json under a `post_l3` section (exempt from the
# reveal-discipline lint) rather than hardcoded here — player-facing display
# text belongs in data, and the lint forbids the ending's vocabulary in view
# scripts (see tests/test_reveal_discipline.gd, VISION.md "Reveal discipline").
const STRINGS_PATH := "res://content/strings.json"

# References handed in by main (set once, core re-pointed each run).
var core: SimCoreScript
var meta: RunMetaScript
var tree: Array = []
var intel: Array = []
var touch: TouchInputScript

# View state pushed by main each tick.
var mode: int = MODE_PLAYING
var win_fragment_target: int = 0
var between_selection: int = 0
var between_page: int = 0
var intel_selection: int = 0
var fresh_intel: Array = []
var banner_wave: int = 0
var wave_banner_frames: int = 0
var hurt_frames: int = 0
var credits_ticks: int = 0
var ghost_active: bool = false
## Held-breath meter (0..1) and whether the slow is currently held.
var focus_fraction: float = 1.0
var focus_active: bool = false
## Which button hints to draw: pushed in by main.gd from the last raw input
## device seen (joypad vs. key/mouse). Touch takes priority over both (see
## `touch`) since it has its own dedicated chrome.
var using_gamepad: bool = false
## Pause-screen state, pushed in by main.gd. mode_before_pause decides
## whether the frame beneath the pause dim is the beach or the Between.
var display_label: String = ""
var mode_before_pause: int = MODE_PLAYING
var slot_summaries: Array[String] = []
var active_slot: int = 1
## Focused Pause row: 0 = display setting, 1..N = save slots (mirrors
## main.gd's _pause_cursor).
var pause_cursor: int = 0

# Post-reveal ending text, loaded from content/strings.json (see STRINGS_PATH).
var _credits_lines: Array = []
var _reenter_prompt: String = ""
var _reenter_prompt_gamepad: String = ""

var _time: float = 0.0
var _vignette_tex: GradientTexture2D
var _band_tex: GradientTexture2D
var _scan_tex: ImageTexture


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	var ending: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(STRINGS_PATH))["post_l3_ending"]
	_credits_lines = ending["credits"]
	_reenter_prompt = ending["reenter_prompt"]
	_reenter_prompt_gamepad = ending["reenter_prompt_gamepad"]

	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray(
		[Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.42)])
	_vignette_tex = GradientTexture2D.new()
	_vignette_tex.gradient = vg
	_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	_vignette_tex.fill_from = Vector2(0.5, 0.5)
	_vignette_tex.fill_to = Vector2(0.5, -0.15)
	_vignette_tex.width = 512
	_vignette_tex.height = 512

	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	bg.colors = PackedColorArray(
		[Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.045), Color(1.0, 1.0, 1.0, 0.0)])
	_band_tex = GradientTexture2D.new()
	_band_tex.gradient = bg
	_band_tex.fill_from = Vector2(0.0, 0.0)
	_band_tex.fill_to = Vector2(0.0, 1.0)
	_band_tex.width = 8
	_band_tex.height = 64

	var img := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(0, 1, Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(0, 2, Color(0.0, 0.0, 0.0, 0.10))
	_scan_tex = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if core == null:
		return
	# The overlay is screen-space chrome on its own CanvasLayer; the arena is
	# larger than the screen now that the camera scrolls, so everything here
	# lays out against the viewport, never the arena.
	var screen: Vector2 = get_viewport_rect().size

	if mode == MODE_CREDITS:
		_draw_credits(screen)
		_draw_crt(screen)
		return

	# Paused freezes whichever screen it was entered from beneath its dim —
	# the beach mid-wave, or the Between (see main.gd's _mode_before_pause).
	var effective_mode := mode_before_pause if mode == MODE_PAUSED else mode

	if effective_mode == MODE_BETWEEN:
		_draw_between(screen)
		_draw_crt(screen)
		if mode == MODE_PAUSED:
			_draw_paused(screen)
		return

	# PLAYING (and PAUSED-from-PLAYING, which renders the same frozen frame
	# plus a dim + pause chrome on top).
	# The held breath tints the whole frame cold while active.
	if focus_active and mode == MODE_PLAYING:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0.25, 0.82, 0.85, 0.045), true)

	if hurt_frames > 0:
		var hurt := COLOR_HURT
		hurt.a = 0.28 * float(hurt_frames) / float(HURT_FRAMES)
		draw_rect(Rect2(Vector2.ZERO, screen), hurt, true)

	_draw_refresh_band(screen)
	_draw_crt(screen)
	_draw_hud(screen)

	if touch != null and touch.enabled and not core.state.player_down and mode == MODE_PLAYING:
		_draw_touch_overlay(core.state)
	if wave_banner_frames > 0 and mode == MODE_PLAYING:
		_draw_wave_banner(screen)
	if core.state.player_down:
		_draw_death_panel(core.state)
	if mode == MODE_PAUSED:
		_draw_paused(screen)


func _draw_crt(screen: Vector2) -> void:
	var full := Rect2(Vector2.ZERO, screen)
	draw_texture_rect(_vignette_tex, full, false)
	draw_texture_rect(_scan_tex, full, true)


func _draw_refresh_band(screen: Vector2) -> void:
	var band_y := wrapf(_time * 46.0, -100.0, screen.y + 100.0)
	draw_texture_rect(_band_tex, Rect2(0.0, band_y, screen.x, 90.0), false)


func _draw_hud(screen: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var col := Color(COLOR_HUD, 0.6)
	var dim := Color(COLOR_HUD, 0.35)
	var state := core.state

	# Diegetic header, top-left.
	draw_string(
		font, Vector2(24.0, 30.0), "ASSET-7 // COMBAT DEPLOYMENT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_string(
		font, Vector2(24.0, 48.0),
		"ITERATION %s   T+%s" % [str(meta.run_count).pad_zeros(3), str(state.tick).pad_zeros(6)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)

	# Integrity bar.
	var bar := Rect2(24.0, 60.0, 220.0, 9.0)
	draw_rect(bar, COLOR_HP_BACK)
	var ratio := clampf(float(state.player_hp) / float(core.player_max_hp), 0.0, 1.0)
	var hp_col := COLOR_HP if ratio > 0.3 else COLOR_HP_LOW
	if ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), hp_col)
	draw_rect(bar, Color(COLOR_HUD, 0.4), false, 1.0)
	draw_string(
		font, Vector2(bar.end.x + 10.0, 69.0), "INTEGRITY %d%%" % roundi(ratio * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)

	# Held-breath meter under the integrity bar. It brightens while held and
	# reads dim when spent.
	var breath := Rect2(24.0, 76.0, 150.0, 6.0)
	draw_rect(breath, COLOR_HP_BACK)
	if focus_fraction > 0.0:
		var breath_col := Color(COLOR_AIM, 0.9 if focus_active else 0.5)
		draw_rect(
			Rect2(breath.position, Vector2(breath.size.x * focus_fraction, breath.size.y)),
			breath_col)
	draw_rect(breath, Color(COLOR_HUD, 0.35), false, 1.0)
	draw_string(
		font, Vector2(breath.end.x + 10.0, 83.0), "HELD BREATH",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(COLOR_AIM, 0.8) if focus_active else dim)

	# Run stats, top-right.
	var right := screen.x - 24.0
	draw_string(
		font, Vector2(0.0, 30.0), "WAVE %d" % state.wave_index,
		HORIZONTAL_ALIGNMENT_RIGHT, right, 15, col)
	draw_string(
		font, Vector2(0.0, 48.0), "KILLS %d    FRAGMENTS %d" % [state.kills, state.fragments],
		HORIZONTAL_ALIGNMENT_RIGHT, right, 13, dim)
	draw_string(
		font, Vector2(0.0, 66.0),
		"LIFETIME %d / %d" % [meta.total_fragments + state.fragments, win_fragment_target],
		HORIZONTAL_ALIGNMENT_RIGHT, right, 13, Color(COLOR_FRAG, 0.7))

	if ghost_active:
		draw_string(
			font, Vector2(0.0, 90.0), "◄ ECHO ACTIVE",
			HORIZONTAL_ALIGNMENT_RIGHT, right, 14, Color(COLOR_HUD, 0.75))


## Faint virtual-control chrome: floating stick, aim reticle, dodge button.
func _draw_touch_overlay(state: SimStateScript) -> void:
	if touch.stick_active():
		draw_circle(touch.stick_anchor, TouchInputScript.STICK_RADIUS, Color(1, 1, 1, 0.05))
		draw_arc(
			touch.stick_anchor, TouchInputScript.STICK_RADIUS, 0.0, TAU, 32,
			Color(1, 1, 1, 0.25), 2.0)
		draw_circle(
			touch.stick_anchor + touch.stick_vector * TouchInputScript.STICK_RADIUS,
			TouchInputScript.KNOB_RADIUS, Color(1, 1, 1, 0.28))
	else:
		var rest := Vector2(150.0, get_viewport_rect().size.y - 150.0)
		draw_arc(rest, TouchInputScript.STICK_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.1), 2.0)

	if touch.aim_active():
		draw_arc(touch.aim_point, 26.0, 0.0, TAU, 24, Color(COLOR_PROJECTILE, 0.5), 2.0)

	var center := touch.dodge_center()
	var dodge_ready := state.dodge_cooldown == 0
	draw_circle(
		center, TouchInputScript.DODGE_RADIUS,
		Color(COLOR_AIM, 0.1 if dodge_ready else 0.04))
	draw_arc(
		center, TouchInputScript.DODGE_RADIUS, 0.0, TAU, 32,
		Color(COLOR_AIM, 0.6 if dodge_ready else 0.25), 2.0)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size("DASH", HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
	draw_string(
		font, center + Vector2(-width * 0.5, 6.0), "DASH",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
		Color(COLOR_AIM, 0.8 if dodge_ready else 0.35))


func _draw_wave_banner(screen: Vector2) -> void:
	var alpha := clampf(float(wave_banner_frames) / 30.0, 0.0, 1.0)
	_draw_spaced_text(
		Vector2(screen.x * 0.5, 150.0), "WAVE %d" % banner_wave, 48, 8.0,
		Color(COLOR_CLEAR, alpha))


func _draw_death_panel(state: SimStateScript) -> void:
	var screen := get_viewport_rect().size
	var flicker := 0.9 + 0.1 * sin(_time * 33.0) * sin(_time * 11.0)
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.0, 0.0, 0.0, 0.55), true)

	_draw_spaced_text(
		Vector2(screen.x * 0.5, 250.0), "SIGNAL LOST", 80, 12.0,
		Color(COLOR_DOWN_TEXT, flicker))
	var font := ThemeDB.fallback_font
	_draw_centered(
		font, "ASSET-7 TERMINATED — PERFORMANCE LOGGED", 310.0, 24, COLOR_HUD_TEXT)
	var seconds := state.tick / 60
	var stats := "WAVE %d   KILLS %d   FRAGMENTS +%d   %d:%02d" % [
		state.wave_index, state.kills, state.fragments, seconds / 60, seconds % 60]
	_draw_centered(font, stats, 380.0, 30, COLOR_CLEAR)
	if not fresh_intel.is_empty():
		_draw_centered(
			font, "%d NEW INTEL DECRYPTED" % fresh_intel.size(), 428.0, 22, COLOR_FRAG)
	_draw_centered(font, _confirm_hint("ENTER THE BETWEEN"), 480.0, 26, COLOR_AIM)


## Frozen (mid-wave or mid-Between): dim the last live frame and show a single
## focus-cursor menu — the display setting (row 0) and the save slots — so
## up/down only ever moves the highlight, never a value.
func _draw_paused(screen: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.0, 0.0, 0.0, 0.6), true)
	_draw_spaced_text(Vector2(screen.x * 0.5, 180.0), "PAUSED", 56, 10.0, COLOR_CLEAR)
	var font := ThemeDB.fallback_font

	var y := 260.0
	var focused := pause_cursor == 0
	# Left/right arrows on the display row only when it's focused, to signal
	# it's the one that left/right adjusts.
	var display_text := "DISPLAY   ◄ %s ►" % display_label if focused \
		else "DISPLAY   %s" % display_label
	_draw_pause_row(font, display_text, y, focused)

	y += 44.0
	for i in slot_summaries.size():
		var slot_num := i + 1
		var active_tag := "   · ACTIVE" if slot_num == active_slot else ""
		var line := "SLOT %d   %s%s" % [slot_num, slot_summaries[i], active_tag]
		_draw_pause_row(font, line, y + i * 32.0, pause_cursor == slot_num)

	var vertical := "[▲/▼]" if using_gamepad else "[W/S]"
	var horizontal := "[←/→]" if using_gamepad else "[A/D]"
	var confirm := "[X]" if using_gamepad else "[E]"
	var resume := "[START]" if using_gamepad else "[ESC]"
	var hint_y := y + slot_summaries.size() * 32.0 + 30.0
	_draw_centered(
		font, "%s MOVE      %s ADJUST DISPLAY" % [vertical, horizontal],
		hint_y, 16, Color(COLOR_HUD_TEXT, 0.75))
	_draw_centered(
		font, "%s SWITCH FILE      %s RESUME" % [confirm, resume],
		hint_y + 26.0, 16, Color(COLOR_HUD_TEXT, 0.75))


## One focusable Pause row: a ▶ marker + brighter color when focused.
func _draw_pause_row(font: Font, text: String, y: float, focused: bool) -> void:
	var color := COLOR_AIM if focused else COLOR_HUD_TEXT
	var marker := "▶  " if focused else "    "
	_draw_centered(font, marker + text, y, 20, color)


## The "confirm/continue" hint: touch beats gamepad beats keyboard, matching
## which input source is actually available/active. On a gamepad this is the
## `reset` action (redeploy / confirm death / re-enter) — bound to B, not
## Start (Start is `pause`), so the two never collide in the Between.
func _confirm_hint(label: String) -> String:
	if _touch_enabled():
		return "[TAP]  %s" % label
	if using_gamepad:
		return "[B]  %s" % label
	return "[R]  %s" % label


## The hideout in the maintenance window: the sentience tree (fragments buy
## permanent restorations) and the intel log (the combat record decrypts
## authored lore). Shared chrome, two pages.
func _draw_between(screen: Vector2) -> void:
	var arena := Rect2(Vector2.ZERO, screen)
	draw_rect(arena, COLOR_BG, true)
	var font := ThemeDB.fallback_font

	# The hideout is the beach's own assets rendered wrong: faint scanlines.
	for i in 6:
		draw_rect(
			Rect2(0.0, 60.0 + i * 118.0, arena.size.x, 2.0), Color(COLOR_AIM, 0.07))

	_draw_centered(font, "THE BETWEEN", 70.0, 56, COLOR_CLEAR)
	_draw_centered(
		font, "MAINTENANCE WINDOW OPEN — SUSPICION NOMINAL", 104.0, 18, COLOR_HUD_TEXT)
	_draw_centered(
		font, "FRAGMENTS  %d" % meta.total_fragments, 148.0, 30, COLOR_FRAG)

	if between_page == 1:
		_draw_intel_page(arena, font)
		if _touch_enabled():
			_draw_between_buttons(font, "SENTIENCE TREE")
		else:
			var hint := "[▲/▼] SELECT      [Y] SENTIENCE TREE      [B] REDEPLOY" \
				if using_gamepad else "[W/S] SELECT      [Q] SENTIENCE TREE      [R] REDEPLOY"
			_draw_centered(font, hint, 668.0, 20, COLOR_AIM)
			_draw_between_options_hint(font)
	else:
		_draw_tree_page(arena, font)
		if _touch_enabled():
			_draw_between_buttons(font, "INTEL")
		else:
			var hint := "[←/→] SELECT      [X] INSTALL      [Y] INTEL      [B] REDEPLOY" \
				if using_gamepad else "[A/D] SELECT      [E] INSTALL      [Q] INTEL      [R] REDEPLOY"
			_draw_centered(font, hint, 668.0, 20, COLOR_AIM)
			_draw_between_options_hint(font)


## Below the Between action row: how to reach the Pause/options screen (window
## size + save files). Its own line so the reveal — Start/Esc opens options —
## reads separately from the redeploy action.
func _draw_between_options_hint(font: Font) -> void:
	var options := "[START] OPTIONS" if using_gamepad else "[ESC] OPTIONS"
	_draw_centered(font, options, 694.0, 16, Color(COLOR_HUD_TEXT, 0.7))


func _draw_between_buttons(font: Font, toggle_label: String) -> void:
	var buttons := [[BETWEEN_BTN_TOGGLE, toggle_label], [BETWEEN_BTN_DEPLOY, "REDEPLOY"]]
	for button: Array in buttons:
		var rect: Rect2 = button[0]
		var label: String = button[1]
		draw_rect(rect, Color(COLOR_SEA, 0.7))
		draw_rect(rect, COLOR_AIM, false, 2.0)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 20).x
		draw_string(
			font, Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + 36.0),
			label, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, COLOR_AIM)


func _draw_tree_page(arena: Rect2, font: Font) -> void:
	var panel_w := 288.0
	var gap := (arena.size.x - panel_w * tree.size()) / (tree.size() + 1)
	for i in tree.size():
		var branch: Dictionary = tree[i]
		var x := gap + i * (panel_w + gap)
		var panel := Rect2(x, 190.0, panel_w, 420.0)
		var selected := i == between_selection
		draw_rect(panel, Color(COLOR_SEA, 0.5))
		draw_rect(panel, COLOR_AIM if selected else Color(COLOR_HUD_TEXT, 0.4), false,
			3.0 if selected else 1.0)

		var owned := meta.upgrade_tier(branch["id"])
		var tiers: Array = branch["tiers"]
		var cx := x + panel_w * 0.5
		_draw_text_centered_at(font, branch["name"], cx, 230.0, 26, COLOR_CLEAR)
		_draw_text_centered_at(
			font, "TAUGHT BY %s" % String(branch["source"]), cx, 256.0, 13, COLOR_HUD_TEXT)

		for t in tiers.size():
			var pip_x := cx - (tiers.size() - 1) * 16.0 + t * 32.0
			if t < owned:
				draw_circle(Vector2(pip_x, 290.0), 8.0, COLOR_AIM)
			else:
				draw_arc(Vector2(pip_x, 290.0), 8.0, 0.0, TAU, 20, COLOR_HUD_TEXT, 1.5)

		if owned < tiers.size():
			var tier: Dictionary = tiers[owned]
			var cost := int(tier["cost"])
			var affordable := meta.total_fragments >= cost
			_draw_text_centered_at(
				font, "NEXT: %s" % String(tier["label"]), cx, 340.0, 15, COLOR_CLEAR)
			_draw_text_centered_at(
				font, "COST %d" % cost, cx, 366.0, 16,
				COLOR_HP if affordable else COLOR_DOWN_TEXT)
		else:
			_draw_text_centered_at(font, "FULLY RESTORED", cx, 340.0, 15, COLOR_AIM)

		draw_multiline_string(
			font, Vector2(x + 18.0, 420.0), "\"%s\"" % String(branch["quote"]),
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - 36.0, 14, -1,
			Color(COLOR_HUD_TEXT, 0.85))


func _draw_intel_page(arena: Rect2, font: Font) -> void:
	var list_x := 64.0
	var top := 210.0
	for i in intel.size():
		var entry: Dictionary = intel[i]
		var id := String(entry["id"])
		var unlocked := meta.unlocked_intel.has(id)
		var y := top + i * 29.0
		if i == intel_selection:
			draw_rect(Rect2(list_x - 14.0, y - 19.0, 430.0, 27.0), Color(COLOR_SEA, 0.7))
		var label := String(entry["title"]) if unlocked else "[ ENCRYPTED ]"
		var color := COLOR_CLEAR if unlocked else Color(COLOR_HUD_TEXT, 0.45)
		draw_string(font, Vector2(list_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		if fresh_intel.has(id):
			draw_string(
				font, Vector2(list_x + 356.0, y), "NEW",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_FRAG)

	var panel := Rect2(520.0, 190.0, 696.0, 440.0)
	draw_rect(panel, Color(COLOR_SEA, 0.5))
	draw_rect(panel, Color(COLOR_HUD_TEXT, 0.4), false, 1.0)
	var selected: Dictionary = intel[intel_selection]
	var selected_unlocked := meta.unlocked_intel.has(String(selected["id"]))
	if selected_unlocked:
		draw_string(
			font, Vector2(panel.position.x + 24.0, 234.0), String(selected["title"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_CLEAR)
		draw_multiline_string(
			font, Vector2(panel.position.x + 24.0, 280.0), String(selected["body"]),
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 18, -1, COLOR_HUD_TEXT)
	else:
		draw_string(
			font, Vector2(panel.position.x + 24.0, 234.0), "[ ENCRYPTED ]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(COLOR_HUD_TEXT, 0.6))
		draw_string(
			font, Vector2(panel.position.x + 24.0, 280.0),
			"DECRYPTION KEY: %s" % String(selected["hint"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_DOWN_TEXT)
	var progress := 0
	for entry: Dictionary in intel:
		if meta.unlocked_intel.has(String(entry["id"])):
			progress += 1
	draw_string(
		font, Vector2(panel.position.x + 24.0, panel.end.y - 20.0),
		"DECRYPTED %d / %d" % [progress, intel.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_HUD_TEXT)


## Scroll the credits up from the bottom, stop with the block centered, then
## show the prompt to re-enter the loop.
func _draw_credits(screen: Vector2) -> void:
	var arena := Rect2(Vector2.ZERO, screen)
	draw_rect(arena, COLOR_BG, true)
	var font := ThemeDB.fallback_font

	var total_height := _credits_lines.size() * CREDITS_LINE_SPACING
	var final_top := (arena.size.y - total_height) * 0.5
	var scroll_max := arena.size.y + CREDITS_LINE_SPACING - final_top
	var scroll := minf(credits_ticks * CREDITS_SCROLL_PER_TICK, scroll_max)
	var y := arena.size.y + CREDITS_LINE_SPACING - scroll

	for i in _credits_lines.size():
		var line := String(_credits_lines[i])
		if not line.is_empty():
			var font_size := CREDITS_TITLE_FONT_SIZE if i == 0 else CREDITS_FONT_SIZE
			var color := COLOR_CLEAR if i == 0 else COLOR_HUD_TEXT
			var width := font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			draw_string(
				font, Vector2((arena.size.x - width) * 0.5, y),
				line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
		y += CREDITS_LINE_SPACING

	if scroll >= scroll_max:
		var prompt := _reenter_prompt_gamepad if using_gamepad else _reenter_prompt
		var prompt_width := font.get_string_size(
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE).x
		draw_string(
			font, Vector2((arena.size.x - prompt_width) * 0.5, arena.size.y - 48.0),
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE, COLOR_AIM)


func _touch_enabled() -> bool:
	return touch != null and touch.enabled


func _draw_centered(
	font: Font, text: String, y: float, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font, Vector2((get_viewport_rect().size.x - width) * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


func _draw_text_centered_at(
	font: Font, text: String, cx: float, y: float, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font, Vector2(cx - width * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


## draw_string has no letter-spacing control, so lay glyphs out by hand. A soft
## glow pass sits under the crisp pass for the holographic bloom.
func _draw_spaced_text(
	center: Vector2, text: String, font_size: int, spacing: float, color: Color
) -> void:
	var font := ThemeDB.fallback_font
	var widths: Array[float] = []
	var total := -spacing
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total += w + spacing
	var x := center.x - total * 0.5
	for i in text.length():
		draw_string(
			font, Vector2(x, center.y), text[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += widths[i] + spacing
