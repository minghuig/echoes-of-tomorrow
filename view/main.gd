extends Node2D
## View root: owns the SimCore, translates raw input into one Command per
## physics tick, and drives the run lifecycle (reset, seed selection,
## command-log recording), the persistent meta layer, the meta win state, and
## the ghost echo (a second SimCore re-running the previous run's
## (seed, loadout, command_log) in lockstep with live play).
##
## Rendering is delegated to four child nodes — Background (holo construct),
## World (sim entities), Effects (additive particles), Overlay (HUD + menus on
## a shake-immune CanvasLayer). All feedback (shake, hit-stop, particles) is
## DERIVED here by diffing successive SimStates; the sim emits no events and
## stays pure, so ghosts/replays get identical presentation for free. Juice
## dilates VIEW time only — a hit-stop frame skips the whole view tick (no
## command recorded, no sim step), so command logs stay 1:1 with sim ticks.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const SimCommand := preload("res://sim/command.gd")
const RunMetaScript := preload("res://view/run_meta.gd")
const DisplaySettingsScript := preload("res://view/display_settings.gd")
const SfxScript := preload("res://view/sfx.gd")
const TouchInputScript := preload("res://view/touch_input.gd")
const BackgroundScript := preload("res://view/background.gd")
const WorldScript := preload("res://view/world_renderer.gd")
const FxScript := preload("res://view/fx.gd")
const OverlayScript := preload("res://view/overlay.gd")

## A finished run, kept in memory as the data substrate for ghost replay.
## The loadout is part of the record: a run only replays exactly under the
## same (seed, loadout, command_log).
class RunRecord extends RefCounted:
	var seed_value: int = 0
	var command_log: Array[SimCommand] = []
	var loadout: Dictionary = {}

## View flow: normal play, paused (frozen mid-wave), the Between (sentience
## tree, entered after every death), or the credits roll after the meta win.
enum Mode { PLAYING, BETWEEN, CREDITS, PAUSED }

const BASE_SEED: int = 7
const STICK_AIM_DEADZONE: float = 0.35
## Joypad axis motion below this magnitude doesn't count as "using a gamepad"
## (stick drift/noise), for choosing which button hints to draw.
const GAMEPAD_DETECT_DEADZONE: float = 0.5

## Ignore the skip input for the first second so the R that ended the run
## can't also dismiss the credits.
const CREDITS_MIN_TICKS: int = 60

## Tap targets for the Between on touch devices (replace the key hints).
const BETWEEN_BTN_TOGGLE := Rect2(320.0, 636.0, 280.0, 56.0)
const BETWEEN_BTN_DEPLOY := Rect2(680.0, 636.0, 280.0, 56.0)

## Three independent save files, so starting over means switching to an
## unused slot instead of erasing the only one. `save.json` (pre-dating
## slots) is migrated into slot 1 on first boot under this scheme.
const SLOT_COUNT: int = 3
const LEGACY_SAVE_PATH := "user://save.json"
const ACTIVE_SLOT_PATH := "user://active_slot.json"
## Pause-screen rows: the display setting (row 0) plus one per save slot.
const PAUSE_ROW_COUNT: int = SLOT_COUNT + 1

# Feel-pass tuning (view frames, not sim ticks — hit-stop frames skip the
# view tick entirely, sim included, so logs stay aligned).
const HITSTOP_HIT_FRAMES: int = 2
const HITSTOP_DESTROY_FRAMES: int = 5
const HITSTOP_KILL_FRAMES: int = 3
const HITSTOP_HEAVY_KILL_FRAMES: int = 7
const HITSTOP_DEATH_FRAMES: int = 20
const SHAKE_HIT: float = 2.5
const SHAKE_DESTROY: float = 7.0
const SHAKE_KILL: float = 4.0
const SHAKE_HEAVY_KILL: float = 9.0
const SHAKE_HURT: float = 8.0
const SHAKE_DEATH: float = 14.0
const SHAKE_DECAY: float = 0.85
const HURT_FRAMES: int = 18
const WAVE_BANNER_FRAMES: int = 110

# The held breath: hold `focus` to run the world at quarter speed. Purely
# view-side pacing — the sim is stepped every FOCUS_STEP_DIV-th view frame
# (skipped frames record no command, exactly like hit-stop), so command logs
# stay 1:1 with sim ticks and replays/ghosts are untouched. The meter drains
# in wall-clock frames while held and refills while released.
const FOCUS_STEP_DIV: int = 4
const FOCUS_MAX: float = 180.0
const FOCUS_DRAIN: float = 1.0
const FOCUS_REGEN: float = 0.22
## Hit-stop frames when a fresh windup/barrage telegraph appears (the world
## hitches when death looks at you), rate-limited by a cooldown.
const HITCH_FRAMES: int = 6
const HITCH_COOLDOWN_FRAMES: int = 150

# Additive-FX + recoil tuning.
const TRAIL_LENGTH: int = 9
const RECOIL_KICK: float = 3.5
const RECOIL_DECAY: float = 0.6
const AFTERIMAGE_MIN_SPEED: float = 240.0
const THRUST_MIN_SPEED: float = 90.0

# Enemy tint per type, echoed by the world renderer, used for hit/kill sparks.
const ENEMY_COLORS := {
	"drone": Color("ff8c5a"),
	"infantry": Color("e05e51"),
	"heavy": Color("ff7a4f"),
}

