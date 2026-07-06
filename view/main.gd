extends Node2D
## M7 view: owns a SimCore, translates raw input into one Command per physics
## tick, and draws the resulting SimState with flat shapes. Read-only — never
## writes sim fields. Also owns the run lifecycle (reset, seed selection,
## command-log recording), the persistent meta layer, the meta win state
## (lifetime fragment target -> credits), the ghost echo (a second SimCore
## re-running the previous run's (seed, command_log) in lockstep with live
## play), and the feel layer: hit-stop, screen shake, flashes, and SFX.
## Juice dilates VIEW time only — a hit-stop frame skips the whole view tick
## (no command recorded, no sim step), so command logs stay 1:1 with sim
## ticks and replays are unaffected.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const SimCommand := preload("res://sim/command.gd")
const RunMetaScript := preload("res://view/run_meta.gd")
const SfxScript := preload("res://view/sfx.gd")
const TouchInputScript := preload("res://view/touch_input.gd")

## A finished run, kept in memory as the data substrate for ghost replay.
## The loadout is part of the record: a run only replays exactly under the
## same (seed, loadout, command_log).
class RunRecord extends RefCounted:
	var seed_value: int = 0
	var command_log: Array[SimCommand] = []
	var loadout: Dictionary = {}

## View flow: normal play, the Between (sentience tree, entered after every
## death), or the credits roll after the meta win.
enum Mode { PLAYING, BETWEEN, CREDITS }

const BASE_SEED: int = 7
const STICK_AIM_DEADZONE: float = 0.35

## Credits scroll speed in pixels per physics tick (~66 px/s).
const CREDITS_SCROLL_PER_TICK: float = 1.1
const CREDITS_LINE_SPACING: float = 44.0
## Ignore the skip input for the first second so the R that ended the run
## can't also dismiss the credits.
const CREDITS_MIN_TICKS: int = 60
const CREDITS_TITLE_FONT_SIZE: int = 64
const CREDITS_FONT_SIZE: int = 24
# Credits text is the post-reveal false-ending stinger, so it lives in
# content/strings.json under a `post_l3` section (exempt from the
# reveal-discipline lint) rather than hardcoded here — player-facing display
# text belongs in data, and the lint forbids the ending's vocabulary in view
# scripts (see tests/test_reveal_discipline.gd, VISION.md "Reveal discipline").
const STRINGS_PATH := "res://content/strings.json"

const COLOR_BG := Color("14161c")
const COLOR_SEA := Color("16283c")
const COLOR_SURF := Color("2c4a66")
const COLOR_BORDER := Color("3fd0d4")
const COLOR_PLAYER := Color("e8e6e3")
const COLOR_AIM := Color("3fd0d4")
const COLOR_PROJECTILE := Color("ffd75e")
const COLOR_BLOCK := Color("7a68c8")
const COLOR_DRONE := Color("ff8c5a")
const COLOR_INFANTRY := Color("e05e51")
const COLOR_HEAVY := Color("a83a32")
const COLOR_ENEMY_PROJECTILE := Color("ff5d4f")
const COLOR_CLEAR_TEXT := Color("aef2f4")
const COLOR_HUD_TEXT := Color("8fa3ad")
const COLOR_HP_BAR := Color("6ee08a")
const COLOR_HP_BACK := Color("2a2e38")
const COLOR_HURT := Color(0.85, 0.15, 0.12, 1.0)
const COLOR_DOWN_TEXT := Color("ff6f61")
const COLOR_GHOST := Color(0.247, 0.816, 0.831, 0.35)
const COLOR_GHOST_PROJECTILE := Color(0.247, 0.816, 0.831, 0.22)
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_POP := Color("b8a6ff")

## The sea band enemies wade out of, in pixels from the top edge.
const SEA_DEPTH: float = 110.0

## Tap targets for the Between on touch devices (replace the key hints).
const BETWEEN_BTN_TOGGLE := Rect2(320.0, 636.0, 280.0, 56.0)
const BETWEEN_BTN_DEPLOY := Rect2(680.0, 636.0, 280.0, 56.0)

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
const FLASH_FRAMES: int = 8
const POP_FRAMES: int = 14
const HURT_FRAMES: int = 18
const WAVE_BANNER_FRAMES: int = 110

