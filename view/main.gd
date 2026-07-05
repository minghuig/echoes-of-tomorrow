extends Node2D
## M5 view: owns a SimCore, translates raw input into one Command per physics
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

## A finished run, kept in memory as the data substrate for ghost replay.
class RunRecord extends RefCounted:
	var seed_value: int = 0
	var command_log: Array[SimCommand] = []

## View flow: normal play, or the credits roll after the meta win.
enum Mode { PLAYING, CREDITS }

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
var _command_log: Array[SimCommand] = []
var _last_run: RunRecord = null
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


func _ready() -> void:
	_meta = RunMetaScript.new()
	_meta.load_from_disk()
	_win_fragment_target = _load_win_target()
	_fx_rng.randomize()
	_sfx_fire = _make_sfx_player(SfxScript.fire_blip(), -16.0)
	_sfx_hit = _make_sfx_player(SfxScript.block_hit(), -10.0)
	_sfx_break = _make_sfx_player(SfxScript.block_break(), -6.0)
	_sfx_clear = _make_sfx_player(SfxScript.clear_chime(), -6.0)
	_sfx_enemy_hit = _make_sfx_player(SfxScript.enemy_hit(), -12.0)
	_sfx_enemy_die = _make_sfx_player(SfxScript.enemy_die(), -8.0)
	_sfx_hurt = _make_sfx_player(SfxScript.player_hurt(), -5.0)
	_sfx_wave = _make_sfx_player(SfxScript.wave_horn(), -8.0)
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

	# Down: the sim froze itself; hold on the death panel until redeploy.
	if _core.state.player_down:
		_decay_fx()
		if Input.is_action_just_pressed("reset"):
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
		_sfx_clear.play()
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
	_hitstop_frames = 0
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	_flashes.clear()
	_pops.clear()
	_hurt_frames = 0
	_wave_banner_frames = 0
	_core = SimCoreScript.new()
	_core.setup(_run_seed)
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

	if _wave_banner_frames > 0:
		_draw_wave_banner(state)
	if state.player_down:
		_draw_death_panel(state)


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
	_draw_centered(font, "[R]  REDEPLOY", 470.0, 26, COLOR_AIM)


func _draw_centered(
	font: Font, text: String, y: float, font_size: int, color: Color
) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font, Vector2((_core.state.arena_size.x - width) * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


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
