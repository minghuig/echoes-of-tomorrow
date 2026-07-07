class_name SimCore
extends RefCounted
## Deterministic simulation. Advances only via step(), one 1/60s tick at a
## time. All randomness must go through `rng` (the only RNG); no wall-clock,
## no engine physics, no scene tree. A run is reproducible from
## (seed, loadout, command log) — the loadout is the resolved sentience-tree
## stat modifiers, pure data supplied by the meta layer at setup.

const SimCommand := preload("res://sim/command.gd")
const State := preload("res://sim/sim_state.gd")

const TICKS_PER_SECOND: int = 60
const DT: float = 1.0 / 60.0

## Enemy attack phases (SimState.Enemy.phase). Every dangerous action winds up
## visibly, commits along a locked direction, then leaves a punish window.
const PHASE_ROAM := 0
const PHASE_WINDUP := 1
const PHASE_COMMIT := 2
const PHASE_RECOVER := 3

const TUNING_PATH := "res://content/tuning.json"
const LAYOUT_PATH := "res://content/block_layout.json"
const ENEMIES_PATH := "res://content/enemies.json"
const WAVES_PATH := "res://content/waves.json"

var state: State
var rng: RandomNumberGenerator

# Tuning values, loaded from content/tuning.json in setup(). Public fields are
# read by the view (radii for shapes, ticks/hp for cosmetic indicators).
var player_radius: float
var _player_speed: float
var player_max_hp: int
var _dodge_impulse: float
var _dodge_decay: float
var dodge_cooldown_ticks: int
var _dodge_iframe_ticks: int
var projectile_radius: float
var _proj_speed: float
var _proj_ttl_ticks: int
var _fire_cooldown_ticks: int
var _proj_damage: int
var _proj_spawn_offset: float
var block_max_hp: int

# Enemy roster (type name -> stats Dictionary) and the assault schedule,
# loaded from content in setup().
var enemy_types: Dictionary
var _waves: Array
var _escalation: Dictionary
var _first_wave_tick: int
var _wave_interval_ticks: int
var _trickle_interval_ticks: int
var _spawn_edge_margin: float

# The authored assault timeline (barrages, flank entries) and artillery
# tuning, from waves.json. Craters cap so the slow-field stays bounded.
var _events: Array
var _artillery: Dictionary
var _recurring_barrage: Dictionary
var _crater_slow: float
var _max_craters: int

# From the loadout: extra fragments stripped per kill (Exfiltration branch).
var _kill_fragment_add: int = 0


func setup(seed_value: int, loadout: Dictionary = {}) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	var tuning: Dictionary = _load_json(TUNING_PATH)
	var player: Dictionary = tuning["player"]
	var projectile: Dictionary = tuning["projectile"]
	var block: Dictionary = tuning["block"]
	var arena: Dictionary = tuning["arena"]

	player_radius = player["radius"]
	_player_speed = player["speed"]
	player_max_hp = int(player["max_hp"])
	_dodge_impulse = player["dodge_impulse"]
	_dodge_decay = player["dodge_decay"]
	dodge_cooldown_ticks = int(player["dodge_cooldown_ticks"])
	_dodge_iframe_ticks = int(player["dodge_iframe_ticks"])
	projectile_radius = projectile["radius"]
	_proj_speed = projectile["speed"]
	_proj_ttl_ticks = int(projectile["ttl_ticks"])
	_fire_cooldown_ticks = int(projectile["fire_cooldown_ticks"])
	_proj_damage = int(projectile["damage"])
	_proj_spawn_offset = projectile["spawn_offset"]
	block_max_hp = int(block["hp"])

	enemy_types = _load_json(ENEMIES_PATH)
	var waves_cfg: Dictionary = _load_json(WAVES_PATH)
	_waves = waves_cfg["waves"]
	_escalation = waves_cfg["escalation"]
	_first_wave_tick = int(waves_cfg["first_wave_tick"])
	_wave_interval_ticks = int(waves_cfg["wave_interval_ticks"])
	_trickle_interval_ticks = int(waves_cfg["trickle_interval_ticks"])
	_spawn_edge_margin = waves_cfg["spawn_edge_margin"]
	_events = waves_cfg.get("events", [])
	_artillery = waves_cfg.get("artillery", {})
	_recurring_barrage = waves_cfg.get("recurring_barrage", {})
	_crater_slow = float(_artillery.get("crater_slow", 1.0))
	_max_craters = int(_artillery.get("max_craters", 48))

	# Sentience-tree modifiers. Integer/rounded math so identical loadouts
	# always resolve to identical tuning.
	player_max_hp += int(loadout.get("max_hp_add", 0))
	_fire_cooldown_ticks = maxi(
		1, roundi(float(_fire_cooldown_ticks) * float(loadout.get("fire_cooldown_scale", 1.0))))
	dodge_cooldown_ticks = maxi(
		1, roundi(float(dodge_cooldown_ticks) * float(loadout.get("dodge_cooldown_scale", 1.0))))
	_dodge_iframe_ticks += int(loadout.get("dodge_iframe_add", 0))
	_kill_fragment_add = int(loadout.get("kill_fragment_add", 0))

	state = State.new()
	state.arena_size = Vector2(arena["width"], arena["height"])
	state.player_hp = player_max_hp

	var layout: Dictionary = _load_json(LAYOUT_PATH)
	var spawn: Dictionary = layout["player_spawn"]
	state.player_pos = Vector2(spawn["x"], spawn["y"])
	for entry: Dictionary in layout["blocks"]:
		var b := State.Block.new()
		b.pos = Vector2(entry["x"], entry["y"])
		b.size = Vector2(entry["w"], entry["h"])
		b.hp = block_max_hp
		state.blocks.append(b)


