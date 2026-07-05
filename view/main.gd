extends Node2D
## M0 view: owns a SimCore, translates raw input into one Command per physics
## tick, and draws the resulting SimState with flat shapes. Read-only — never
## writes sim fields.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const SimCommand := preload("res://sim/command.gd")

const RUN_SEED: int = 7
const STICK_AIM_DEADZONE: float = 0.35

const STRINGS_PATH := "res://content/strings.json"

const COLOR_BG := Color("14161c")
const COLOR_BORDER := Color("3fd0d4")
const COLOR_PLAYER := Color("e8e6e3")
const COLOR_AIM := Color("3fd0d4")
const COLOR_PROJECTILE := Color("ffd75e")
const COLOR_BLOCK := Color("7a68c8")
const COLOR_CLEAR_TEXT := Color("aef2f4")

var _core: SimCoreScript
var _ui_strings: Dictionary


func _ready() -> void:
	_core = SimCoreScript.new()
	_core.setup(RUN_SEED)
	# Player-facing text lives in content/strings.json so the reveal-discipline
	# lint (tests/test_reveal_discipline.gd) can enforce VISION.md's vocabulary
	# rules — never hardcode display strings in scripts.
	var strings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(STRINGS_PATH))
	_ui_strings = strings["ui"]


func _physics_process(_delta: float) -> void:
	_core.step(_build_command())
	queue_redraw()


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


func _draw_clear_banner(state: SimStateScript) -> void:
	var font := ThemeDB.fallback_font
	var text: String = _ui_strings["clear_banner"]
	var font_size := 96
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := (state.arena_size - size) * 0.5 + Vector2(0.0, size.y * 0.8)
	draw_string(
		font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_CLEAR_TEXT)
