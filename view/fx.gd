extends Node2D
## Transient view-only effects: sparks, shockwave rings, block fragments,
## muzzle flashes, dodge afterimages, fading projectile trails. The node's
## material is additive, so overlapping shapes bloom on the dark arena.
## Purely cosmetic — nothing here reads input or touches the sim.

const DrawUtil := preload("res://view/draw_util.gd")

const COLOR_SPARK := Color("ffd75e")
const COLOR_SPARK_HOT := Color("fff3c4")
const COLOR_CYAN := Color("3fd0d4")
const COLOR_VIOLET := Color("a794f7")
const COLOR_WHITE := Color("e8e6e3")


class Effect extends RefCounted:
	var life: float = 1.0
	var max_life: float = 1.0

	## Remaining-life fraction: 1.0 at spawn, 0.0 at death.
	func u() -> float:
		return clampf(life / max_life, 0.0, 1.0)

	func step(delta: float) -> void:
		life -= delta

	func paint(_ci: CanvasItem) -> void:
		pass


class Spark extends Effect:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var color := Color.WHITE
	var width: float = 2.0

	func step(delta: float) -> void:
		super.step(delta)
		pos += vel * delta
		vel -= vel * minf(4.5 * delta, 1.0)

	func paint(ci: CanvasItem) -> void:
		var tail := pos - vel * 0.035
		if tail.distance_squared_to(pos) < 1.0:
			tail = pos + Vector2(1.0, 0.0)
		ci.draw_line(pos, tail, Color(color, color.a * u()), width)


class Mote extends Effect:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius: float = 2.0
	var color := Color.WHITE

	func step(delta: float) -> void:
		super.step(delta)
		pos += vel * delta
		vel -= vel * minf(3.0 * delta, 1.0)

	func paint(ci: CanvasItem) -> void:
		ci.draw_circle(pos, radius * (0.3 + 0.7 * u()), Color(color, color.a * u()))


class Ring extends Effect:
	var pos := Vector2.ZERO
	var r_from: float = 4.0
	var r_to: float = 60.0
	var width: float = 4.0
	var color := Color.WHITE

	func paint(ci: CanvasItem) -> void:
		var k := 1.0 - u()
		var eased := 1.0 - (1.0 - k) * (1.0 - k)
		var r := lerpf(r_from, r_to, eased)
		ci.draw_arc(
			pos, r, 0.0, TAU, 48, Color(color, color.a * u()), maxf(width * u(), 1.0), true)


class RectFlash extends Effect:
	var rect := Rect2()
	var color := Color.WHITE

	func paint(ci: CanvasItem) -> void:
		ci.draw_rect(rect, Color(color, color.a * u()))


class Fragment extends Effect:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var half := Vector2(4.0, 4.0)
	var rot: float = 0.0
	var rot_speed: float = 0.0
	var color := Color.WHITE

	func step(delta: float) -> void:
		super.step(delta)
		pos += vel * delta
		vel -= vel * minf(2.2 * delta, 1.0)
		rot += rot_speed * delta

	func paint(ci: CanvasItem) -> void:
		var s := 0.35 + 0.65 * u()
		ci.draw_set_transform(pos, rot, Vector2.ONE)
		ci.draw_rect(Rect2(-half * s, half * 2.0 * s), Color(color, color.a * u()))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Muzzle extends Effect:
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT

	func paint(ci: CanvasItem) -> void:
		var k := 1.0 - u()
		ci.draw_circle(pos, 5.0 + 9.0 * k, Color(COLOR_SPARK_HOT, 0.55 * u()))
		for spread: float in [-0.45, 0.0, 0.45]:
			var d := dir.rotated(spread)
			ci.draw_line(
				pos + d * 4.0,
				pos + d * (12.0 + 16.0 * k),
				Color(COLOR_SPARK, 0.7 * u()),
				2.0,
			)


class Afterimage extends Effect:
	var pos := Vector2.ZERO
	var rot: float = 0.0
	var radius: float = 14.0
	var half_gap: float = 6.0

	func paint(ci: CanvasItem) -> void:
		DrawUtil.capsule(ci, pos, radius, half_gap, rot, Color(COLOR_CYAN, 0.30 * u()))


class TrailGhost extends Effect:
	var points := PackedVector2Array()
	var color := Color.WHITE

	func paint(ci: CanvasItem) -> void:
		if points.size() >= 2:
			ci.draw_polyline(points, Color(color, 0.22 * u()), 2.0)


var _effects: Array[Effect] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	var survivors: Array[Effect] = []
	for e: Effect in _effects:
		e.step(delta)
		if e.life > 0.0:
			survivors.append(e)
	_effects = survivors
	queue_redraw()


func _draw() -> void:
	for e: Effect in _effects:
		e.paint(self)


# --- Composite spawners (the vocabulary main.gd speaks) ---