var _core: SimCoreScript
var _meta: RunMetaScript
var _display: DisplaySettingsScript
## Which save file (1..SLOT_COUNT) `_meta` currently reads/writes.
var _active_slot: int = 1
## Focused row on the Pause screen: 0 = the display-size setting, 1..SLOT_COUNT
## = the save-file slots. up/down moves this focus and nothing else, so the
## display setting can only change when its own row is focused (left/right) —
## navigating the slot list never touches it.
var _pause_cursor: int = 0
var _run_seed: int = 0
var _run_loadout: Dictionary = {}
var _command_log: Array[SimCommand] = []
var _last_run: RunRecord = null
var _mode: Mode = Mode.PLAYING
## Which mode Pause was entered from (Playing or Between), so resuming
## returns to the right screen.
var _mode_before_pause: Mode = Mode.PLAYING
var _credits_ticks: int = 0
## Last device to produce a raw input event — purely a view cosmetic (which
## button hints to draw), never read by the sim.
var _using_gamepad: bool = false
var _win_fragment_target: int = 0
## Mines a run starts with once the dispenser schematic is owned (tuning).
var _mine_base_stock: int = 0
## Schematic ids recovered by the most recent banked run (death panel line).
var _fresh_schematics: Array = []

# The sentience tree (content/sentience_tree.json) and Between UI state.
var _tree: Array = []
var _between_selection: int = 0
var _between_ticks: int = 0
## 0 = sentience tree, 1 = intel log.
var _between_page: int = 0

# The intel log (content/intel.json): authored lore decrypted by the
# lifetime combat record. Deaths convert to knowledge, literally.
var _intel: Array = []
var _intel_selection: int = 0
## Entry ids decrypted by the most recent banked run (highlighted as NEW).
var _fresh_intel: Array = []
## A run's results bank exactly once (at death, or at manual reset).
var _run_banked: bool = false

# Ghost echo of the previous run: a parallel SimCore fed the recorded
# command log, one tick per live tick. Never touches the live sim.
var _ghost_core: SimCoreScript = null
var _ghost_log: Array[SimCommand] = []
var _ghost_tick: int = 0

# Feel layer. _fx_rng is view-local randomness (shake jitter) — it must
# never be the sim's RNG.
var _hitstop_frames: int = 0
var _shake: float = 0.0
# Held-breath state (view-only; see FOCUS_* above).
var _focus_meter: float = FOCUS_MAX
var _focus_active: bool = false
var _focus_gate: int = 0
var _hitch_cooldown: int = 0
var _shake_offset: Vector2 = Vector2.ZERO
var _recoil: Vector2 = Vector2.ZERO
var _fx_rng := RandomNumberGenerator.new()
var _hurt_frames: int = 0
var _wave_banner_frames: int = 0
var _banner_wave: int = 0

# Interpolation-free tracer bookkeeping, keyed by projectile instance id.
# Shared by reference with the world renderer.
var _proj_prev: Dictionary[int, Vector2] = {}
var _proj_trails: Dictionary[int, PackedVector2Array] = {}

var _sfx_fire: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_break: AudioStreamPlayer
var _sfx_clear: AudioStreamPlayer
var _sfx_enemy_hit: AudioStreamPlayer
var _sfx_enemy_die: AudioStreamPlayer
var _sfx_hurt: AudioStreamPlayer
var _sfx_wave: AudioStreamPlayer
var _sfx_buy: AudioStreamPlayer

## Virtual touch controls — active only on web with a touchscreen.
var _touch := TouchInputScript.new()

@onready var _background: BackgroundScript = $Background
@onready var _world: WorldScript = $World
@onready var _fx: FxScript = $Effects
@onready var _camera: Camera2D = $Camera
@onready var _overlay: OverlayScript = $OverlayLayer/Overlay

## How far the camera leads toward the aim direction.
const CAMERA_LOOKAHEAD: float = 90.0


func _ready() -> void:
	_migrate_legacy_save()
	_active_slot = _load_active_slot()
	_meta = RunMetaScript.new()
	_meta.load_from_disk(_slot_path(_active_slot))
	_display = DisplaySettingsScript.new()
	_display.load_from_disk()
	_display.apply(get_window())
	_win_fragment_target = _load_win_target()
	_tree = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/sentience_tree.json"))["branches"]
	_intel = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/intel.json"))["entries"]
	_fx_rng.randomize()
	_sfx_fire = _make_sfx_player(SfxScript.fire_blip(), -16.0)
	_sfx_hit = _make_sfx_player(SfxScript.block_hit(), -10.0)
	_sfx_break = _make_sfx_player(SfxScript.block_break(), -6.0)
	_sfx_clear = _make_sfx_player(SfxScript.clear_chime(), -6.0)
	_sfx_enemy_hit = _make_sfx_player(SfxScript.enemy_hit(), -12.0)
	_sfx_enemy_die = _make_sfx_player(SfxScript.enemy_die(), -8.0)
	_sfx_hurt = _make_sfx_player(SfxScript.player_hurt(), -5.0)
	_sfx_wave = _make_sfx_player(SfxScript.wave_horn(), -8.0)
	_sfx_buy = _make_sfx_player(SfxScript.buy_blip(), -8.0)

	# Wire the render nodes. References that outlive a run are set once here;
	# the per-run SimCore is (re)pointed in _start_run().
	_world.proj_trails = _proj_trails
	_overlay.meta = _meta
	_overlay.tree = _tree
	_overlay.intel = _intel
	_overlay.touch = _touch
	_overlay.win_fragment_target = _win_fragment_target

	_start_run()
	# Touch chrome is screen-space (the viewport), not world-space — the
	# arena is bigger than the screen now that the camera scrolls.
	_touch.setup(get_viewport().get_visible_rect().size)
	_background.arena_size = _core.state.arena_size
	_present()