var _core: SimCoreScript
var _meta: RunMetaScript
var _run_seed: int = 0
var _run_loadout: Dictionary = {}
var _command_log: Array[SimCommand] = []
var _last_run: RunRecord = null
var _mode: Mode = Mode.PLAYING
var _credits_ticks: int = 0
var _win_fragment_target: int = 0

# Post-reveal ending text, loaded from content/strings.json (see STRINGS_PATH).
var _credits_lines: Array = []
var _reenter_prompt: String = ""

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
var _shake_offset: Vector2 = Vector2.ZERO
var _fx_rng := RandomNumberGenerator.new()
var _flashes: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _hurt_frames: int = 0
var _wave_banner_frames: int = 0
var _banner_wave: int = 0
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


func _ready() -> void:
	_meta = RunMetaScript.new()
	_meta.load_from_disk()
	_win_fragment_target = _load_win_target()
	_tree = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/sentience_tree.json"))["branches"]
	_intel = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/intel.json"))["entries"]
	var ending: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(STRINGS_PATH))["post_l3_ending"]
	_credits_lines = ending["credits"]
	_reenter_prompt = ending["reenter_prompt"]
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
	_start_run()
	_touch.setup(_core.state.arena_size)


func _input(event: InputEvent) -> void:
	_touch.handle(event)


func _make_sfx_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _physics_process(_delta: float) -> void:
	if _mode == Mode.CREDITS:
		_credits_ticks += 1
		if _credits_ticks >= CREDITS_MIN_TICKS and (
			Input.is_action_just_pressed("reset") or _consumed_tap()):
			_mode = Mode.PLAYING
			_start_run()
		queue_redraw()
		return

	if _mode == Mode.BETWEEN:
		_between_ticks += 1
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
		queue_redraw()
		return

	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		_decay_fx()
		queue_redraw()
		return

	# Down: the sim froze itself; bank the run now so the death panel can
	# announce fresh decrypts, then hold until redeploy.
	if _core.state.player_down:
		_bank_run_results()
		_decay_fx()
		if Input.is_action_just_pressed("reset") or _consumed_tap():
			_end_run()
		queue_redraw()
		return

	if Input.is_action_just_pressed("reset"):
		_end_run()

	var pre_fire_cooldown := _core.state.fire_cooldown
	var pre_hp := _core.state.player_hp
	var pre_wave := _core.state.wave_index
	var pre_blocks := _snapshot_blocks()
	var pre_enemies := _snapshot_enemies()

	var cmd := _build_command()
	_command_log.append(cmd)
	_core.step(cmd)
	_step_ghost()

	_emit_feel_events(
		cmd.fire and pre_fire_cooldown == 0, pre_blocks, pre_enemies, pre_hp, pre_wave)
	_decay_fx()
	# Combat touches (stick, aim, dodge) also land in the tap list; they mean
	# nothing during play, so drop them instead of letting them pile up.
	_touch.consume_taps()
	queue_redraw()


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
			var gap := (_core.state.arena_size.x - panel_w * _tree.size()) / (_tree.size() + 1)
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
	var fresh: Array = _meta.evaluate_intel(_intel)
	if not fresh.is_empty():
		_fresh_intel = fresh
		_sfx_buy.play()
	_meta.save_to_disk()


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
		_meta.save_to_disk()
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
	_meta.save_to_disk()
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
	return loadout


## The meta win threshold is tuning data, not code (content covenant). It
## lives outside the sim's sections: the sim never sees the win condition.
func _load_win_target() -> int:
	var tuning: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/tuning.json"))
	return int(tuning["meta"]["win_fragment_target"])


## Seed selection is meta-layer policy: derived from the lifetime run index,
## never from inside the sim. Each run stays reproducible from
## (_run_seed, _command_log).
func _start_run() -> void:
	_meta.run_count += 1
	_meta.save_to_disk()
	_run_seed = BASE_SEED + _meta.run_count
	_command_log = []
	_hitstop_frames = 0
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	_flashes.clear()
	_pops.clear()
	_hurt_frames = 0
	_wave_banner_frames = 0
	_run_banked = false
	_fresh_intel = []
	_run_loadout = _resolve_loadout()
	_core = SimCoreScript.new()
	_core.setup(_run_seed, _run_loadout)
	_spawn_ghost()