## Advance the simulation by exactly one tick. Once the player is down the
## world freezes; only the tick counter advances.
func step(cmd: SimCommand) -> void:
	if not state.player_down:
		_step_player(cmd)
		_step_projectiles()
		_schedule_waves()
		_schedule_events()
		_step_spawns()
		_step_enemies()
		_step_enemy_projectiles()
		_step_impacts()
		_cull_dead_enemies()
	state.tick += 1


func _step_player(cmd: SimCommand) -> void:
	var move := cmd.move
	if move.length_squared() > 1.0:
		move = move.normalized()

	if cmd.aim != Vector2.ZERO:
		state.player_aim = cmd.aim.normalized()

	if state.iframe_ticks > 0:
		state.iframe_ticks -= 1
	if state.dodge_cooldown > 0:
		state.dodge_cooldown -= 1
	if cmd.dodge and state.dodge_cooldown == 0:
		var dir := move if move != Vector2.ZERO else state.player_aim
		state.dodge_vel = dir.normalized() * _dodge_impulse
		state.dodge_cooldown = dodge_cooldown_ticks
		state.iframe_ticks = _dodge_iframe_ticks

	state.player_vel = move * _player_speed + state.dodge_vel
	state.player_pos += state.player_vel * DT * _crater_factor(state.player_pos)
	state.dodge_vel *= _dodge_decay
	if state.dodge_vel.length_squared() < 1.0:
		state.dodge_vel = Vector2.ZERO

	state.player_pos.x = clampf(
		state.player_pos.x, player_radius, state.arena_size.x - player_radius)
	state.player_pos.y = clampf(
		state.player_pos.y, player_radius, state.arena_size.y - player_radius)

	if state.fire_cooldown > 0:
		state.fire_cooldown -= 1
	if cmd.fire and state.fire_cooldown == 0:
		var p := State.Projectile.new()
		p.pos = state.player_pos + state.player_aim * _proj_spawn_offset
		p.vel = state.player_aim * _proj_speed
		p.ttl = _proj_ttl_ticks
		p.damage = _proj_damage
		state.projectiles.append(p)
		state.fire_cooldown = _fire_cooldown_ticks


func _step_projectiles() -> void:
	var survivors: Array[State.Projectile] = []
	for p: State.Projectile in state.projectiles:
		p.pos += p.vel * DT
		p.ttl -= 1
		if p.ttl <= 0 or _outside_arena(p.pos):
			continue
		var hit := false
		for e: State.Enemy in state.enemies:
			if e.hp > 0 and _circles_hit(p.pos, projectile_radius, e.pos, _stat_f(e.type, "radius")):
				e.hp -= p.damage
				hit = true
				break
		if not hit:
			for b: State.Block in state.blocks:
				if _circle_hits_aabb(p.pos, projectile_radius, b.pos, b.size):
					b.hp -= 1
					hit = true
					break
		if not hit:
			survivors.append(p)
	state.projectiles = survivors

	_settle_blocks()


