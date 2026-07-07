extends Node2D
## Draws the live sim entities — blocks, enemies, projectiles, the player, and
## the previous run's ghost echo — from SimState with layered fake-glow shapes.
## Read-only: renders state, never mutates it. Trail bookkeeping is owned by
## main.gd and shared in by reference; this node shakes with the world (its
## position is set by main), so the overlay HUD stays rock-steady on top.

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
const COLOR_ENEMY_PROJ := Color("ff5d4f")
const COLOR_ENEMY_PROJ_CORE := Color("ffd9cf")
const COLOR_BLOCK_FILL := Color("241f3d")
const COLOR_BLOCK_EDGE := Color("8f7bea")
const COLOR_BLOCK_BRIGHT := Color("c3b6ff")
const COLOR_CRACK := Color("0e0c18")
const COLOR_DRONE := Color("ff8c5a")
const COLOR_INFANTRY := Color("e05e51")
const COLOR_HEAVY := Color("ff7a4f")
const COLOR_LANCER := Color("ff6fa5")
const COLOR_SAPPER := Color("b8e05a")
const COLOR_MORTAR := Color("d98c4a")
const COLOR_CACHE := Color("ffd75e")
const COLOR_SCHEMATIC := Color("6ff2f6")
const COLOR_REPAIR := Color("6ee08a")
const COLOR_MINE := Color("ff5d4f")
const COLOR_GHOST := Color(0.247, 0.816, 0.831, 0.35)
const COLOR_GHOST_PROJ := Color(0.247, 0.816, 0.831, 0.22)
## Windup warnings: danger red that heats toward white as the attack commits.
const COLOR_TELEGRAPH := Color("ff4d42")
const COLOR_TELEGRAPH_HOT := Color("ffe9dc")
## Rough ground left by artillery.
const COLOR_CRATER_FILL := Color("05060b")
const COLOR_CRATER_RIM := Color("7a563e")

var core: SimCoreScript
var ghost_core: SimCoreScript = null
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

	for c: SimStateScript.Crater in state.craters:
		_draw_crater(c)

	for r: SimStateScript.Rubble in state.rubble:
		_draw_rubble(r)

	for b: SimStateScript.Block in state.blocks:
		_draw_block(b)

	for c: SimStateScript.Cache in state.caches:
		_draw_cache(c)
	for m: SimStateScript.Mine in state.mines:
		_draw_mine(m)
	for p: SimStateScript.Pickup in state.pickups:
		_draw_pickup(p)

	for imp: SimStateScript.Impact in state.pending_impacts:
		_draw_impact_warning(imp, state.tick)

	if ghost_core != null:
		_draw_ghost()

	_draw_enemies(state)

	for p: SimStateScript.Projectile in state.enemy_projectiles:
		_draw_enemy_projectile(p)
	for p: SimStateScript.Projectile in state.projectiles:
		_draw_projectile(p)

	_draw_player(state)


## Scorched rough ground: dark bowl, ember rim, deterministic debris flecks.
func _draw_crater(c: SimStateScript.Crater) -> void:
	draw_circle(c.pos, c.radius, Color(COLOR_CRATER_FILL, 0.85))
	draw_circle(c.pos, c.radius * 0.55, Color(0.0, 0.0, 0.0, 0.5))
	draw_arc(c.pos, c.radius, 0.0, TAU, 40, Color(COLOR_CRATER_RIM, 0.4), 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.pos)
	for i in 6:
		var p := c.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * c.radius * 0.8
		draw_circle(p, rng.randf_range(1.5, 3.0), Color(COLOR_CRATER_RIM, 0.25))