func _input(event: InputEvent) -> void:
	_touch.handle(event)
	_track_input_device(event)


## Which device produced this event decides which button hints Overlay draws
## (e.g. [B] vs [R]) — cosmetic only, never fed into a Command.
func _track_input_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_using_gamepad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > GAMEPAD_DETECT_DEADZONE:
			_using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_using_gamepad = false


func _make_sfx_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _physics_process(_delta: float) -> void:
	if _mode == Mode.PAUSED:
		_process_paused_input()
		_present()
		return

	if _mode == Mode.CREDITS:
		_credits_ticks += 1
		if _credits_ticks >= CREDITS_MIN_TICKS and (
			Input.is_action_just_pressed("reset") or _consumed_tap()):
			_mode = Mode.PLAYING
			_start_run()
		_present()
		return

	if _mode == Mode.BETWEEN:
		_between_ticks += 1
		if Input.is_action_just_pressed("pause"):
			_open_pause(Mode.BETWEEN)
			_present()
			return
		if Input.is_action_just_pressed("intel"):
			_between_page = 1 - _between_page
		if _between_page == 1:
			if Input.is_action_just_pressed("move_up"):
				_intel_selection = (_intel_selection + _intel.size() - 1) % _intel.size()
			if Input.is_action_just_pressed("move_down"):
				_intel_selection = (_intel_selection + 1) % _intel.size()
		else:
			if Input.is_action_just_pressed("move_left"):
				_between_selection = (_between_selection + _tree.size() - 1) % _tree.size()
			if Input.is_action_just_pressed("move_right"):
				_between_selection = (_between_selection + 1) % _tree.size()
			if Input.is_action_just_pressed("buy"):
				_try_buy()
		_handle_between_taps()
		if _mode == Mode.BETWEEN and _between_ticks >= 5 \
				and Input.is_action_just_pressed("reset"):
			_mode = Mode.PLAYING
			_start_run()
		_present()
		return

	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		_decay_fx()
		_present()
		return

	# Down: the sim froze itself; bank the run now so the death panel can
	# announce fresh decrypts, then hold until redeploy.
	if _core.state.player_down:
		_bank_run_results()
		_decay_fx()
		if Input.is_action_just_pressed("reset") or _consumed_tap():
			_end_run()
		_present()
		return

	if Input.is_action_just_pressed("pause"):
		_open_pause(Mode.PLAYING)
		_present()
		return

	if Input.is_action_just_pressed("reset"):
		_end_run()
		_present()
		return

	# The held breath: while held (and the meter lasts), only every
	# FOCUS_STEP_DIV-th view frame steps the sim. Skipped frames render and
	# decay fx but record no command — the hit-stop contract.
	_focus_active = Input.is_action_pressed("focus") and _focus_meter > 0.0
	if _focus_active:
		_focus_meter = maxf(_focus_meter - FOCUS_DRAIN, 0.0)
		_focus_gate += 1
		if _focus_gate % FOCUS_STEP_DIV != 0:
			_decay_fx()
			_present()
			return
	else:
		_focus_meter = minf(_focus_meter + FOCUS_REGEN, FOCUS_MAX)

	var state: SimStateScript = _core.state
	var pre_fire_cooldown := state.fire_cooldown
	var pre_hp := state.player_hp
	var pre_wave := state.wave_index
	var pre_dodge_cd := state.dodge_cooldown
	var pre_blocks := _snapshot_blocks()
	var pre_enemies := _snapshot_enemies()
	var pre_projectiles: Array[SimStateScript.Projectile] = state.projectiles.duplicate()
	for p: SimStateScript.Projectile in state.projectiles:
		_proj_prev[p.get_instance_id()] = p.pos

	var pre_impacts: Array[SimStateScript.Impact] = state.pending_impacts.duplicate()
	var pre_caches: Array[SimStateScript.Cache] = state.caches.duplicate()
	var pre_pickups: Array[SimStateScript.Pickup] = state.pickups.duplicate()
	var pre_mines: Array[SimStateScript.Mine] = state.mines.duplicate()

	var cmd := _build_command()
	_command_log.append(cmd)
	_core.step(cmd)
	_step_ghost()

	_emit_impact_events(state, pre_impacts)
	_emit_fixture_events(state, pre_caches, pre_pickups, pre_mines)

	_emit_feel_events(
		cmd.fire and pre_fire_cooldown == 0, pre_blocks, pre_enemies, pre_hp, pre_wave)
	_diff_projectiles(state, pre_projectiles)
	_emit_player_feedback(state, pre_dodge_cd)
	_update_trails(state)
	_decay_fx()
	# Combat touches (stick, aim, dodge) also land in the tap list; they mean
	# nothing during play, so drop them instead of letting them pile up.
	_touch.consume_taps()
	_present()