## Queue the next wave onto the spawn list when its start tick arrives.
## Waves keep coming whether or not the last one is dead — the beach is
## unwinnable by design; pressure only escalates.
func _schedule_waves() -> void:
	var start_tick := _first_wave_tick + state.wave_index * _wave_interval_ticks
	if state.tick != start_tick:
		return
	var comp := _wave_composition(state.wave_index)
	var slot := 0
	for type: String in comp:
		for i in int(comp[type]):
			var s := State.PendingSpawn.new()
			s.tick = state.tick + slot * _trickle_interval_ticks
			s.type = type
			s.pos = Vector2(
				rng.randf_range(_spawn_edge_margin, state.arena_size.x - _spawn_edge_margin),
				_stat_f(type, "radius") + 2.0)
			state.pending_spawns.append(s)
			slot += 1
	state.wave_index += 1


## Authored waves first; past the end, escalate the last wave linearly.
func _wave_composition(index: int) -> Dictionary:
	if index < _waves.size():
		return _waves[index]
	var extra := index - _waves.size() + 1
	var comp := {}
	var last: Dictionary = _waves[_waves.size() - 1]
	for type: String in last:
		comp[type] = int(last[type]) + int(_escalation.get(type, 0)) * extra
	return comp


## Fire authored assault events whose tick has arrived, plus the recurring
## barrage cadence past the authored timeline. Event order in the data is
## chronological; event_index walks it exactly once per run.
func _schedule_events() -> void:
	while state.event_index < _events.size() \
			and int(_events[state.event_index]["tick"]) <= state.tick:
		_fire_event(_events[state.event_index])
		state.event_index += 1

	if not _recurring_barrage.is_empty():
		var start := int(_recurring_barrage["start_tick"])
		var interval := int(_recurring_barrage["interval_ticks"])
		if state.tick >= start and (state.tick - start) % interval == 0:
			var rounds := (state.tick - start) / interval
			var growth_every := int(_recurring_barrage.get("count_growth_every", 3))
			var count := int(_recurring_barrage["count"]) + rounds / growth_every
			_fire_barrage(count, _artillery["zone"])


func _fire_event(event: Dictionary) -> void:
	match String(event["kind"]):
		"barrage":
			_fire_barrage(int(event["count"]), event.get("zone", _artillery["zone"]))
		"flank":
			_fire_flank(String(event["edge"]), event["comp"])


## Schedule `count` shells over `zone`, staggered so the barrage rolls across
## the ground instead of landing as one stamp. Positions draw from the sim RNG
## at schedule time (same contract as wave spawn jitter).
func _fire_barrage(count: int, zone: Dictionary) -> void:
	var telegraph := int(_artillery["telegraph_ticks"])
	var stagger := int(_artillery["stagger_ticks"])
	for i in count:
		var imp := State.Impact.new()
		imp.pos = Vector2(
			rng.randf_range(float(zone["x"]), float(zone["x"]) + float(zone["w"])),
			rng.randf_range(float(zone["y"]), float(zone["y"]) + float(zone["h"])))
		imp.land_tick = state.tick + telegraph + i * stagger
		imp.radius = float(_artillery["radius"])
		imp.damage = int(_artillery["damage"])
		imp.crater_radius = float(_artillery["crater_radius"])
		state.pending_impacts.append(imp)


## A squad entering from a side edge at scripted ticks — spawn edges become
## data instead of "everything walks in from the sea".
func _fire_flank(edge: String, comp: Dictionary) -> void:
	var slot := 0
	for type: String in comp:
		for i in int(comp[type]):
			var radius := _stat_f(type, "radius")
			var s := State.PendingSpawn.new()
			s.tick = state.tick + slot * _trickle_interval_ticks
			s.type = type
			var x := radius + 4.0 if edge == "left" else state.arena_size.x - radius - 4.0
			s.pos = Vector2(x, rng.randf_range(140.0, state.arena_size.y * 0.6))
			state.pending_spawns.append(s)
			slot += 1