## Incoming artillery: target ring + collapsing outer ring + hot center dot,
## flashing faster as the shell falls. Geometry is exact — the sim resolves
## the impact at precisely this circle.
func _draw_impact_warning(imp: SimStateScript.Impact, tick: int) -> void:
	var rem := imp.land_tick - tick
	var t := clampf(1.0 - float(rem) / 110.0, 0.0, 1.0)
	var flash := 0.65 + 0.35 * sin(_time * (8.0 + 22.0 * t))
	var color := COLOR_TELEGRAPH.lerp(COLOR_TELEGRAPH_HOT, t * t)
	draw_circle(imp.pos, imp.radius, Color(color, (0.04 + 0.10 * t) * flash))
	draw_arc(
		imp.pos, imp.radius, 0.0, TAU, 40,
		Color(color, (0.16 + 0.45 * t) * flash), 1.5 + 2.5 * t)
	var outer := imp.radius * (1.0 + float(rem) * 0.012)
	draw_arc(imp.pos, outer, 0.0, TAU, 40, Color(color, 0.22 * flash), 1.5)
	draw_circle(imp.pos, 3.0 + 2.0 * t, Color(color, 0.7 * flash))


## A dead block's remains: dim scattered slabs in a faint patch. Reads as
## debris, promises the slow, offers no cover.
func _draw_rubble(r: SimStateScript.Rubble) -> void:
	var rect := Rect2(r.pos, r.size)
	draw_rect(rect.grow(4.0), Color(COLOR_BLOCK_FILL, 0.30))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r.pos)
	for i in 9:
		var p := Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y)
		var half := Vector2(rng.randf_range(3.0, 8.0), rng.randf_range(2.0, 5.0))
		draw_set_transform(p, rng.randf_range(-0.6, 0.6), Vector2.ONE)
		draw_rect(Rect2(-half, half * 2.0), Color(COLOR_BLOCK_EDGE, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A lootable crate: braced box with a pulsing lock light. Schematic caches
## glow cyan and read as the thing worth crossing the map for.
func _draw_cache(c: SimStateScript.Cache) -> void:
	var rect := Rect2(c.pos, c.size)
	var color := COLOR_SCHEMATIC if c.kind == "schematic" else COLOR_CACHE
	var pulse := 0.6 + 0.4 * sin(_time * 3.2 + c.pos.x)
	draw_rect(rect.grow(6.0), Color(color, 0.05 * pulse))
	draw_rect(rect.grow(2.0), Color(color, 0.10 * pulse))
	draw_rect(rect, Color(COLOR_BLOCK_FILL, 0.9))
	draw_rect(rect, Color(color, 0.85), false, 2.0)
	_draw_block_corners(rect.grow(2.0), Color(color, 0.9 * pulse))
	draw_circle(rect.get_center(), 4.0, Color(color, 0.4 + 0.5 * pulse))
	# Damage state: lock dims as it cracks.
	if c.kind == "schematic":
		# A small orbiting spark marks it as singular.
		var orbit := rect.get_center() + Vector2.from_angle(_time * 2.0) * (rect.size.x * 0.75)
		draw_circle(orbit, 2.5, Color(color, 0.8))


## Salvage on the ground: bobbing diamond, colored by what it does.
func _draw_pickup(p: SimStateScript.Pickup) -> void:
	var bob := sin(_time * 4.0 + p.pos.x * 0.1) * 3.0
	var pos := p.pos + Vector2(0.0, bob)
	var color := COLOR_REPAIR
	if p.kind == "overcharge":
		color = COLOR_PROJ
	elif p.kind == "mine_restock":
		color = COLOR_MINE
	# Expiring salvage flickers.
	var alpha := 0.95
	if p.ttl < 240:
		alpha = 0.4 + 0.5 * sin(_time * 12.0)
	var pts := PackedVector2Array([
		pos + Vector2(0.0, -8.0), pos + Vector2(7.0, 0.0),
		pos + Vector2(0.0, 8.0), pos + Vector2(-7.0, 0.0)])
	draw_circle(pos, 13.0, Color(color, 0.08))
	draw_colored_polygon(pts, Color(color, alpha * 0.85))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(color, alpha), 1.5)


## A planted mine: dark disc; the core blinks red once armed, and a faint
## ring shows the trigger reach so placement is a readable plan.
func _draw_mine(m: SimStateScript.Mine) -> void:
	var armed := m.arm_ticks <= 0
	var blink := 0.5 + 0.5 * sin(_time * (10.0 if armed else 3.0))
	draw_circle(m.pos, 8.0, Color(COLOR_BG, 0.9))
	draw_arc(m.pos, 8.0, 0.0, TAU, 20, Color(COLOR_MINE, 0.8), 1.5)
	draw_circle(m.pos, 3.0, Color(COLOR_MINE, (0.9 if armed else 0.4) * blink))
	if armed:
		draw_arc(m.pos, 42.0, 0.0, TAU, 32, Color(COLOR_MINE, 0.12), 1.0)


func _draw_block(b: SimStateScript.Block) -> void:
	var rect := Rect2(b.pos, b.size)
	var max_hp := maxi(b.max_hp, 1)
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

	# HP readout: pips for light cover, a thin fill bar for tough segments
	# (a seawall at 10 pips would read as noise).
	if max_hp <= 6:
		for i in b.hp:
			draw_rect(
				Rect2(
					rect.position + Vector2(6.0 + i * 8.0, rect.size.y - 10.0),
					Vector2(4.0, 4.0),
				),
				Color(COLOR_BLOCK_BRIGHT, 0.85),
			)
	else:
		var bar := Rect2(
			rect.position + Vector2(6.0, rect.size.y - 9.0),
			Vector2(rect.size.x - 12.0, 3.0))
		draw_rect(bar, Color(COLOR_BLOCK_BRIGHT, 0.2))
		draw_rect(
			Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)),
			Color(COLOR_BLOCK_BRIGHT, 0.75))


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