## Push feel state onto the render nodes and reconcile mode visibility. Called
## at the end of every view tick (the sim never reads any of this back).
func _present() -> void:
	_world.position = _shake_offset
	_fx.position = _shake_offset
	_world.recoil = _recoil
	_update_camera()


## Follow the player with a little lead toward the aim, clamped so the view
## never leaves the arena. Smoothing is on the Camera2D node itself.
func _update_camera() -> void:
	var half := get_viewport().get_visible_rect().size * 0.5
	var arena: Vector2 = _core.state.arena_size
	var target: Vector2 = _core.state.player_pos \
		+ _core.state.player_aim * CAMERA_LOOKAHEAD
	_camera.position = Vector2(
		clampf(target.x, half.x, arena.x - half.x),
		clampf(target.y, half.y, arena.y - half.y))

	_overlay.mode = _mode
	_overlay.between_selection = _between_selection
	_overlay.between_page = _between_page
	_overlay.intel_selection = _intel_selection
	_overlay.fresh_intel = _fresh_intel
	_overlay.banner_wave = _banner_wave
	_overlay.wave_banner_frames = _wave_banner_frames
	_overlay.hurt_frames = _hurt_frames
	_overlay.credits_ticks = _credits_ticks
	_overlay.ghost_active = _ghost_active()
	_overlay.using_gamepad = _using_gamepad
	_overlay.focus_fraction = _focus_meter / FOCUS_MAX
	_overlay.focus_active = _focus_active
	_overlay.mine_stock = _core.state.mine_stock
	_overlay.mines_unlocked = _meta.schematics.has("mine_dispenser")
	_overlay.fresh_schematics = _fresh_schematics
	_overlay.display_label = _display.label()
	_overlay.mode_before_pause = _mode_before_pause
	_overlay.slot_summaries = _slot_summaries()
	_overlay.active_slot = _active_slot
	_overlay.pause_cursor = _pause_cursor

	# Paused freezes on the last live frame (world/background/fx keep their
	# last-drawn state) with the pause chrome drawn on top by Overlay — but
	# only if Pause was entered from PLAYING; from the Between, the frozen
	# frame beneath the dim should stay the Between screen, not the beach.
	var playing := _mode == Mode.PLAYING \
		or (_mode == Mode.PAUSED and _mode_before_pause == Mode.PLAYING)
	_background.visible = playing
	_world.visible = playing
	_fx.visible = playing


## Enter the Pause screen from `from` (Playing or Between), focusing the top
## row so navigation starts predictably.
func _open_pause(from: Mode) -> void:
	_mode_before_pause = from
	_mode = Mode.PAUSED
	_pause_cursor = 0


## Pause screen input, structured as a focus cursor over the display setting
## (row 0) and the save slots (rows 1..SLOT_COUNT): up/down only moves focus,
## left/right adjusts the display *only* while its row is focused, and confirm
## (buy) acts on the focused slot. So navigating the list can never change the
## display by accident (the earlier always-live left/right binding did, badly
## on an analog stick where up/down drifts into the left/right axis).
func _process_paused_input() -> void:
	if Input.is_action_just_pressed("pause"):
		_mode = _mode_before_pause
		return
	if Input.is_action_just_pressed("move_up"):
		_pause_cursor = (_pause_cursor + PAUSE_ROW_COUNT - 1) % PAUSE_ROW_COUNT
		return
	if Input.is_action_just_pressed("move_down"):
		_pause_cursor = (_pause_cursor + 1) % PAUSE_ROW_COUNT
		return

	if _pause_cursor == 0:
		# Display row: left/right cycles window size (applied live and saved).
		if Input.is_action_just_pressed("move_left"):
			_display.cycle(-1)
			_display.apply(get_window())
			_display.save_to_disk()
		elif Input.is_action_just_pressed("move_right"):
			_display.cycle(1)
			_display.apply(get_window())
			_display.save_to_disk()
	elif Input.is_action_just_pressed("buy"):
		# Slot row: confirm the focused slot. The active slot just resumes
		# (continue this file); another slot switches to it.
		var slot := _pause_cursor
		if slot == _active_slot:
			_mode = _mode_before_pause
		else:
			_switch_slot(slot)


## Path for a given save-file slot (1..SLOT_COUNT).
func _slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


## One line per slot for the Pause screen's save-file list: run count,
## fragments, and wins read straight off disk (no RunMeta instantiated) so
## picking a slot never has a side effect on any file but the active one.
func _slot_summaries() -> Array[String]:
	var summaries: Array[String] = []
	for slot in range(1, SLOT_COUNT + 1):
		var path := _slot_path(slot)
		if not FileAccess.file_exists(path):
			summaries.append("EMPTY — NEW GAME")
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			summaries.append("EMPTY — NEW GAME")
			continue
		var runs := int(parsed.get("run_count", 0))
		var fragments := int(parsed.get("total_fragments", 0))
		var wins := int(parsed.get("wins", 0))
		summaries.append("RUN %d · %d FRAGMENTS · %d WIN%s" % [
			runs, fragments, wins, "" if wins == 1 else "S"])
	return summaries


## A pre-slots save.json (single file) becomes slot 1 the first time this
## scheme runs, so existing progress isn't stranded behind the new UI.
func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(_slot_path(1)) or not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var legacy := RunMetaScript.new()
	legacy.load_from_disk(LEGACY_SAVE_PATH)
	legacy.save_to_disk(_slot_path(1))