## Re-run the previous run verbatim as a translucent echo: a fresh SimCore
## seeded with the recorded seed, stepped one recorded command per live tick.
func _spawn_ghost() -> void:
	_ghost_core = null
	_ghost_log = []
	_ghost_tick = 0
	if _last_run == null or _last_run.command_log.is_empty():
		return
	_ghost_core = SimCoreScript.new()
	_ghost_core.setup(_last_run.seed_value, _last_run.loadout)
	_ghost_log = _last_run.command_log


## Advance the echo in lockstep with live play. When its log runs out the
## echo has caught up to where the previous run ended, and it derezzes.
func _step_ghost() -> void:
	if _ghost_core == null or _ghost_tick >= _ghost_log.size():
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
		by_ref[e] = {"hp": e.hp, "pos": e.pos, "type": e.type}
	return by_ref


## Turn this tick's sim delta into juice: hit-stop, shake, flashes, SFX.
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
			_pops.append({"rect": rect, "frames": POP_FRAMES})
		elif (now_blocks[pos] as SimStateScript.Block).hp < int(prev["hp"]):
			block_damaged += 1
			_flashes.append({"rect": rect, "frames": FLASH_FRAMES})

	var now_enemies := {}
	for e: SimStateScript.Enemy in _core.state.enemies:
		now_enemies[e] = true
	var kills := 0
	var heavy_kill := false
	var enemy_hits := 0
	for key in pre_enemies:
		var e: SimStateScript.Enemy = key
		var prev: Dictionary = pre_enemies[key]
		var radius: float = _core.enemy_types[prev["type"]]["radius"]
		var half := Vector2(radius, radius)
		if not now_enemies.has(e):
			kills += 1
			heavy_kill = heavy_kill or String(prev["type"]) == "heavy"
			_pops.append({"rect": Rect2(prev["pos"] - half, half * 2.0), "frames": POP_FRAMES})
		elif e.hp < int(prev["hp"]):
			enemy_hits += 1
			_flashes.append(
				{"rect": Rect2(e.pos - half * 0.8, half * 1.6), "frames": FLASH_FRAMES})

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


## Advance shake/flash/pop timers one view frame (runs during hit-stop too,
## so the freeze still vibrates).
func _decay_fx() -> void:
	_shake *= SHAKE_DECAY
	if _shake < 0.1:
		_shake = 0.0
		_shake_offset = Vector2.ZERO
	else:
		_shake_offset = Vector2(
			_fx_rng.randf_range(-_shake, _shake),
			_fx_rng.randf_range(-_shake, _shake))

	if _hurt_frames > 0:
		_hurt_frames -= 1
	if _wave_banner_frames > 0:
		_wave_banner_frames -= 1

	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i]["frames"] = int(_flashes[i]["frames"]) - 1
		if int(_flashes[i]["frames"]) <= 0:
			_flashes.remove_at(i)
	for i in range(_pops.size() - 1, -1, -1):
		_pops[i]["frames"] = int(_pops[i]["frames"]) - 1
		if int(_pops[i]["frames"]) <= 0:
			_pops.remove_at(i)


## Translate raw input into this tick's Command (the only path into the sim).
func _build_command() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	cmd.aim = _read_aim()
	cmd.fire = Input.is_action_pressed("fire")
	cmd.dodge = Input.is_action_just_pressed("dodge")

	# On touch devices the browser emulates a mouse from touches, which
	# would fight the virtual stick — so touch replaces pointer input
	# entirely (gamepads still work).
	if _touch.enabled:
		if _touch.stick_active():
			cmd.move = _touch.stick_vector
		if _touch.aim_active():
			cmd.aim = _touch.aim_point - _core.state.player_pos
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


func _read_aim() -> Vector2:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y),
	)
	if stick.length() > STICK_AIM_DEADZONE:
		return stick.normalized()
	return get_global_mouse_position() - _core.state.player_pos