## The assault, rendered as hostile holo constructs. Each type keeps its M5
## silhouette but gains rim glow, a health-driven dim, and an aim indicator.
## Telegraphs draw first (under every body) so a windup is never occluded.
func _draw_enemies(state: SimStateScript) -> void:
	for e: SimStateScript.Enemy in state.enemies:
		if e.phase == SimCoreScript.PHASE_WINDUP:
			_draw_telegraph(e)

	for e: SimStateScript.Enemy in state.enemies:
		var stats: Dictionary = core.enemy_types[e.type]
		var radius: float = stats["radius"]
		var max_hp := int(stats["hp"])
		var strength := clampf(float(e.hp) / float(max_hp), 0.0, 1.0)
		# Recovering enemies read as spent — the punish window is visible.
		if e.phase == SimCoreScript.PHASE_RECOVER:
			strength *= 0.45
		var toward := (state.player_pos - e.pos).normalized()
		if e.phase == SimCoreScript.PHASE_WINDUP \
				or e.phase == SimCoreScript.PHASE_COMMIT:
			toward = e.attack_dir
		match e.type:
			"drone":
				if e.phase == SimCoreScript.PHASE_COMMIT:
					# Dive streak behind the committed lunge.
					draw_line(
						e.pos - e.attack_dir * 26.0, e.pos,
						Color(COLOR_DRONE, 0.5), 4.0)
				_draw_enemy_drone(e.pos, radius, strength, toward)
			"infantry":
				_draw_enemy_infantry(e.pos, radius, strength, toward, e)
			"lancer":
				if e.phase == SimCoreScript.PHASE_COMMIT:
					draw_line(
						e.pos - e.attack_dir * 40.0, e.pos,
						Color(COLOR_LANCER, 0.55), 5.0)
				_draw_enemy_lancer(e.pos, radius, strength, toward)
			"sapper":
				_draw_enemy_sapper(e.pos, radius, strength, toward)
			"mortar":
				_draw_enemy_mortar(e.pos, radius, strength)
			_:
				_draw_enemy_heavy(e.pos, radius, strength, toward)