func muzzle_flash(pos: Vector2, dir: Vector2) -> void:
	var m := Muzzle.new()
	_set_life(m, 0.09)
	m.pos = pos
	m.dir = dir
	_effects.append(m)


func impact(pos: Vector2, normal_dir: Vector2) -> void:
	_burst(pos, normal_dir, 8, 160.0, 460.0, 1.0, COLOR_SPARK, COLOR_SPARK_HOT)
	ring(pos, COLOR_SPARK, 2.0, 20.0, 0.18, 3.0)


func fizzle(pos: Vector2) -> void:
	var m := Mote.new()
	_set_life(m, _rng.randf_range(0.18, 0.28))
	m.pos = pos
	m.radius = 3.5
	m.color = Color(COLOR_SPARK, 0.5)
	_effects.append(m)


func block_hit(rect: Rect2) -> void:
	var f := RectFlash.new()
	_set_life(f, 0.12)
	f.rect = rect.grow(1.0)
	f.color = Color(1.0, 1.0, 1.0, 0.30)
	_effects.append(f)


func block_destroyed(rect: Rect2) -> void:
	var center := rect.get_center()

	var f := RectFlash.new()
	_set_life(f, 0.10)
	f.rect = rect.grow(3.0)
	f.color = Color(1.0, 1.0, 1.0, 0.55)
	_effects.append(f)

	for i in 12:
		var frag := Fragment.new()
		_set_life(frag, _rng.randf_range(0.45, 0.8))
		frag.pos = Vector2(
			rect.position.x + _rng.randf() * rect.size.x,
			rect.position.y + _rng.randf() * rect.size.y,
		)
		var out := (frag.pos - center).normalized()
		if out == Vector2.ZERO:
			out = Vector2.from_angle(_rng.randf() * TAU)
		frag.vel = out * _rng.randf_range(140.0, 420.0)
		frag.half = Vector2(_rng.randf_range(3.0, 9.0), _rng.randf_range(3.0, 9.0))
		frag.rot = _rng.randf() * TAU
		frag.rot_speed = _rng.randf_range(-7.0, 7.0)
		frag.color = Color(COLOR_VIOLET, 0.85)
		_effects.append(frag)

	_burst(center, Vector2.RIGHT, 16, 120.0, 620.0, PI, COLOR_VIOLET, COLOR_SPARK_HOT)
	ring(center, COLOR_WHITE, 6.0, 110.0, 0.4, 6.0)
	ring(center, COLOR_VIOLET, 4.0, 70.0, 0.3, 4.0)


func dodge_burst(pos: Vector2, dir: Vector2) -> void:
	ring(pos, COLOR_CYAN, 4.0, 46.0, 0.25, 4.0)
	_burst(pos, -dir, 8, 220.0, 520.0, 0.5, COLOR_CYAN, COLOR_WHITE)


func afterimage(pos: Vector2, rot: float, radius: float, half_gap: float) -> void:
	var a := Afterimage.new()
	_set_life(a, 0.26)
	a.pos = pos
	a.rot = rot
	a.radius = radius
	a.half_gap = half_gap
	_effects.append(a)


func thrust(pos: Vector2, base_vel: Vector2) -> void:
	var m := Mote.new()
	_set_life(m, _rng.randf_range(0.18, 0.34))
	m.pos = pos + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
	m.vel = base_vel + Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-18.0, 18.0))
	m.radius = _rng.randf_range(1.5, 3.0)
	m.color = Color(COLOR_CYAN, 0.35)
	_effects.append(m)


func trail_ghost(points: PackedVector2Array) -> void:
	var t := TrailGhost.new()
	_set_life(t, 0.22)
	t.points = points
	t.color = COLOR_SPARK
	_effects.append(t)


func ring(
	pos: Vector2, color: Color, r_from: float, r_to: float, dur: float, width: float
) -> void:
	var r := Ring.new()
	_set_life(r, dur)
	r.pos = pos
	r.color = color
	r.r_from = r_from
	r.r_to = r_to
	r.width = width
	_effects.append(r)


func _burst(
	pos: Vector2,
	dir: Vector2,
	count: int,
	speed_min: float,
	speed_max: float,
	spread: float,
	col_a: Color,
	col_b: Color,
) -> void:
	var base_angle := dir.angle() if dir != Vector2.ZERO else _rng.randf() * TAU
	for i in count:
		var s := Spark.new()
		_set_life(s, _rng.randf_range(0.15, 0.4))
		s.pos = pos
		var angle := base_angle + _rng.randf_range(-spread, spread)
		s.vel = Vector2.from_angle(angle) * _rng.randf_range(speed_min, speed_max)
		s.color = col_a if _rng.randf() < 0.7 else col_b
		s.width = _rng.randf_range(1.5, 2.5)
		_effects.append(s)


func _set_life(e: Effect, dur: float) -> void:
	e.max_life = dur
	e.life = dur
