extends Node2D
## Draws the live sim entities (blocks, projectiles, player) from SimState
## with layered fake-glow shapes and render-rate interpolation. Read-only:
## renders state, never mutates it. Interpolation/trail bookkeeping is owned
## by main.gd and shared in by reference.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const DrawUtil := preload("res://view/draw_util.gd")

const COLOR_BG := Color("0b0d13")
const COLOR_PLAYER := Color("e8e6e3")
const COLOR_PLAYER_GLOW := Color("3fd0d4")
const COLOR_VISOR := Color("101623")
const COLOR_EYE := Color("6ff2f6")
const COLOR_AIM := Color("3fd0d4")
const COLOR_PROJ := Color("ffd75e")
const COLOR_PROJ_CORE := Color("fff6d8")
const COLOR_BLOCK_FILL := Color("241f3d")
const COLOR_BLOCK_EDGE := Color("8f7bea")
const COLOR_BLOCK_BRIGHT := Color("c3b6ff")
const COLOR_CRACK := Color("0e0c18")

var core: SimCoreScript
var prev_player_pos := Vector2.ZERO
var proj_prev: Dictionary[int, Vector2] = {}
var proj_trails: Dictionary[int, PackedVector2Array] = {}
var recoil := Vector2.ZERO

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if core == null:
		return
	var state: SimStateScript = core.state
	var f := Engine.get_physics_interpolation_fraction()

	for b: SimStateScript.Block in state.blocks:
		_draw_block(b)
	for p: SimStateScript.Projectile in state.projectiles:
		_draw_projectile(p, f)
	_draw_player(state, f)


func _draw_block(b: SimStateScript.Block) -> void:
	var rect := Rect2(b.pos, b.size)
	var max_hp := core.block_max_hp
	var health := float(b.hp) / float(max_hp)
	var damage := max_hp - b.hp

	var edge_alpha := lerpf(0.45, 1.0, health)
	if b.hp == 1:
		# Failing panel: unstable flicker.
		edge_alpha *= 0.82 + 0.18 * sin(_time * 26.0 + b.pos.x)

	# Faked outer glow.
	draw_rect(rect.grow(7.0), Color(COLOR_BLOCK_EDGE, 0.04 * edge_alpha))
	draw_rect(rect.grow(3.0), Color(COLOR_BLOCK_EDGE, 0.09 * edge_alpha))

	# Panel fill dims as it takes damage; top sheen + inner outline sell "hologram".
	draw_rect(rect, COLOR_BLOCK_FILL.lerp(COLOR_BG, (1.0 - health) * 0.5))
	draw_rect(
		Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, 3.0)),
		Color(1.0, 1.0, 1.0, 0.09),
	)
	draw_rect(rect.grow(-5.0), Color(COLOR_BLOCK_BRIGHT, 0.10 * health), false, 1.0)

	if damage > 0:
		_draw_cracks(rect, damage, hash(b.pos))

	draw_rect(rect, Color(COLOR_BLOCK_EDGE, edge_alpha), false, 2.0)
	_draw_block_corners(rect.grow(-1.0), Color(COLOR_BLOCK_BRIGHT, edge_alpha))

	for i in b.hp:
		draw_rect(
			Rect2(
				rect.position + Vector2(6.0 + i * 8.0, rect.size.y - 10.0),
				Vector2(4.0, 4.0),
			),
			Color(COLOR_BLOCK_BRIGHT, 0.85),
		)


func _draw_cracks(rect: Rect2, damage: int, seed_value: int) -> void:
	# Deterministic per block (seeded by its position) so cracks don't crawl
	# between frames; more cracks appear as damage grows.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in damage * 2:
		var p := Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y,
		)
		var points := PackedVector2Array([p])
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for j in 3:
			dir = dir.rotated(rng.randf_range(-0.9, 0.9))
			p += dir * rng.randf_range(6.0, 14.0)
			p.x = clampf(p.x, rect.position.x + 2.0, rect.end.x - 2.0)
			p.y = clampf(p.y, rect.position.y + 2.0, rect.end.y - 2.0)
			points.append(p)
		draw_polyline(points, Color(COLOR_CRACK, 0.85), 1.5)