func _load_active_slot() -> int:
	if not FileAccess.file_exists(ACTIVE_SLOT_PATH):
		return 1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTIVE_SLOT_PATH))
	if parsed is Dictionary:
		return clampi(int(parsed.get("slot", 1)), 1, SLOT_COUNT)
	return 1


func _save_active_slot() -> void:
	var file := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("main: cannot write " + ACTIVE_SLOT_PATH)
		return
	file.store_string(JSON.stringify({"slot": _active_slot}))


## Switch the active save file and drop straight into a run under it —
## loading its progress if it has any, or starting fresh if it's empty. The
## "start a new file" the Pause screen exposes is just switching to an
## unused slot; the other two slots are left untouched either way.
func _switch_slot(slot: int) -> void:
	if slot == _active_slot:
		return
	_active_slot = slot
	_save_active_slot()
	_meta = RunMetaScript.new()
	_meta.load_from_disk(_slot_path(_active_slot))
	_overlay.meta = _meta
	_last_run = null
	_mode = Mode.PLAYING
	_start_run()


## True if the player tapped anywhere this frame (touch devices only).
func _consumed_tap() -> bool:
	return _touch.enabled and not _touch.consume_taps().is_empty()


## Touch UI for the Between: tap a branch to select it, tap it again to
## install; tap intel rows to read; bottom buttons flip pages and redeploy.
func _handle_between_taps() -> void:
	if not _touch.enabled:
		return
	for tap: Vector2 in _touch.consume_taps():
		if BETWEEN_BTN_TOGGLE.has_point(tap):
			_between_page = 1 - _between_page
		elif BETWEEN_BTN_DEPLOY.has_point(tap) and _between_ticks >= 5:
			_mode = Mode.PLAYING
			_start_run()
			return
		elif _between_page == 1:
			# Rows drawn at y = 210 + i * 29 (baseline), highlight from y-19.
			var row := int((tap.y - 191.0) / 29.0)
			if tap.x < 500.0 and row >= 0 and row < _intel.size():
				_intel_selection = row
		else:
			var panel_w := 288.0
			var screen_w := get_viewport().get_visible_rect().size.x
			var gap := (screen_w - panel_w * _tree.size()) / (_tree.size() + 1)
			for i in _tree.size():
				if Rect2(gap + i * (panel_w + gap), 190.0, panel_w, 420.0).has_point(tap):
					if i == _between_selection:
						_try_buy()
					else:
						_between_selection = i
					break


## Fold the run's results into the persistent record exactly once: fragments
## bank, the combat record grows, and the intel log re-evaluates its locks.
func _bank_run_results() -> void:
	if _run_banked:
		return
	_run_banked = true
	var s: SimStateScript = _core.state
	_meta.total_fragments += s.fragments
	_meta.lifetime_fragments += s.fragments
	_meta.lifetime_kills += s.kills
	_meta.best_wave = maxi(_meta.best_wave, s.wave_index)
	if s.player_down:
		_meta.deaths += 1
	for schematic: String in s.schematics_found:
		if not _meta.schematics.has(schematic):
			_meta.schematics.append(schematic)
			_fresh_schematics.append(schematic)
	var fresh: Array = _meta.evaluate_intel(_intel)
	if not fresh.is_empty():
		_fresh_intel = fresh
		_sfx_buy.play()
	_meta.save_to_disk(_slot_path(_active_slot))


## Tear down the current run — retain its (seed, loadout, command_log), make
## sure its results are banked — then roll credits (first time the lifetime
## fragment target is reached) or drop into the Between.
func _end_run() -> void:
	_bank_run_results()
	var record := RunRecord.new()
	record.seed_value = _run_seed
	record.command_log = _command_log
	record.loadout = _run_loadout
	_last_run = record
	if _meta.wins == 0 and _meta.total_fragments >= _win_fragment_target:
		_meta.wins += 1
		_meta.save_to_disk(_slot_path(_active_slot))
		_mode = Mode.CREDITS
		_credits_ticks = 0
		_sfx_clear.play()
		return
	_mode = Mode.BETWEEN
	_between_ticks = 0


func _try_buy() -> void:
	var branch: Dictionary = _tree[_between_selection]
	var owned := _meta.upgrade_tier(branch["id"])
	var tiers: Array = branch["tiers"]
	if owned >= tiers.size():
		return
	var cost := int(tiers[owned]["cost"])
	if _meta.total_fragments < cost:
		return
	_meta.total_fragments -= cost
	_meta.upgrades[branch["id"]] = owned + 1
	# Restorations can decrypt intel too (the Deprecated notice the work).
	var fresh: Array = _meta.evaluate_intel(_intel)
	if not fresh.is_empty():
		_fresh_intel.append_array(fresh)
	_meta.save_to_disk(_slot_path(_active_slot))
	_sfx_buy.play()


## Flatten owned tiers into the stat-modifier dict the sim consumes. Tier
## effects are absolute (not stacking), so only the owned tier applies.
func _resolve_loadout() -> Dictionary:
	var loadout := {}
	for branch: Dictionary in _tree:
		var owned := _meta.upgrade_tier(branch["id"])
		if owned <= 0:
			continue
		var effects: Dictionary = branch["tiers"][owned - 1]["effects"]
		for key in effects:
			loadout[key] = effects[key]
	# Schematic gear: owning the dispenser blueprint stocks the run's mines.
	if _meta.schematics.has("mine_dispenser"):
		loadout["mine_stock"] = _mine_base_stock
	return loadout


