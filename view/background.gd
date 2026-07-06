extends Node2D
## Arena backdrop: gradient wash, holographic grid, a faint "sea" band the
## assault wades out of, perimeter frame with corner brackets, calibration
## ticks, and slow-drifting data motes. Pure ambience — knows nothing about
## the sim except the arena size and sea depth handed over at startup.

const COLOR_BG := Color("0b0d13")
const COLOR_GLOW_CENTER := Color("181d2c")
const COLOR_GRID := Color("3fd0d4")
const COLOR_FRAME := Color("3fd0d4")
const COLOR_MOTE_A := Color("3fd0d4")
const COLOR_MOTE_B := Color("8f7bea")
const COLOR_SEA := Color("16283c")
const COLOR_SURF := Color("3fd0d4")

const GRID_MINOR: float = 40.0
const MAJOR_EVERY: int = 4
const MOTE_COUNT: int = 26
const BRACKET_INSET: float = 10.0
const BRACKET_LEN: float = 30.0


class Mote extends RefCounted:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius: float = 1.5
	var color := Color.WHITE


var arena_size := Vector2(1280.0, 720.0)
## The sea band enemies wade out of, in pixels from the top edge (0 = none).
var sea_depth: float = 0.0

var _motes: Array[Mote] = []
var _center_tex: GradientTexture2D
var _sea_tex: GradientTexture2D
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([COLOR_GLOW_CENTER, Color(COLOR_GLOW_CENTER, 0.0)])
	_center_tex = GradientTexture2D.new()
	_center_tex.gradient = gradient
	_center_tex.fill = GradientTexture2D.FILL_RADIAL
	_center_tex.fill_from = Vector2(0.5, 0.5)
	_center_tex.fill_to = Vector2(1.0, 0.5)
	_center_tex.width = 256
	_center_tex.height = 256

	# Sea band: a downward fade so the top edge reads as depth.
	var sea := Gradient.new()
	sea.offsets = PackedFloat32Array([0.0, 1.0])
	sea.colors = PackedColorArray([Color(COLOR_SEA, 0.55), Color(COLOR_SEA, 0.0)])
	_sea_tex = GradientTexture2D.new()
	_sea_tex.gradient = sea
	_sea_tex.fill_from = Vector2(0.0, 0.0)
	_sea_tex.fill_to = Vector2(0.0, 1.0)
	_sea_tex.width = 8
	_sea_tex.height = 64

	for i in MOTE_COUNT:
		var m := Mote.new()
		m.pos = Vector2(
			_rng.randf_range(0.0, arena_size.x), _rng.randf_range(0.0, arena_size.y))
		m.vel = Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-16.0, -4.0))
		m.radius = _rng.randf_range(1.0, 2.4)
		var col := COLOR_MOTE_A if _rng.randf() < 0.6 else COLOR_MOTE_B
		m.color = Color(col, _rng.randf_range(0.04, 0.12))
		_motes.append(m)


func _process(delta: float) -> void:
	_time += delta
	for m: Mote in _motes:
		m.pos += m.vel * delta
		if m.pos.x < -4.0:
			m.pos.x += arena_size.x + 8.0
		elif m.pos.x > arena_size.x + 4.0:
			m.pos.x -= arena_size.x + 8.0
		if m.pos.y < -4.0:
			m.pos.y += arena_size.y + 8.0
		elif m.pos.y > arena_size.y + 4.0:
			m.pos.y -= arena_size.y + 8.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, arena_size), COLOR_BG)

	var glow_half := Vector2(720.0, 720.0)
	draw_texture_rect(
		_center_tex, Rect2(arena_size * 0.5 - glow_half, glow_half * 2.0), false)

	if sea_depth > 0.0:
		_draw_sea()

	_draw_grid()

	for m: Mote in _motes:
		draw_circle(m.pos, m.radius, m.color)

	_draw_frame()


func _draw_sea() -> void:
	draw_texture_rect(_sea_tex, Rect2(0.0, 0.0, arena_size.x, sea_depth), false)
	# Surf line ripples gently so the water reads as alive.
	var wobble := 1.5 * sin(_time * 1.4)
	draw_line(
		Vector2(0.0, sea_depth + wobble), Vector2(arena_size.x, sea_depth + wobble),
		Color(COLOR_SURF, 0.35), 2.0)


func _draw_grid() -> void:
	var pulse := 0.85 + 0.15 * sin(_time * 0.9)
	var xi := 1
	while xi * GRID_MINOR < arena_size.x:
		var x := xi * GRID_MINOR
		var alpha := (0.10 if xi % MAJOR_EVERY == 0 else 0.045) * pulse
		draw_line(Vector2(x, 0.0), Vector2(x, arena_size.y), Color(COLOR_GRID, alpha), 1.0)
		xi += 1
	var yi := 1
	while yi * GRID_MINOR < arena_size.y:
		var y := yi * GRID_MINOR
		var alpha := (0.10 if yi % MAJOR_EVERY == 0 else 0.045) * pulse
		draw_line(Vector2(0.0, y), Vector2(arena_size.x, y), Color(COLOR_GRID, alpha), 1.0)
		yi += 1


func _draw_frame() -> void:
	var rect := Rect2(Vector2.ZERO, arena_size)
	# Faked glow: wide translucent stroke under a crisp bright one.
	draw_rect(rect.grow(-1.0), Color(COLOR_FRAME, 0.10), false, 6.0)
	draw_rect(rect.grow(-3.0), Color(COLOR_FRAME, 0.55), false, 2.0)

	var bright := Color(COLOR_FRAME, 0.9)
	_draw_bracket(Vector2(BRACKET_INSET, BRACKET_INSET), Vector2(1.0, 1.0), bright)
	_draw_bracket(
		Vector2(arena_size.x - BRACKET_INSET, BRACKET_INSET), Vector2(-1.0, 1.0), bright)
	_draw_bracket(
		Vector2(BRACKET_INSET, arena_size.y - BRACKET_INSET), Vector2(1.0, -1.0), bright)
	_draw_bracket(
		Vector2(arena_size.x - BRACKET_INSET, arena_size.y - BRACKET_INSET),
		Vector2(-1.0, -1.0),
		bright,
	)

	# Calibration ticks along the frame at major grid intervals.
	var tick_col := Color(COLOR_FRAME, 0.30)
	var step := GRID_MINOR * MAJOR_EVERY
	var xi := 1
	while xi * step < arena_size.x:
		var x := xi * step
		draw_line(Vector2(x, 3.0), Vector2(x, 9.0), tick_col, 2.0)
		draw_line(Vector2(x, arena_size.y - 3.0), Vector2(x, arena_size.y - 9.0), tick_col, 2.0)
		xi += 1
	var yi := 1
	while yi * step < arena_size.y:
		var y := yi * step
		draw_line(Vector2(3.0, y), Vector2(9.0, y), tick_col, 2.0)
		draw_line(Vector2(arena_size.x - 3.0, y), Vector2(arena_size.x - 9.0, y), tick_col, 2.0)
		yi += 1


func _draw_bracket(corner: Vector2, dir: Vector2, color: Color) -> void:
	draw_line(corner, corner + Vector2(dir.x * BRACKET_LEN, 0.0), color, 3.0)
	draw_line(corner, corner + Vector2(0.0, dir.y * BRACKET_LEN), color, 3.0)