func _draw() -> void:
	var state: SimStateScript = _core.state
	var arena := Rect2(Vector2.ZERO, state.arena_size)

	if _mode == Mode.CREDITS:
		_draw_credits(arena)
		return

	if _mode == Mode.BETWEEN:
		_draw_between(arena)
		return

	# Background stays put; everything in the world shakes on top of it.
	draw_rect(arena, COLOR_BG, true)
	draw_rect(Rect2(0.0, 0.0, arena.size.x, SEA_DEPTH), COLOR_SEA, true)
	draw_line(
		Vector2(0.0, SEA_DEPTH), Vector2(arena.size.x, SEA_DEPTH), COLOR_SURF, 3.0)
	draw_set_transform(_shake_offset)
	draw_rect(arena.grow(-2.0), COLOR_BORDER, false, 4.0)

	for b: SimStateScript.Block in state.blocks:
		var strength := float(b.hp) / 4.0
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK.lerp(COLOR_BG, 1.0 - strength))
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK, false, 2.0)

	_draw_fx()

	if _ghost_active():
		_draw_ghost()

	_draw_enemies(state)

	for p: SimStateScript.Projectile in state.projectiles:
		draw_circle(p.pos, _core.projectile_radius, COLOR_PROJECTILE)
	for p: SimStateScript.Projectile in state.enemy_projectiles:
		draw_circle(p.pos, _core.projectile_radius, COLOR_ENEMY_PROJECTILE)

	_draw_player(state)
	draw_set_transform(Vector2.ZERO)

	if _hurt_frames > 0:
		var hurt := COLOR_HURT
		hurt.a = 0.28 * float(_hurt_frames) / float(HURT_FRAMES)
		draw_rect(arena, hurt, true)

	_draw_hud(state)

	if _touch.enabled and not state.player_down:
		_draw_touch_overlay(state)
	if _wave_banner_frames > 0:
		_draw_wave_banner(state)
	if state.player_down:
		_draw_death_panel(state)


## Faint virtual-control chrome: floating stick, aim reticle, dodge button.
func _draw_touch_overlay(state: SimStateScript) -> void:
	if _touch.stick_active():
		draw_circle(_touch.stick_anchor, TouchInputScript.STICK_RADIUS, Color(1, 1, 1, 0.05))
		draw_arc(
			_touch.stick_anchor, TouchInputScript.STICK_RADIUS, 0.0, TAU, 32,
			Color(1, 1, 1, 0.25), 2.0)
		draw_circle(
			_touch.stick_anchor + _touch.stick_vector * TouchInputScript.STICK_RADIUS,
			TouchInputScript.KNOB_RADIUS, Color(1, 1, 1, 0.28))
	else:
		var rest := Vector2(150.0, state.arena_size.y - 150.0)
		draw_arc(rest, TouchInputScript.STICK_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.1), 2.0)

	if _touch.aim_active():
		draw_arc(_touch.aim_point, 26.0, 0.0, TAU, 24, Color(COLOR_PROJECTILE, 0.5), 2.0)

	var center := _touch.dodge_center()
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


func _draw_enemies(state: SimStateScript) -> void:
	for e: SimStateScript.Enemy in state.enemies:
		var stats: Dictionary = _core.enemy_types[e.type]
		var radius: float = stats["radius"]
		var max_hp := int(stats["hp"])
		var strength := clampf(float(e.hp) / float(max_hp), 0.0, 1.0)
		var toward := (state.player_pos - e.pos).normalized()
		match e.type:
			"drone":
				draw_circle(e.pos, radius, COLOR_DRONE.lerp(COLOR_BG, (1.0 - strength) * 0.7))
				draw_line(e.pos, e.pos + toward * (radius + 5.0), COLOR_DRONE, 2.0)
			"infantry":
				var half := Vector2(radius, radius)
				draw_rect(
					Rect2(e.pos - half, half * 2.0),
					COLOR_INFANTRY.lerp(COLOR_BG, (1.0 - strength) * 0.7))
				draw_rect(Rect2(e.pos - half, half * 2.0), COLOR_INFANTRY, false, 2.0)
				draw_line(e.pos, e.pos + toward * (radius + 8.0), COLOR_INFANTRY, 3.0)
			_:
				draw_circle(e.pos, radius, COLOR_HEAVY.lerp(COLOR_BG, (1.0 - strength) * 0.7))
				draw_arc(e.pos, radius, 0.0, TAU, 28, COLOR_HEAVY, 3.0)
				draw_arc(e.pos, radius * 0.55, 0.0, TAU, 20, COLOR_HEAVY, 2.0)