## Land every shell whose tick arrived: AoE damage to the player, enemies,
## and cover alike (artillery doesn't care whose side you're on), then leave
## a crater. Baiting the assault into its own barrage is intended play.
func _step_impacts() -> void:
	if state.pending_impacts.is_empty():
		return
	var remaining: Array[State.Impact] = []
	var hit_blocks := false
	for imp: State.Impact in state.pending_impacts:
		if imp.land_tick > state.tick:
			remaining.append(imp)
			continue
		if _circles_hit(imp.pos, imp.radius, state.player_pos, player_radius):
			_damage_player(imp.damage)
		for e: State.Enemy in state.enemies:
			if e.hp > 0 and _circles_hit(imp.pos, imp.radius, e.pos, _stat_f(e.type, "radius")):
				e.hp -= imp.damage
		var block_damage := int(_artillery["block_damage"])
		for b: State.Block in state.blocks:
			if _circle_hits_aabb(imp.pos, imp.radius, b.pos, b.size):
				b.hp -= block_damage
				hit_blocks = true
		var crater := State.Crater.new()
		crater.pos = imp.pos
		crater.radius = imp.crater_radius
		state.craters.append(crater)
		while state.craters.size() > _max_craters:
			state.craters.pop_front()
	state.pending_impacts = remaining
	if hit_blocks:
		_settle_blocks()


## Movement multiplier for ground movers standing in rough ground.
func _crater_factor(pos: Vector2) -> float:
	for c: State.Crater in state.craters:
		if pos.distance_squared_to(c.pos) <= c.radius * c.radius:
			return _crater_slow
	return 1.0


func _step_spawns() -> void:
	while not state.pending_spawns.is_empty() and state.pending_spawns[0].tick <= state.tick:
		var s: State.PendingSpawn = state.pending_spawns.pop_front()
		var e := State.Enemy.new()
		e.pos = s.pos
		e.type = s.type
		e.hp = _stat_i(s.type, "hp")
		e.fire_cooldown = _stat_i(s.type, "fire_cooldown_ticks")
		state.enemies.append(e)


func _step_enemies() -> void:
	for e: State.Enemy in state.enemies:
		var radius := _stat_f(e.type, "radius")
		var to_player := state.player_pos - e.pos
		var dist := to_player.length()
		var dir := to_player / dist if dist > 0.001 else Vector2.DOWN

		match e.phase:
			PHASE_WINDUP:
				_step_windup(e)
			PHASE_COMMIT:
				_step_commit(e)
			PHASE_RECOVER:
				e.vel = Vector2.ZERO
				e.phase_ticks -= 1
				if e.phase_ticks <= 0:
					e.phase = PHASE_ROAM
			_:
				_step_roam(e, dir, dist)
		var factor := 1.0
		if bool(enemy_types[e.type].get("ground", true)):
			factor = _crater_factor(e.pos)
		e.pos += e.vel * DT * factor

		_separate(e, radius)
		for b: State.Block in state.blocks:
			_push_out_of_block(e, radius, b)
		e.pos.x = clampf(e.pos.x, radius, state.arena_size.x - radius)
		e.pos.y = clampf(e.pos.y, -radius * 2.0, state.arena_size.y - radius)

		if e.contact_cooldown > 0:
			e.contact_cooldown -= 1
		elif _circles_hit(e.pos, radius, state.player_pos, player_radius):
			_damage_player(_stat_i(e.type, "contact_damage"))
			e.contact_cooldown = _stat_i(e.type, "contact_cooldown_ticks")


