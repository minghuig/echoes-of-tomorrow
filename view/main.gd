extends Node2D
## M1 view: owns a SimCore, translates raw input into one Command per physics
## tick, and draws the resulting SimState with flat shapes. Read-only — never
## writes sim fields. Also owns the run lifecycle (reset, seed selection,
## command-log recording) and the persistent meta layer — all outside the sim.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const SimCommand := preload("res://sim/command.gd")
const RunMetaScript := preload("res://view/run_meta.gd")

## A finished run, kept in memory as the data substrate for M3 ghost replay.
## No replay rendering yet — milestone discipline.
class RunRecord extends RefCounted:
	var seed_value: int = 0
	var command_log: Array[SimCommand] = []

const BASE_SEED: int = 7
## Ticks to linger on the CLEAR banner before auto-starting the next run (~2s).
const CLEAR_RESET_DELAY_TICKS: int = 120
const STICK_AIM_DEADZONE: float = 0.35

const COLOR_BG := Color("14161c")
const COLOR_BORDER := Color("3fd0d4")
const COLOR_PLAYER := Color("e8e6e3")
const COLOR_AIM := Color("3fd0d4")
const COLOR_PROJECTILE := Color("ffd75e")
const COLOR_BLOCK := Color("7a68c8")
const COLOR_CLEAR_TEXT := Color("aef2f4")
const COLOR_HUD_TEXT := Color("8fa3ad")

var _core: SimCoreScript
var _meta: RunMetaScript
var _run_seed: int = 0
var _command_log: Array[SimCommand] = []
var _last_run: RunRecord = null
var _clear_ticks: int = 0


func _ready() -> void:
	_meta = RunMetaScript.new()
	_meta.load_from_disk()
	_start_run()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		_end_run()

	var cmd := _build_command()
	_command_log.append(cmd)
	_core.step(cmd)

	if _core.state.blocks.is_empty():
		_clear_ticks += 1
		if _clear_ticks >= CLEAR_RESET_DELAY_TICKS:
			_end_run()

	queue_redraw()


## Tear down the current run — retain its (seed, command_log), bank its
## fragments into the persistent meta layer — and start a fresh one.
func _end_run() -> void:
	var record := RunRecord.new()
	record.seed_value = _run_seed
	record.command_log = _command_log
	_last_run = record
	_meta.total_fragments += _core.state.fragments
	_start_run()


## Seed selection is meta-layer policy: derived from the lifetime run index,
## never from inside the sim. Each run stays reproducible from
## (_run_seed, _command_log).
func _start_run() -> void:
	_meta.run_count += 1
	_meta.save_to_disk()
	_run_seed = BASE_SEED + _meta.run_count
	_command_log = []
	_clear_ticks = 0
	_core = SimCoreScript.new()
	_core.setup(_run_seed)


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

	draw_rect(arena, COLOR_BG, true)
	draw_rect(arena.grow(-2.0), COLOR_BORDER, false, 4.0)

	for b: SimStateScript.Block in state.blocks:
		var strength := float(b.hp) / 3.0
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK.lerp(COLOR_BG, 1.0 - strength))
		draw_rect(Rect2(b.pos, b.size), COLOR_BLOCK, false, 2.0)

	for p: SimStateScript.Projectile in state.projectiles:
		draw_circle(p.pos, _core.projectile_radius, COLOR_PROJECTILE)

	_draw_player(state)
	_draw_hud(state)

	if state.blocks.is_empty():
		_draw_clear_banner(state)


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
	var text := "RUN %d   FRAGMENTS %d   LIFETIME %d" % [
		_meta.run_count, state.fragments, _meta.total_fragments + state.fragments]
	draw_string(
		font, Vector2(16.0, 28.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		COLOR_HUD_TEXT)


func _draw_clear_banner(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text := "CLEAR"
	var font_size := 96
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := (state.arena_size - size) * 0.5 + Vector2(0.0, size.y * 0.8)
	draw_string(
		font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_CLEAR_TEXT)