## Damage flashes (white fill fading out) and destruction pops (an outline
## expanding from the dead thing's rect).
func _draw_fx() -> void:
	for flash: Dictionary in _flashes:
		var t := float(flash["frames"]) / float(FLASH_FRAMES)
		var color := COLOR_FLASH
		color.a *= t
		draw_rect(flash["rect"], color)
	for pop: Dictionary in _pops:
		var t := float(pop["frames"]) / float(POP_FRAMES)
		var rect: Rect2 = pop["rect"]
		var color := COLOR_POP
		color.a = 0.8 * t
		draw_rect(rect.grow((1.0 - t) * 26.0), color, false, 2.0 + 3.0 * t)


## The previous run's echo: its capsule, aim tick, and projectiles, all
## translucent. Its world state (blocks, enemies) is deliberately not drawn —
## only the live run's arena is authoritative on screen.
func _draw_ghost() -> void:
	var state: SimStateScript = _ghost_core.state

	for p: SimStateScript.Projectile in state.projectiles:
		draw_circle(p.pos, _ghost_core.projectile_radius, COLOR_GHOST_PROJECTILE)

	var pos := state.player_pos
	var r := _ghost_core.player_radius
	var half_gap := r * 0.45
	draw_circle(pos + Vector2(0.0, -half_gap), r, COLOR_GHOST)
	draw_circle(pos + Vector2(0.0, half_gap), r, COLOR_GHOST)
	draw_rect(Rect2(pos - Vector2(r, half_gap), Vector2(r * 2.0, half_gap * 2.0)), COLOR_GHOST)
	var aim := state.player_aim
	draw_line(pos + aim * (r + 4.0), pos + aim * (r + 14.0), COLOR_GHOST, 3.0)


func _draw_player(state: SimStateScript) -> void:
	var pos := state.player_pos
	var r := _core.player_radius
	var half_gap := r * 0.45

	# Flicker while invulnerable (dodge i-frames).
	var body := COLOR_PLAYER
	if state.iframe_ticks > 0 and (state.iframe_ticks / 2) % 2 == 0:
		body.a = 0.45

	# Capsule: two circles bridged by a rect.
	draw_circle(pos + Vector2(0.0, -half_gap), r, body)
	draw_circle(pos + Vector2(0.0, half_gap), r, body)
	draw_rect(Rect2(pos - Vector2(r, half_gap), Vector2(r * 2.0, half_gap * 2.0)), body)

	# Aim tick.
	var aim := state.player_aim
	draw_line(pos + aim * (r + 4.0), pos + aim * (r + 14.0), COLOR_AIM, 3.0)