## The meta win threshold is tuning data, not code (content covenant). It
## lives outside the sim's sections: the sim never sees the win condition.
func _load_win_target() -> int:
	var tuning: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/tuning.json"))
	_mine_base_stock = int(tuning.get("mine", {}).get("stock", 0))
	return int(tuning["meta"]["win_fragment_target"])


## Seed selection is meta-layer policy: derived from the lifetime run index,
## never from inside the sim. Each run stays reproducible from
## (_run_seed, _command_log).
func _start_run() -> void:
	_meta.run_count += 1
	_meta.save_to_disk(_slot_path(_active_slot))
	_run_seed = BASE_SEED + _meta.run_count
	_command_log = []
	_hitstop_frames = 0
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	_recoil = Vector2.ZERO
	_hurt_frames = 0
	_wave_banner_frames = 0
	_focus_meter = FOCUS_MAX
	_focus_active = false
	_focus_gate = 0
	_hitch_cooldown = 0
	_run_banked = false
	_fresh_intel = []
	_fresh_schematics = []
	_proj_prev.clear()
	_proj_trails.clear()
	if _fx != null:
		_fx.clear()
	_run_loadout = _resolve_loadout()
	_core = SimCoreScript.new()
	_core.setup(_run_seed, _run_loadout)
	_world.core = _core
	_overlay.core = _core
	# The tide is per-seed sim state; the backdrop paints to it.
	_background.sea_depth = _core.state.surf_line
	if _camera != null:
		_update_camera()
		_camera.reset_smoothing()
	_spawn_ghost()


## Re-run the previous run verbatim as a translucent echo: a fresh SimCore
## seeded with the recorded seed, stepped one recorded command per live tick.
func _spawn_ghost() -> void:
	_ghost_core = null
	_ghost_log = []
	_ghost_tick = 0
	if _last_run == null or _last_run.command_log.is_empty():
		_world.ghost_core = null
		return
	_ghost_core = SimCoreScript.new()
	_ghost_core.setup(_last_run.seed_value, _last_run.loadout)
	_ghost_log = _last_run.command_log
	_world.ghost_core = _ghost_core


## Advance the echo in lockstep with live play. When its log runs out the
## echo has caught up to where the previous run ended, and it derezzes.
func _step_ghost() -> void:
	if _ghost_core == null or _ghost_tick >= _ghost_log.size():
		if _ghost_tick >= _ghost_log.size():
			_world.ghost_core = null
		return
	_ghost_core.step(_ghost_log[_ghost_tick])
	_ghost_tick += 1


func _ghost_active() -> bool:
	return _ghost_core != null and _ghost_tick < _ghost_log.size()


## Compare block state across one sim step to spot hits and kills. Keyed by
## position — blocks never move.
func _snapshot_blocks() -> Dictionary:
	var by_pos := {}
	for b: SimStateScript.Block in _core.state.blocks:
		by_pos[b.pos] = {"hp": b.hp, "size": b.size}
	return by_pos


## Enemies move, so key by object identity (refs persist across ticks).
func _snapshot_enemies() -> Dictionary:
	var by_ref := {}
	for e: SimStateScript.Enemy in _core.state.enemies:
		by_ref[e] = {"hp": e.hp, "pos": e.pos, "type": e.type, "phase": e.phase}
	return by_ref