## Windup warning, per behavior: divers draw their exact committed lane,
## volleys their locked firing line, slammers the ring that is about to land.
## Everything heats red -> white as phase_ticks runs out; the geometry is
## truthful because the sim locked attack_dir at windup start.
func _draw_telegraph(e: SimStateScript.Enemy) -> void:
	var stats: Dictionary = core.enemy_types[e.type]
	var windup := maxf(float(stats["windup_ticks"]), 1.0)
	var t := 1.0 - float(e.phase_ticks) / windup
	var flash := 0.7 + 0.3 * sin(_time * 22.0)
	var color := COLOR_TELEGRAPH.lerp(COLOR_TELEGRAPH_HOT, t * t)
	var radius: float = stats["radius"]

	match String(stats["behavior"]):
		"diver":
			var reach: float = (
				float(stats["dive_speed"]) * float(stats["dive_ticks"])
				* SimCoreScript.DT + radius * 2.0)
			var to := e.pos + e.attack_dir * reach
			draw_line(e.pos, to, Color(color, (0.10 + 0.38 * t) * flash), 3.0)
			var perp := e.attack_dir.orthogonal() * 6.0
			var base := to - e.attack_dir * 10.0
			draw_colored_polygon(
				PackedVector2Array([to, base + perp, base - perp]),
				Color(color, (0.25 + 0.6 * t) * flash))
		"volley":
			var reach := float(stats["preferred_range"]) * 1.25
			var muzzle := e.pos + e.attack_dir * (radius + 6.0)
			draw_line(
				muzzle, muzzle + e.attack_dir * reach,
				Color(color, (0.12 + 0.38 * t) * flash), 2.5)
			# Shot pips march toward the muzzle as the volley loads.
			for i in int(stats["volley_shots"]):
				var d := radius + 14.0 + float(i) * 10.0
				draw_circle(
					e.pos + e.attack_dir * d, 2.5,
					Color(color, (0.2 + 0.7 * t) * flash))
		"slammer":
			var r: float = stats["slam_radius"]
			draw_circle(e.pos, r * t, Color(color, 0.10 * flash))
			draw_arc(
				e.pos, r, 0.0, TAU, 48,
				Color(color, (0.22 + 0.55 * t) * flash), 2.0 + 3.5 * t)
		"lancer":
			var reach: float = (
				float(stats["charge_speed"]) * float(stats["charge_ticks"])
				* SimCoreScript.DT + radius * 2.0)
			var to := e.pos + e.attack_dir * reach
			draw_line(e.pos, to, Color(color, (0.12 + 0.42 * t) * flash), 4.0)
			var perp := e.attack_dir.orthogonal() * 8.0
			var base := to - e.attack_dir * 14.0
			draw_colored_polygon(
				PackedVector2Array([to, base + perp, base - perp]),
				Color(color, (0.3 + 0.6 * t) * flash))
		"sapper":
			var r: float = stats["blast_radius"]
			draw_circle(e.pos, r * t, Color(color, 0.12 * flash))
			draw_arc(
				e.pos, r, 0.0, TAU, 40,
				Color(color, (0.25 + 0.6 * t) * flash), 2.0 + 3.0 * t)
		"mortar":
			# attack_dir is the registered target position: crosshair there.
			var target: Vector2 = e.attack_dir
			var s := 14.0 + 8.0 * (1.0 - t)
			draw_arc(target, s, 0.0, TAU, 24, Color(color, (0.3 + 0.5 * t) * flash), 2.0)
			draw_line(
				target + Vector2(-s - 6.0, 0.0), target + Vector2(s + 6.0, 0.0),
				Color(color, 0.5 * flash), 1.5)
			draw_line(
				target + Vector2(0.0, -s - 6.0), target + Vector2(0.0, s + 6.0),
				Color(color, 0.5 * flash), 1.5)
			draw_line(
				e.pos, target, Color(color, 0.10 * flash), 1.0)


func _draw_enemy_drone(pos: Vector2, radius: float, strength: float, toward: Vector2) -> void:
	var fill := COLOR_DRONE.lerp(COLOR_BG, (1.0 - strength) * 0.7)
	draw_circle(pos, radius + 5.0, Color(COLOR_DRONE, 0.06))
	draw_circle(pos, radius + 2.0, Color(COLOR_DRONE, 0.12))
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0.0, TAU, 24, Color(COLOR_DRONE, 0.9), 1.5)
	# Forward stinger toward the player.
	draw_line(pos + toward * radius, pos + toward * (radius + 6.0), COLOR_DRONE, 2.0)
	draw_circle(pos + toward * (radius * 0.2), radius * 0.28, Color(COLOR_EYE, 0.8))