func _draw_block_corners(rect: Rect2, color: Color) -> void:
	var l := 7.0
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		rect.end,
	]
	var dirs: Array[Vector2] = [
		Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]
	for i in 4:
		draw_line(corners[i], corners[i] + Vector2(dirs[i].x * l, 0.0), color, 2.0)
		draw_line(corners[i], corners[i] + Vector2(0.0, dirs[i].y * l), color, 2.0)


func _draw_projectile(p: SimStateScript.Projectile, f: float) -> void:
	var id := p.get_instance_id()
	var prev: Vector2 = proj_prev.get(id, p.pos)
	var pos := prev.lerp(p.pos, f)

	# Trail: per-segment fade and taper toward the bolt.
	var trail: PackedVector2Array = proj_trails.get(id, PackedVector2Array())
	if not trail.is_empty():
		var points := trail.duplicate()
		points.append(pos)
		var n := points.size()
		for i in n - 1:
			var t := float(i + 1) / float(n)
			draw_line(
				points[i], points[i + 1], Color(COLOR_PROJ, 0.04 + 0.20 * t), 1.0 + 3.5 * t)

	# Bolt: elongated along velocity, hot core inside layered glow.
	var r := core.projectile_radius
	draw_set_transform(pos, p.vel.angle(), Vector2(1.9, 1.0))
	draw_circle(Vector2.ZERO, r * 2.6, Color(COLOR_PROJ, 0.10))
	draw_circle(Vector2.ZERO, r * 1.6, Color(COLOR_PROJ, 0.38))
	draw_circle(Vector2.ZERO, r * 0.95, COLOR_PROJ_CORE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player(state: SimStateScript, f: float) -> void:
	var pos := prev_player_pos.lerp(state.player_pos, f) + recoil
	var r := core.player_radius
	var half_gap := r * 0.45
	var aim := state.player_aim
	var rot := aim.angle() + PI / 2.0

	# Breathing rim glow, hull oriented along the aim direction.
	var pulse := 0.75 + 0.25 * sin(_time * 2.6)
	DrawUtil.capsule(self, pos, r + 7.0, half_gap, rot, Color(COLOR_PLAYER_GLOW, 0.05 * pulse))
	DrawUtil.capsule(self, pos, r + 3.0, half_gap, rot, Color(COLOR_PLAYER_GLOW, 0.11 * pulse))
	DrawUtil.capsule(self, pos, r, half_gap, rot, COLOR_PLAYER)
	DrawUtil.capsule(self, pos, r - 3.0, half_gap, rot, Color(COLOR_PLAYER_GLOW, 0.07))

	# Sensor eye tracks the aim.
	draw_circle(pos + aim * (r * 0.45), r * 0.42, COLOR_VISOR)
	draw_circle(pos + aim * (r * 0.58), r * 0.20, COLOR_EYE)

	# Dodge recharge arc sweeps back in around the hull.
	if state.dodge_cooldown > 0:
		var frac := 1.0 - float(state.dodge_cooldown) / float(core.dodge_cooldown_ticks)
		if frac > 0.02:
			draw_arc(
				pos, r + 6.5, -PI / 2.0, -PI / 2.0 + TAU * frac, 28,
				Color(COLOR_AIM, 0.45), 2.0, true)

	# Aim chevron + faint targeting line.
	var tip := pos + aim * (r + 15.0)
	var chevron_base := pos + aim * (r + 8.0)
	var perp := aim.orthogonal() * 5.0
	draw_colored_polygon(
		PackedVector2Array([tip, chevron_base + perp, chevron_base - perp]),
		Color(COLOR_AIM, 0.95),
	)
	draw_line(pos + aim * (r + 18.0), pos + aim * (r + 60.0), Color(COLOR_AIM, 0.10), 2.0)