## Roaming: behavior-specific approach movement, plus watching for the moment
## to start an attack windup. fire_cooldown is the universal between-attacks
## timer and only runs down while roaming.
func _step_roam(e: State.Enemy, dir: Vector2, dist: float) -> void:
	if e.fire_cooldown > 0:
		e.fire_cooldown -= 1
	var speed := _stat_f(e.type, "speed")
	match _stat_s(e.type, "behavior"):
		"diver":
			e.vel = dir * speed
			if e.fire_cooldown == 0 and dist <= _stat_f(e.type, "dive_range"):
				_begin_windup(e, dir)
		"volley":
			var preferred := _stat_f(e.type, "preferred_range")
			var advance := 1.0
			if dist < preferred * 0.6:
				advance = -1.0
			elif dist <= preferred:
				advance = 0.0
			e.vel = dir * speed * advance
			if e.fire_cooldown == 0 and dist <= preferred * 1.15:
				# Lead the shot: lock aim at where the player will be if they
				# keep moving — standing still or changing course both work.
				var lead := float(_stat_i(e.type, "lead_ticks")) * DT
				var aim := state.player_pos + state.player_vel * lead - e.pos
				_begin_windup(e, aim.normalized() if aim.length() > 0.001 else dir)
		"slammer":
			e.vel = dir * speed
			if e.fire_cooldown == 0 and dist <= _stat_f(e.type, "slam_range"):
				_begin_windup(e, dir)
		_:
			e.vel = dir * speed


func _begin_windup(e: State.Enemy, dir: Vector2) -> void:
	e.phase = PHASE_WINDUP
	e.phase_ticks = _stat_i(e.type, "windup_ticks")
	e.attack_dir = dir
	e.vel = Vector2.ZERO


## Windup: rooted and telegraphing. When it expires the attack commits along
## the direction locked at windup start.
func _step_windup(e: State.Enemy) -> void:
	e.vel = Vector2.ZERO
	e.phase_ticks -= 1
	if e.phase_ticks > 0:
		return
	match _stat_s(e.type, "behavior"):
		"diver":
			e.phase = PHASE_COMMIT
			e.phase_ticks = _stat_i(e.type, "dive_ticks")
		"volley":
			e.phase = PHASE_COMMIT
			e.shots_left = _stat_i(e.type, "volley_shots")
			_fire_volley_shot(e)
		"slammer":
			_resolve_slam(e)


func _step_commit(e: State.Enemy) -> void:
	match _stat_s(e.type, "behavior"):
		"diver":
			e.vel = e.attack_dir * _stat_f(e.type, "dive_speed")
			e.phase_ticks -= 1
			if e.phase_ticks <= 0:
				_begin_recover(e)
		"volley":
			e.vel = Vector2.ZERO
			e.phase_ticks -= 1
			if e.phase_ticks <= 0:
				if e.shots_left > 0:
					_fire_volley_shot(e)
				else:
					_begin_recover(e)
		_:
			_begin_recover(e)


func _begin_recover(e: State.Enemy) -> void:
	e.phase = PHASE_RECOVER
	e.phase_ticks = _stat_i(e.type, "recover_ticks")
	e.fire_cooldown = _stat_i(e.type, "fire_cooldown_ticks")
	e.vel = Vector2.ZERO


## One volley round along the locked attack direction.
func _fire_volley_shot(e: State.Enemy) -> void:
	var radius := _stat_f(e.type, "radius")
	var p := State.Projectile.new()
	p.pos = e.pos + e.attack_dir * (radius + 6.0)
	p.vel = e.attack_dir * _stat_f(e.type, "proj_speed")
	p.ttl = _stat_i(e.type, "proj_ttl_ticks")
	p.damage = _stat_i(e.type, "proj_damage")
	state.enemy_projectiles.append(p)
	e.shots_left -= 1
	e.phase_ticks = _stat_i(e.type, "shot_gap_ticks")


## The slam lands the tick its windup ends: AoE damage + knockback to the
## player, and it shatters cover caught in the ring — the enemy edits the map.
func _resolve_slam(e: State.Enemy) -> void:
	var slam_radius := _stat_f(e.type, "slam_radius")
	if _circles_hit(e.pos, slam_radius, state.player_pos, player_radius):
		_damage_player(_stat_i(e.type, "slam_damage"))
		var push := state.player_pos - e.pos
		var push_dir := push.normalized() if push.length() > 0.001 else Vector2.DOWN
		state.dodge_vel += push_dir * _stat_f(e.type, "slam_knockback")
	var block_damage := _stat_i(e.type, "slam_block_damage")
	for b: State.Block in state.blocks:
		if _circle_hits_aabb(e.pos, slam_radius, b.pos, b.size):
			b.hp -= block_damage
	_settle_blocks()
	_begin_recover(e)