func _draw_enemy_infantry(
	pos: Vector2, radius: float, strength: float, toward: Vector2,
	e: SimStateScript.Enemy
) -> void:
	var half := Vector2(radius, radius)
	var rect := Rect2(pos - half, half * 2.0)
	var fill := COLOR_INFANTRY.lerp(COLOR_BG, (1.0 - strength) * 0.7)
	draw_rect(rect.grow(4.0), Color(COLOR_INFANTRY, 0.06))
	draw_rect(rect.grow(2.0), Color(COLOR_INFANTRY, 0.11))
	draw_rect(rect, fill)
	draw_rect(rect, Color(COLOR_INFANTRY, 0.95), false, 2.0)
	_draw_block_corners(rect, Color(COLOR_INFANTRY, 0.9))
	# Muzzle line: bright when a volley is ready or firing, dim mid-reload —
	# the reload window is meant to be read and punished.
	var reloading := e.phase == SimCoreScript.PHASE_ROAM and e.fire_cooldown > 0
	var muzzle_alpha := 0.35 if reloading else 1.0
	draw_line(pos, pos + toward * (radius + 8.0), Color(COLOR_INFANTRY, muzzle_alpha), 3.0)
	if reloading:
		# Reload progress ticks up over the barrel.
		var frac := 1.0 - float(e.fire_cooldown) / maxf(
			float(core.enemy_types[e.type]["fire_cooldown_ticks"]), 1.0)
		draw_rect(
			Rect2(pos + Vector2(-radius, -radius - 7.0), Vector2(radius * 2.0 * frac, 3.0)),
			Color(COLOR_INFANTRY, 0.55))


func _draw_enemy_heavy(pos: Vector2, radius: float, strength: float, toward: Vector2) -> void:
	var fill := COLOR_HEAVY.lerp(COLOR_BG, (1.0 - strength) * 0.6)
	draw_circle(pos, radius + 6.0, Color(COLOR_HEAVY, 0.06))
	draw_circle(pos, radius + 2.0, Color(COLOR_HEAVY, 0.12))
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0.0, TAU, 32, Color(COLOR_HEAVY, 0.95), 3.0)
	draw_arc(pos, radius * 0.55, 0.0, TAU, 24, Color(COLOR_HEAVY, 0.8), 2.0)
	# Charging core that pulses.
	var pulse := 0.5 + 0.5 * sin(_time * 4.0 + pos.x)
	draw_circle(pos, radius * 0.28, Color(COLOR_ENEMY_PROJ, 0.4 + 0.4 * pulse))
	draw_line(pos + toward * (radius * 0.55), pos + toward * (radius + 4.0), COLOR_HEAVY, 3.0)


## A blade of a unit: elongated dart aimed down its threat axis.
func _draw_enemy_lancer(
	pos: Vector2, radius: float, strength: float, toward: Vector2
) -> void:
	var fill := COLOR_LANCER.lerp(COLOR_BG, (1.0 - strength) * 0.7)
	var perp := toward.orthogonal()
	var pts := PackedVector2Array([
		pos + toward * (radius + 8.0),
		pos - toward * radius + perp * radius * 0.7,
		pos - toward * radius * 0.5,
		pos - toward * radius - perp * radius * 0.7,
	])
	draw_circle(pos, radius + 4.0, Color(COLOR_LANCER, 0.07))
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(COLOR_LANCER, 0.95), 2.0)


## The demolitionist: small diamond with a strobing charge pack. It wants
## your walls, not you.
func _draw_enemy_sapper(
	pos: Vector2, radius: float, strength: float, toward: Vector2
) -> void:
	var fill := COLOR_SAPPER.lerp(COLOR_BG, (1.0 - strength) * 0.7)
	var pts := PackedVector2Array([
		pos + Vector2(0.0, -radius), pos + Vector2(radius, 0.0),
		pos + Vector2(0.0, radius), pos + Vector2(-radius, 0.0)])
	draw_circle(pos, radius + 4.0, Color(COLOR_SAPPER, 0.07))
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(COLOR_SAPPER, 0.9), 1.5)
	var strobe := 0.4 + 0.6 * absf(sin(_time * 9.0 + pos.x))
	draw_circle(pos, radius * 0.3, Color(COLOR_TELEGRAPH, strobe))
	draw_line(pos, pos + toward * (radius + 5.0), Color(COLOR_SAPPER, 0.6), 2.0)


