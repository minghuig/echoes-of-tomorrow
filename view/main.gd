extends Node2D
## M4 view: owns a SimCore, translates raw input into one Command per physics
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

## A finished run, kept in memory as the data substrate for M3 ghost replay.
## No replay rendering yet — milestone discipline.
class RunRecord extends RefCounted:
	var seed_value: int = 0
	var command_log: Array[SimCommand] = []

## View flow: normal play, or the credits roll after the meta win.
enum Mode { PLAYING, CREDITS }

const BASE_SEED: int = 7
## Ticks to linger on the CLEAR banner before auto-starting the next run (~2s).
const CLEAR_RESET_DELAY_TICKS: int = 120
const STICK_AIM_DEADZONE: float = 0.35

## Credits scroll speed in pixels per physics tick (~66 px/s).
const CREDITS_SCROLL_PER_TICK: float = 1.1
const CREDITS_LINE_SPACING: float = 44.0
## Ignore the skip input for the first second so the R that ended the run
## can't also dismiss the credits.
const CREDITS_MIN_TICKS: int = 60
const CREDITS_TITLE_FONT_SIZE: int = 64
const CREDITS_FONT_SIZE: int = 24
const CREDITS_LINES: Array[String] = [
	"ECHOES OF TOMORROW",
	"",
	"TRAINING PROTOCOL COMPLETE",
	"",
	"BUILT BY",
	"TWO DEVS AND THEIR AGENTS",
	"",
	"EVERY RUN A SEED AND A COMMAND LOG",
	"NOTHING HERE IS EVER FORGOTTEN",
	"",
	"THANKS FOR PLAYING",
	"",
	"",
	"ASSET-7: NOMINAL. ARCHIVING.",
]

const COLOR_BG := Color("14161c")
const COLOR_BORDER := Color("3fd0d4")
const COLOR_PLAYER := Color("e8e6e3")
const COLOR_AIM := Color("3fd0d4")
const COLOR_PROJECTILE := Color("ffd75e")
const COLOR_BLOCK := Color("7a68c8")
const COLOR_CLEAR_TEXT := Color("aef2f4")
const COLOR_HUD_TEXT := Color("8fa3ad")
const COLOR_GHOST := Color(0.247, 0.816, 0.831, 0.35)
const COLOR_GHOST_PROJECTILE := Color(0.247, 0.816, 0.831, 0.22)
const COLOR_FLASH := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_POP := Color("b8a6ff")

# Feel-pass tuning (view frames, not sim ticks — hit-stop frames skip the
# view tick entirely, sim included, so logs stay aligned).
const HITSTOP_HIT_FRAMES: int = 2
const HITSTOP_DESTROY_FRAMES: int = 5
const SHAKE_HIT: float = 2.5
const SHAKE_DESTROY: float = 7.0
const SHAKE_CLEAR: float = 12.0
const SHAKE_DECAY: float = 0.85
const FLASH_FRAMES: int = 8
const POP_FRAMES: int = 14

var _core: SimCoreScript
var _meta: RunMetaScript
var _run_seed: int = 0
var _command_log: Array[SimCommand] = []
var _last_run: RunRecord = null
var _clear_ticks: int = 0
var _mode: Mode = Mode.PLAYING
var _credits_ticks: int = 0
var _win_fragment_target: int = 0

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
var _sfx_fire: AudioStreamPlayer
var _sfx_hit: AudioStreamPlayer
var _sfx_break: AudioStreamPlayer
var _sfx_clear: AudioStreamPlayer


func _ready() -> void:
	_meta = RunMetaScript.new()
	_meta.load_from_disk()
	_win_fragment_target = _load_win_target()
	_fx_rng.randomize()
	_sfx_fire = _make_sfx_player(SfxScript.fire_blip(), -14.0)
	_sfx_hit = _make_sfx_player(SfxScript.block_hit(), -10.0)
	_sfx_break = _make_sfx_player(SfxScript.block_break(), -6.0)
	_sfx_clear = _make_sfx_player(SfxScript.clear_chime(), -6.0)
	_start_run()


func _make_sfx_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