## Pairwise push-apart so enemies read as a mob, not a stack.
func _separate(e: State.Enemy, radius: float) -> void:
	for other: State.Enemy in state.enemies:
		if other == e:
			continue
		var r := radius + _stat_f(other.type, "radius")
		var delta := e.pos - other.pos
		var d2 := delta.length_squared()
		if d2 > 0.0001 and d2 < r * r:
			var d := sqrt(d2)
			e.pos += (delta / d) * (r - d) * 0.5


func _push_out_of_block(e: State.Enemy, radius: float, b: State.Block) -> void:
	var closest := Vector2(
		clampf(e.pos.x, b.pos.x, b.pos.x + b.size.x),
		clampf(e.pos.y, b.pos.y, b.pos.y + b.size.y),
	)
	var delta := e.pos - closest
	var d2 := delta.length_squared()
	if d2 >= radius * radius:
		return
	if d2 > 0.0001:
		var d := sqrt(d2)
		e.pos += (delta / d) * (radius - d)
	else:
		e.pos.y = b.pos.y + b.size.y + radius  # degenerate: eject downfield


func _step_enemy_projectiles() -> void:
	var survivors: Array[State.Projectile] = []
	for p: State.Projectile in state.enemy_projectiles:
		p.pos += p.vel * DT
		p.ttl -= 1
		if p.ttl <= 0 or _outside_arena(p.pos):
			continue
		var hit := false
		for b: State.Block in state.blocks:
			if _circle_hits_aabb(p.pos, projectile_radius, b.pos, b.size):
				b.hp -= 1
				hit = true
				break
		if not hit and _circles_hit(p.pos, projectile_radius, state.player_pos, player_radius):
			_damage_player(p.damage)
			hit = true
		if not hit:
			survivors.append(p)
	state.enemy_projectiles = survivors

	_settle_blocks()


## Sweep destroyed blocks and bank their fragments. Called after anything
## that can damage blocks (projectiles, enemy fire, slams).
func _settle_blocks() -> void:
	var standing: Array[State.Block] = []
	for b: State.Block in state.blocks:
		if b.hp > 0:
			standing.append(b)
		else:
			state.fragments += 1
	state.blocks = standing


func _cull_dead_enemies() -> void:
	var alive: Array[State.Enemy] = []
	for e: State.Enemy in state.enemies:
		if e.hp > 0:
			alive.append(e)
		else:
			state.kills += 1
			state.fragments += _stat_i(e.type, "fragments") + _kill_fragment_add
	state.enemies = alive


func _damage_player(amount: int) -> void:
	if state.iframe_ticks > 0 or state.player_down:
		return
	state.player_hp -= amount
	if state.player_hp <= 0:
		state.player_hp = 0
		state.player_down = true


func _stat_f(type: String, key: String) -> float:
	return enemy_types[type][key]


func _stat_i(type: String, key: String) -> int:
	return int(enemy_types[type][key])


func _stat_s(type: String, key: String) -> String:
	return String(enemy_types[type][key])


func _outside_arena(pos: Vector2) -> bool:
	return (
		pos.x < -projectile_radius or pos.y < -projectile_radius
		or pos.x > state.arena_size.x + projectile_radius
		or pos.y > state.arena_size.y + projectile_radius
	)


func _circles_hit(a: Vector2, a_radius: float, b: Vector2, b_radius: float) -> bool:
	var r := a_radius + b_radius
	return a.distance_squared_to(b) <= r * r


func _circle_hits_aabb(
	center: Vector2, radius: float, aabb_pos: Vector2, aabb_size: Vector2
) -> bool:
	var closest := Vector2(
		clampf(center.x, aabb_pos.x, aabb_pos.x + aabb_size.x),
		clampf(center.y, aabb_pos.y, aabb_pos.y + aabb_size.y),
	)
	return center.distance_squared_to(closest) <= radius * radius


func _load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "Missing data file: " + path)
	return JSON.parse_string(text)