## Turn this tick's sim delta into juice: hit-stop, shake, particles, SFX.
func _emit_feel_events(
	fired: bool, pre_blocks: Dictionary, pre_enemies: Dictionary,
	pre_hp: int, pre_wave: int
) -> void:
	if fired:
		_sfx_fire.play()

	var now_blocks := {}
	for b: SimStateScript.Block in _core.state.blocks:
		now_blocks[b.pos] = b
	var block_destroyed := 0
	var block_damaged := 0
	for pos: Vector2 in pre_blocks:
		var prev: Dictionary = pre_blocks[pos]
		var rect := Rect2(pos, prev["size"])
		if not now_blocks.has(pos):
			block_destroyed += 1
			_fx.block_destroyed(rect)
		elif (now_blocks[pos] as SimStateScript.Block).hp < int(prev["hp"]):
			block_damaged += 1
			_fx.block_hit(rect)

	var now_enemies := {}
	for e: SimStateScript.Enemy in _core.state.enemies:
		now_enemies[e] = true
	var kills := 0
	var heavy_kill := false
	var enemy_hits := 0
	var slams := 0
	for key in pre_enemies:
		var e: SimStateScript.Enemy = key
		var prev: Dictionary = pre_enemies[key]
		var type := String(prev["type"])
		var radius: float = _core.enemy_types[type]["radius"]
		if not now_enemies.has(e):
			kills += 1
			heavy_kill = heavy_kill or type == "heavy"
			_fx.enemy_destroyed(prev["pos"], radius, _enemy_color(type))
		elif e.hp < int(prev["hp"]):
			enemy_hits += 1
			_fx.enemy_hit(e.pos, _enemy_color(type))
		# A slammer that left WINDUP for RECOVER landed its slam this tick.
		if now_enemies.has(e) \
				and int(prev["phase"]) == SimCoreScript.PHASE_WINDUP \
				and e.phase == SimCoreScript.PHASE_RECOVER \
				and String(_core.enemy_types[type]["behavior"]) == "slammer":
			slams += 1
			var slam_radius: float = _core.enemy_types[type]["slam_radius"]
			_fx.ring(e.pos, Color.WHITE, radius, slam_radius, 0.28, 6.0)
			_fx.ring(e.pos, _enemy_color(type), radius * 0.6, slam_radius * 0.8, 0.22, 4.0)

	if block_destroyed > 0:
		_hitstop_frames = maxi(_hitstop_frames, HITSTOP_DESTROY_FRAMES)
		_shake = maxf(_shake, SHAKE_DESTROY)
		_sfx_break.play()
	elif block_damaged > 0:
		_hitstop_frames = maxi(_hitstop_frames, HITSTOP_HIT_FRAMES)
		_shake = maxf(_shake, SHAKE_HIT)
		_sfx_hit.play()

	if kills > 0:
		_hitstop_frames = maxi(
			_hitstop_frames,
			HITSTOP_HEAVY_KILL_FRAMES if heavy_kill else HITSTOP_KILL_FRAMES)
		_shake = maxf(_shake, SHAKE_HEAVY_KILL if heavy_kill else SHAKE_KILL)
		_sfx_enemy_die.play()
	elif enemy_hits > 0:
		_sfx_enemy_hit.play()

	if slams > 0:
		_shake = maxf(_shake, SHAKE_DESTROY)
		_sfx_break.play()

	if _core.state.player_hp < pre_hp:
		_hurt_frames = HURT_FRAMES
		_shake = maxf(_shake, SHAKE_HURT)
		_sfx_hurt.play()
		if _core.state.player_down:
			_hitstop_frames = maxi(_hitstop_frames, HITSTOP_DEATH_FRAMES)
			_shake = maxf(_shake, SHAKE_DEATH)

	if _core.state.wave_index > pre_wave:
		_banner_wave = _core.state.wave_index
		_wave_banner_frames = WAVE_BANNER_FRAMES
		_sfx_wave.play()

	# The world hitches for a beat when a fresh threat telegraphs — a windup
	# starting or a barrage being called in — rate-limited so dense waves
	# don't turn into a slideshow.
	if _hitch_cooldown == 0:
		var fresh_telegraph := false
		for key in pre_enemies:
			var e: SimStateScript.Enemy = key
			if now_enemies.has(e) and e.phase == SimCoreScript.PHASE_WINDUP \
					and int(pre_enemies[key]["phase"]) != SimCoreScript.PHASE_WINDUP:
				fresh_telegraph = true
				break
		if fresh_telegraph:
			_hitstop_frames = maxi(_hitstop_frames, HITCH_FRAMES)
			_hitch_cooldown = HITCH_COOLDOWN_FRAMES


## Shells that left pending_impacts this tick landed: explosion fx + shake.
func _emit_impact_events(
	state: SimStateScript, pre_impacts: Array[SimStateScript.Impact]
) -> void:
	if pre_impacts.is_empty():
		return
	var still := {}
	for imp: SimStateScript.Impact in state.pending_impacts:
		still[imp] = true
	var landed := 0
	for imp: SimStateScript.Impact in pre_impacts:
		if still.has(imp):
			continue
		landed += 1
		_fx.explosion(imp.pos, imp.radius)
	if landed > 0:
		_shake = maxf(_shake, SHAKE_DESTROY)
		_hitstop_frames = maxi(_hitstop_frames, HITSTOP_HIT_FRAMES)
		_sfx_break.play()


## Fixture/loot deltas -> juice: cracked caches shatter, collected salvage
## chimes, detonated mines explode.
func _emit_fixture_events(
	state: SimStateScript,
	pre_caches: Array[SimStateScript.Cache],
	pre_pickups: Array[SimStateScript.Pickup],
	pre_mines: Array[SimStateScript.Mine],
) -> void:
	var still_caches := {}
	for c: SimStateScript.Cache in state.caches:
		still_caches[c] = true
	for c: SimStateScript.Cache in pre_caches:
		if not still_caches.has(c):
			_fx.block_destroyed(Rect2(c.pos, c.size))
			_shake = maxf(_shake, SHAKE_DESTROY)
			_sfx_break.play()

	var still_pickups := {}
	for p: SimStateScript.Pickup in state.pickups:
		still_pickups[p] = true
	for p: SimStateScript.Pickup in pre_pickups:
		if still_pickups.has(p):
			continue
		# Removed pickup: collected if it still had life left (expiry fizzles).
		if p.ttl > 1:
			_fx.ring(p.pos, Color("6ee08a"), 4.0, 30.0, 0.25, 3.0)
			_sfx_buy.play()
		else:
			_fx.fizzle(p.pos)

	var still_mines := {}
	for m: SimStateScript.Mine in state.mines:
		still_mines[m] = true
	for m: SimStateScript.Mine in pre_mines:
		if not still_mines.has(m):
			_fx.explosion(m.pos, 72.0)
			_shake = maxf(_shake, SHAKE_DESTROY)
			_sfx_break.play()