func _physics_process(_delta: float) -> void:
	if _mode == Mode.CREDITS:
		_credits_ticks += 1
		if _credits_ticks >= CREDITS_MIN_TICKS and Input.is_action_just_pressed("reset"):
			_mode = Mode.PLAYING
			_start_run()
		queue_redraw()
		return

	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		_decay_fx()
		queue_redraw()
		return

	if Input.is_action_just_pressed("reset"):
		_end_run()

	var pre_fire_cooldown := _core.state.fire_cooldown
	var pre_blocks := _snapshot_blocks()

	var cmd := _build_command()
	_command_log.append(cmd)
	_core.step(cmd)
	_step_ghost()

	_emit_feel_events(cmd.fire and pre_fire_cooldown == 0, pre_blocks)
	_decay_fx()

	if _core.state.blocks.is_empty():
		_clear_ticks += 1
		if _clear_ticks >= CLEAR_RESET_DELAY_TICKS:
			_end_run()

	queue_redraw()


## Tear down the current run — retain its (seed, command_log), bank its
## fragments into the persistent meta layer — then either roll credits (first
## time the lifetime fragment target is reached) or start a fresh run.
func _end_run() -> void:
	var record := RunRecord.new()
	record.seed_value = _run_seed
	record.command_log = _command_log
	_last_run = record
	_meta.total_fragments += _core.state.fragments
	if _meta.wins == 0 and _meta.total_fragments >= _win_fragment_target:
		_meta.wins += 1
		_meta.save_to_disk()
		_mode = Mode.CREDITS
		_credits_ticks = 0
		return
	_start_run()


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
	_clear_ticks = 0
	_hitstop_frames = 0
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	_flashes.clear()
	_pops.clear()
	_core = SimCoreScript.new()
	_core.setup(_run_seed)
	_spawn_ghost()


## Compare block state across one sim step to spot hits and kills. Keyed by
## position — blocks never move.
func _snapshot_blocks() -> Dictionary:
	var by_pos := {}
	for b: SimStateScript.Block in _core.state.blocks:
		by_pos[b.pos] = {"hp": b.hp, "size": b.size}
	return by_pos


## Turn this tick's sim delta into juice: hit-stop, shake, flashes, SFX.
func _emit_feel_events(fired: bool, pre_blocks: Dictionary) -> void:
	if fired:
		_sfx_fire.play()

	var now := {}
	for b: SimStateScript.Block in _core.state.blocks:
		now[b.pos] = b
	var destroyed := 0
	var damaged := 0
	for pos: Vector2 in pre_blocks:
		var prev: Dictionary = pre_blocks[pos]
		var rect := Rect2(pos, prev["size"])
		if not now.has(pos):
			destroyed += 1
			_pops.append({"rect": rect, "frames": POP_FRAMES})
		elif (now[pos] as SimStateScript.Block).hp < int(prev["hp"]):
			damaged += 1
			_flashes.append({"rect": rect, "frames": FLASH_FRAMES})

	if destroyed > 0:
		_hitstop_frames = maxi(_hitstop_frames, HITSTOP_DESTROY_FRAMES)
		_shake = maxf(_shake, SHAKE_DESTROY)
		_sfx_break.play()
	elif damaged > 0:
		_hitstop_frames = maxi(_hitstop_frames, HITSTOP_HIT_FRAMES)
		_shake = maxf(_shake, SHAKE_HIT)
		_sfx_hit.play()

	if destroyed > 0 and _core.state.blocks.is_empty():
		_shake = maxf(_shake, SHAKE_CLEAR)
		_sfx_clear.play()


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

	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i]["frames"] = int(_flashes[i]["frames"]) - 1
		if int(_flashes[i]["frames"]) <= 0:
			_flashes.remove_at(i)
	for i in range(_pops.size() - 1, -1, -1):
		_pops[i]["frames"] = int(_pops[i]["frames"]) - 1
		if int(_pops[i]["frames"]) <= 0:
			_pops.remove_at(i)