## The dug-in emplacement: base plate, ring, elevated tube. Doesn't move;
## dies where it stands.
func _draw_enemy_mortar(pos: Vector2, radius: float, strength: float) -> void:
	var fill := COLOR_MORTAR.lerp(COLOR_BG, (1.0 - strength) * 0.6)
	var half := Vector2(radius + 6.0, radius * 0.5)
	draw_rect(Rect2(pos - Vector2(half.x, -radius * 0.4), Vector2(half.x * 2.0, 6.0)),
		Color(COLOR_MORTAR, 0.5))
	draw_circle(pos, radius + 5.0, Color(COLOR_MORTAR, 0.07))
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0.0, TAU, 28, Color(COLOR_MORTAR, 0.95), 2.5)
	# The tube, angled up-field.
	draw_line(pos, pos + Vector2(0.0, -radius - 9.0), Color(COLOR_MORTAR, 0.9), 4.0)
	draw_circle(pos + Vector2(0.0, -radius - 9.0), 3.0, Color(COLOR_TELEGRAPH, 0.7))


func _draw_projectile(p: SimStateScript.Projectile) -> void:
	var pos := p.pos
	var id := p.get_instance_id()

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


func _draw_enemy_projectile(p: SimStateScript.Projectile) -> void:
	var r := core.projectile_radius
	draw_set_transform(p.pos, p.vel.angle(), Vector2(1.7, 1.0))
	draw_circle(Vector2.ZERO, r * 2.4, Color(COLOR_ENEMY_PROJ, 0.10))
	draw_circle(Vector2.ZERO, r * 1.5, Color(COLOR_ENEMY_PROJ, 0.4))
	draw_circle(Vector2.ZERO, r * 0.9, COLOR_ENEMY_PROJ_CORE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The previous run's echo: capsule, aim tick, and projectiles, all translucent
## cyan. Its world state (blocks, enemies) is deliberately not drawn — only the
## live run's arena is authoritative on screen.
func _draw_ghost() -> void:
	var state: SimStateScript = ghost_core.state
	if state.player_down:
		return

	for p: SimStateScript.Projectile in state.projectiles:
		draw_circle(p.pos, ghost_core.projectile_radius, COLOR_GHOST_PROJ)

	var pos := state.player_pos
	var r := ghost_core.player_radius
	var half_gap := r * 0.45
	var rot := state.player_aim.angle() + PI / 2.0
	DrawUtil.capsule(self, pos, r, half_gap, rot, COLOR_GHOST)
	var aim := state.player_aim
	draw_line(pos + aim * (r + 4.0), pos + aim * (r + 14.0), COLOR_GHOST, 3.0)


func _draw_player(state: SimStateScript) -> void:
	var pos := state.player_pos + recoil
	var r := core.player_radius
	var half_gap := r * 0.45
	var aim := state.player_aim
	var rot := aim.angle() + PI / 2.0

	# Body alpha flickers while dodge i-frames are active (matches M5 read).
	var body := COLOR_PLAYER
	if state.iframe_ticks > 0 and (state.iframe_ticks / 2) % 2 == 0:
		body = Color(COLOR_PLAYER, 0.45)

	# Breathing rim glow, hull oriented along the aim direction.
	var pulse := 0.75 + 0.25 * sin(_time * 2.6)
	DrawUtil.capsule(self, pos, r + 7.0, half_gap, rot, Color(COLOR_PLAYER_GLOW, 0.05 * pulse))
	DrawUtil.capsule(self, pos, r + 3.0, half_gap, rot, Color(COLOR_PLAYER_GLOW, 0.11 * pulse))
	DrawUtil.capsule(self, pos, r, half_gap, rot, body)
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