## Diff the projectile set to spawn muzzle flashes (on new bolts), recoil, and
## impact sparks + trail ghosts (on removed bolts).
func _diff_projectiles(
	state: SimStateScript, pre_projectiles: Array[SimStateScript.Projectile]
) -> void:
	var cur_ids: Dictionary[int, bool] = {}
	for p: SimStateScript.Projectile in state.projectiles:
		cur_ids[p.get_instance_id()] = true

	# New projectile => the player fired this tick.
	var first_new := true
	for p: SimStateScript.Projectile in state.projectiles:
		var id := p.get_instance_id()
		if _proj_prev.has(id):
			continue
		var dir := p.vel.normalized()
		# The sim already advanced the new projectile once; back up to the muzzle.
		var muzzle := p.pos - p.vel * SimCoreScript.DT
		_proj_prev[id] = muzzle
		_fx.muzzle_flash(muzzle, dir)
		if first_new:
			_recoil = -dir * RECOIL_KICK
			first_new = false

	# Removed projectile => impact (or quiet fizzle at end of life).
	var margin := _core.projectile_radius + 2.0
	for p: SimStateScript.Projectile in pre_projectiles:
		var id := p.get_instance_id()
		if cur_ids.has(id):
			continue
		var last: Vector2 = _proj_prev.get(id, p.pos)
		var inside := (
			last.x > margin and last.y > margin
			and last.x < state.arena_size.x - margin
			and last.y < state.arena_size.y - margin
		)
		if inside and p.ttl > 0:
			_fx.impact(last, -p.vel.normalized())
		elif inside:
			_fx.fizzle(last)
		var trail: PackedVector2Array = _proj_trails.get(id, PackedVector2Array())
		if trail.size() >= 2:
			_fx.trail_ghost(trail)
		_proj_trails.erase(id)
		_proj_prev.erase(id)


## Dodge burst, dodge afterimages, and thrust motes, all derived from player
## state — no sim events involved.
func _emit_player_feedback(state: SimStateScript, pre_dodge_cd: int) -> void:
	if state.dodge_cooldown > pre_dodge_cd and state.dodge_vel != Vector2.ZERO:
		_fx.dodge_burst(state.player_pos, state.dodge_vel.normalized())

	if state.dodge_vel.length() > AFTERIMAGE_MIN_SPEED:
		_fx.afterimage(
			state.player_pos,
			state.player_aim.angle() + PI / 2.0,
			_core.player_radius,
			_core.player_radius * 0.45,
		)

	if state.player_vel.length() > THRUST_MIN_SPEED and state.tick % 2 == 0:
		var back := -state.player_vel.normalized()
		_fx.thrust(
			state.player_pos + back * (_core.player_radius + 2.0),
			state.player_vel * -0.12,
		)


func _update_trails(state: SimStateScript) -> void:
	for p: SimStateScript.Projectile in state.projectiles:
		var id := p.get_instance_id()
		var trail: PackedVector2Array = _proj_trails.get(id, PackedVector2Array())
		trail.append(p.pos)
		if trail.size() > TRAIL_LENGTH:
			trail = trail.slice(trail.size() - TRAIL_LENGTH)
		_proj_trails[id] = trail
		_proj_prev[id] = p.pos


func _enemy_color(type: String) -> Color:
	return ENEMY_COLORS.get(type, ENEMY_COLORS["heavy"])


## Advance shake/recoil timers one view frame (runs during hit-stop too, so the
## freeze still vibrates and the recoil settles).
func _decay_fx() -> void:
	_shake *= SHAKE_DECAY
	if _shake < 0.1:
		_shake = 0.0
		_shake_offset = Vector2.ZERO
	else:
		_shake_offset = Vector2(
			_fx_rng.randf_range(-_shake, _shake),
			_fx_rng.randf_range(-_shake, _shake))

	_recoil *= RECOIL_DECAY
	if _recoil.length_squared() < 0.01:
		_recoil = Vector2.ZERO

	if _hurt_frames > 0:
		_hurt_frames -= 1
	if _wave_banner_frames > 0:
		_wave_banner_frames -= 1
	if _hitch_cooldown > 0:
		_hitch_cooldown -= 1


## Translate raw input into this tick's Command (the only path into the sim).
func _build_command() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	cmd.aim = _read_aim()
	cmd.fire = Input.is_action_pressed("fire")
	cmd.dodge = Input.is_action_just_pressed("dodge")
	cmd.place_mine = Input.is_action_just_pressed("mine")

	# On touch devices the browser emulates a mouse from touches, which
	# would fight the virtual stick — so touch replaces pointer input
	# entirely (gamepads still work).
	if _touch.enabled:
		if _touch.stick_active():
			cmd.move = _touch.stick_vector
		if _touch.aim_active():
			# Touch positions are screen-space; the camera means screen is
			# no longer world, so run the aim point through the canvas
			# transform before comparing to the player's world position.
			cmd.aim = _screen_to_world(_touch.aim_point) - _core.state.player_pos
			cmd.fire = true
		else:
			var stick := Vector2(
				Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
				Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y),
			)
			cmd.aim = stick.normalized() if stick.length() > STICK_AIM_DEADZONE \
				else Vector2.ZERO
			cmd.fire = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		if _touch.consume_dodge():
			cmd.dodge = true
	return cmd


func _screen_to_world(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * point


func _read_aim() -> Vector2:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y),
	)
	if stick.length() > STICK_AIM_DEADZONE:
		return stick.normalized()
	return get_global_mouse_position() - _core.state.player_pos