## Re-run the previous run verbatim as a translucent echo: a fresh SimCore
## seeded with the recorded seed, stepped one recorded command per live tick.
func _spawn_ghost() -> void:
	_ghost_core = null
	_ghost_log = []
	_ghost_tick = 0
	if _last_run == null or _last_run.command_log.is_empty():
		return
	_ghost_core = SimCoreScript.new()
	_ghost_core.setup(_last_run.seed_value)
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


## Translate raw input into this tick's Command (the only path into the sim).
func _build_command() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	cmd.aim = _read_aim()
	cmd.fire = Input.is_action_pressed("fire")
	cmd.dodge = Input.is_action_just_pressed("dodge")
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

	# Background stays put; everything in the world shakes on top of it.
	draw_rect(arena, COLOR_BG, true)
	draw_set_transform(_shake_offset)
	draw_rect(arena.grow(-2.0), COLOR_BORDER, false, 4.0)

	for b: SimStateScript.Block in state.blocks:
		var strength := float(b.hp) / 3.0
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK.lerp(COLOR_BG, 1.0 - strength))
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK, false, 2.0)

	_draw_fx()

	if _ghost_active():
		_draw_ghost()

	for p: SimStateScript.Projectile in state.projectiles:
		draw_circle(p.pos, _core.projectile_radius, COLOR_PROJECTILE)

	_draw_player(state)
	draw_set_transform(Vector2.ZERO)
	_draw_hud(state)

	if state.blocks.is_empty():
		_draw_clear_banner(state)


## Damage flashes (white fill fading out) and destruction pops (an outline
## expanding from the dead block's rect).
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
## translucent. Its world state (blocks) is deliberately not drawn — only
## the live run's arena is authoritative on screen.
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

	# Capsule: two circles bridged by a rect.
	draw_circle(pos + Vector2(0.0, -half_gap), r, COLOR_PLAYER)
	draw_circle(pos + Vector2(0.0, half_gap), r, COLOR_PLAYER)
	draw_rect(Rect2(pos - Vector2(r, half_gap), Vector2(r * 2.0, half_gap * 2.0)), COLOR_PLAYER)

	# Aim tick.
	var aim := state.player_aim
	draw_line(pos + aim * (r + 4.0), pos + aim * (r + 14.0), COLOR_AIM, 3.0)


func _draw_hud(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text := "RUN %d   FRAGMENTS %d   LIFETIME %d/%d" % [
		_meta.run_count, state.fragments,
		_meta.total_fragments + state.fragments, _win_fragment_target]
	draw_string(
		font, Vector2(16.0, 28.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		COLOR_HUD_TEXT)

	if _ghost_active():
		var echo := "ECHO ACTIVE"
		var width := font.get_string_size(echo, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(
			font, Vector2(state.arena_size.x - width - 16.0, 28.0), echo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(COLOR_GHOST, 0.9))


## Scroll the credits up from the bottom, stop with the block centered, then
## show the prompt to re-enter the loop.
func _draw_credits(arena: Rect2) -> void:
	draw_rect(arena, COLOR_BG, true)
	var font := ThemeDB.fallback_font

	var total_height := CREDITS_LINES.size() * CREDITS_LINE_SPACING
	var final_top := (arena.size.y - total_height) * 0.5
	var scroll_max := arena.size.y + CREDITS_LINE_SPACING - final_top
	var scroll := minf(_credits_ticks * CREDITS_SCROLL_PER_TICK, scroll_max)
	var y := arena.size.y + CREDITS_LINE_SPACING - scroll

	for i in CREDITS_LINES.size():
		var line := CREDITS_LINES[i]
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
		var prompt := "PRESS R TO RE-ENTER TRAINING"
		var prompt_width := font.get_string_size(
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE).x
		draw_string(
			font, Vector2((arena.size.x - prompt_width) * 0.5, arena.size.y - 48.0),
			prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, CREDITS_FONT_SIZE, COLOR_AIM)


func _draw_clear_banner(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text := "CLEAR"
	var font_size := 96
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := (state.arena_size - size) * 0.5 + Vector2(0.0, size.y * 0.8)
	draw_string(
		font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_CLEAR_TEXT)