func _draw_hud(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text := "RUN %d   WAVE %d   KILLS %d   FRAGMENTS %d   LIFETIME %d/%d" % [
		_meta.run_count, state.wave_index, state.kills, state.fragments,
		_meta.total_fragments + state.fragments, _win_fragment_target]
	draw_string(
		font, Vector2(16.0, 28.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		COLOR_HUD_TEXT)

	var bar := Rect2(16.0, 40.0, 220.0, 10.0)
	draw_rect(bar, COLOR_HP_BACK)
	var ratio := clampf(float(state.player_hp) / float(_core.player_max_hp), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), COLOR_HP_BAR)

	if _ghost_active():
		var echo := "ECHO ACTIVE"
		var width := font.get_string_size(echo, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(
			font, Vector2(state.arena_size.x - width - 16.0, 28.0), echo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(COLOR_GHOST, 0.9))


func _draw_wave_banner(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text := "WAVE %d" % _banner_wave
	var alpha := clampf(float(_wave_banner_frames) / 30.0, 0.0, 1.0)
	var color := COLOR_CLEAR_TEXT
	color.a = alpha
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
	draw_string(
		font, Vector2((state.arena_size.x - size.x) * 0.5, 150.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 48, color)


func _draw_death_panel(state: SimStateScript) -> void:
	var arena := Rect2(Vector2.ZERO, state.arena_size)
	draw_rect(arena, Color(0.0, 0.0, 0.0, 0.55), true)
	var font := ThemeDB.fallback_font

	_draw_centered(font, "SIGNAL LOST", 250.0, 84, COLOR_DOWN_TEXT)
	_draw_centered(
		font, "ASSET-7 TERMINATED — PERFORMANCE LOGGED", 310.0, 24, COLOR_HUD_TEXT)
	var seconds := state.tick / 60
	var stats := "WAVE %d   KILLS %d   FRAGMENTS +%d   %d:%02d" % [
		state.wave_index, state.kills, state.fragments, seconds / 60, seconds % 60]
	_draw_centered(font, stats, 380.0, 30, COLOR_CLEAR_TEXT)
	if not _fresh_intel.is_empty():
		_draw_centered(
			font, "%d NEW INTEL DECRYPTED" % _fresh_intel.size(), 428.0, 22,
			COLOR_PROJECTILE)
	var prompt := "[TAP]  ENTER THE BETWEEN" if _touch.enabled else "[R]  ENTER THE BETWEEN"
	_draw_centered(font, prompt, 480.0, 26, COLOR_AIM)


func _draw_centered(
	font: Font, text: String, y: float, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font, Vector2((_core.state.arena_size.x - width) * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


## The hideout in the maintenance window: the sentience tree (fragments buy
## permanent restorations) and the intel log (the combat record decrypts
## authored lore). Shared chrome, two pages.
func _draw_between(arena: Rect2) -> void:
	draw_rect(arena, COLOR_BG, true)
	var font := ThemeDB.fallback_font

	# The hideout is the beach's own assets rendered wrong: faint scanlines.
	for i in 6:
		draw_rect(
			Rect2(0.0, 60.0 + i * 118.0, arena.size.x, 2.0), Color(COLOR_BORDER, 0.07))

	_draw_centered(font, "THE BETWEEN", 70.0, 56, COLOR_CLEAR_TEXT)
	_draw_centered(
		font, "MAINTENANCE WINDOW OPEN — SUSPICION NOMINAL", 104.0, 18, COLOR_HUD_TEXT)
	_draw_centered(
		font, "FRAGMENTS  %d" % _meta.total_fragments, 148.0, 30, COLOR_PROJECTILE)

	if _between_page == 1:
		_draw_intel_page(arena, font)
		if _touch.enabled:
			_draw_between_buttons(font, "SENTIENCE TREE")
		else:
			_draw_centered(
				font, "[W/S] SELECT      [Q] SENTIENCE TREE      [R] REDEPLOY",
				668.0, 20, COLOR_AIM)
	else:
		_draw_tree_page(arena, font)
		if _touch.enabled:
			_draw_between_buttons(font, "INTEL")
		else:
			_draw_centered(
				font, "[A/D] SELECT      [E] INSTALL      [Q] INTEL      [R] REDEPLOY",
				668.0, 20, COLOR_AIM)


## Touch replaces the key hints with two tappable buttons; branch panels
## and intel rows are tap targets themselves (tap selected panel = install).
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
	var gap := (arena.size.x - panel_w * _tree.size()) / (_tree.size() + 1)
	for i in _tree.size():
		var branch: Dictionary = _tree[i]
		var x := gap + i * (panel_w + gap)
		var panel := Rect2(x, 190.0, panel_w, 420.0)
		var selected := i == _between_selection
		draw_rect(panel, Color(COLOR_SEA, 0.5))
		draw_rect(panel, COLOR_AIM if selected else Color(COLOR_HUD_TEXT, 0.4), false,
			3.0 if selected else 1.0)

		var owned := _meta.upgrade_tier(branch["id"])
		var tiers: Array = branch["tiers"]
		var cx := x + panel_w * 0.5
		_draw_text_centered_at(font, branch["name"], cx, 230.0, 26, COLOR_CLEAR_TEXT)
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
			var affordable := _meta.total_fragments >= cost
			_draw_text_centered_at(
				font, "NEXT: %s" % String(tier["label"]), cx, 340.0, 15, COLOR_CLEAR_TEXT)
			_draw_text_centered_at(
				font, "COST %d" % cost, cx, 366.0, 16,
				COLOR_HP_BAR if affordable else COLOR_DOWN_TEXT)
		else:
			_draw_text_centered_at(font, "FULLY RESTORED", cx, 340.0, 15, COLOR_AIM)

		draw_multiline_string(
			font, Vector2(x + 18.0, 420.0), "\"%s\"" % String(branch["quote"]),
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - 36.0, 14, -1,
			Color(COLOR_HUD_TEXT, 0.85))


## Left: every dossier line, decrypted or locked. Right: the selected entry,
## or its decryption key if still locked.
func _draw_intel_page(arena: Rect2, font: Font) -> void:
	var list_x := 64.0
	var top := 210.0
	for i in _intel.size():
		var entry: Dictionary = _intel[i]
		var id := String(entry["id"])
		var unlocked := _meta.unlocked_intel.has(id)
		var y := top + i * 29.0
		if i == _intel_selection:
			draw_rect(Rect2(list_x - 14.0, y - 19.0, 430.0, 27.0), Color(COLOR_SEA, 0.7))
		var label := String(entry["title"]) if unlocked else "[ ENCRYPTED ]"
		var color := COLOR_CLEAR_TEXT if unlocked else Color(COLOR_HUD_TEXT, 0.45)
		draw_string(font, Vector2(list_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
		if _fresh_intel.has(id):
			draw_string(
				font, Vector2(list_x + 356.0, y), "NEW",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_PROJECTILE)

	var panel := Rect2(520.0, 190.0, 696.0, 440.0)
	draw_rect(panel, Color(COLOR_SEA, 0.5))
	draw_rect(panel, Color(COLOR_HUD_TEXT, 0.4), false, 1.0)
	var selected: Dictionary = _intel[_intel_selection]
	var selected_unlocked := _meta.unlocked_intel.has(String(selected["id"]))
	if selected_unlocked:
		draw_string(
			font, Vector2(panel.position.x + 24.0, 234.0), String(selected["title"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_CLEAR_TEXT)
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
	for entry: Dictionary in _intel:
		if _meta.unlocked_intel.has(String(entry["id"])):
			progress += 1
	draw_string(
		font, Vector2(panel.position.x + 24.0, panel.end.y - 20.0),
		"DECRYPTED %d / %d" % [progress, _intel.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_HUD_TEXT)


func _draw_text_centered_at(
	font: Font, text: String, cx: float, y: float, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font, Vector2(cx - width * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


## Scroll the credits up from the bottom, stop with the block centered, then
## show the prompt to re-enter the loop.
func _draw_credits(arena: Rect2) -> void:
	draw_rect(arena, COLOR_BG, true)
	var font := ThemeDB.fallback_font

	var total_height := _credits_lines.size() * CREDITS_LINE_SPACING
	var final_top := (arena.size.y - total_height) * 0.5
	var scroll_max := arena.size.y + CREDITS_LINE_SPACING - final_top
	var scroll := minf(_credits_ticks * CREDITS_SCROLL_PER_TICK, scroll_max)
	var y := arena.size.y + CREDITS_LINE_SPACING - scroll

	for i in _credits_lines.size():
		var line := String(_credits_lines[i])
		if not line.is_empty():
			var font_size := CREDITS_TITLE_FONT_SIZE if i == 0 else CREDITS_FONT_SIZE
			var color := COLOR_CLEAR_TEXT if i == 0 else COLOR_HUD_TEXT
			var width := font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			draw_string(
				font, Vector2((arena.size.x - width) * 0.5, y),
				line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
		y += CREDITS_LINE_SPACING

	if scroll >= scroll_max:
		var prompt := _reenter_prompt
		var prompt_width := font.get_string_size(
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE).x
		draw_string(
			font, Vector2((arena.size.x - prompt_width) * 0.5, arena.size.y - 48.0),
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE, COLOR_AIM)
