class_name SimCore
extends RefCounted
## Deterministic simulation. Advances only via step(), one 1/60s tick at a
## time. All randomness must go through `rng` (the only RNG); no wall-clock,
## no engine physics, no scene tree. A run is reproducible from
## (seed, command log).

const SimCommand := preload("res://sim/command.gd")
const State := preload("res://sim/sim_state.gd")

const TICKS_PER_SECOND: int = 60
const DT: float = 1.0 / 60.0

const TUNING_PATH := "res://content/tuning.json"
const LAYOUT_PATH := "res://content/block_layout.json"

var state: State
var rng: RandomNumberGenerator

# Tuning values, loaded from content/tuning.json in setup().
var player_radius: float
var _player_speed: float
var _player_max_hp: int
var _dodge_impulse: float
var _dodge_decay: float
var _dodge_cooldown_ticks: int
var projectile_radius: float
var _proj_speed: float
var _proj_ttl_ticks: int
var _fire_cooldown_ticks: int
var _proj_spawn_offset: float
var _block_hp: int


func setup(seed_value: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	var tuning: Dictionary = _load_json(TUNING_PATH)
	var player: Dictionary = tuning["player"]
	var projectile: Dictionary = tuning["projectile"]
	var block: Dictionary = tuning["block"]
	var arena: Dictionary = tuning["arena"]

	player_radius = player["radius"]
	_player_speed = player["speed"]
	_player_max_hp = int(player["max_hp"])
	_dodge_impulse = player["dodge_impulse"]
	_dodge_decay = player["dodge_decay"]
	_dodge_cooldown_ticks = int(player["dodge_cooldown_ticks"])
	projectile_radius = projectile["radius"]
	_proj_speed = projectile["speed"]
	_proj_ttl_ticks = int(projectile["ttl_ticks"])
	_fire_cooldown_ticks = int(projectile["fire_cooldown_ticks"])
	_proj_spawn_offset = projectile["spawn_offset"]
	_block_hp = int(block["hp"])

	state = State.new()
	state.arena_size = Vector2(arena["width"], arena["height"])
	state.player_pos = state.arena_size * 0.5
	state.player_hp = _player_max_hp

	var layout: Array = _load_json(LAYOUT_PATH)["blocks"]
	for entry: Dictionary in layout:
		var b := State.Block.new()
		b.pos = Vector2(entry["x"], entry["y"])
		b.size = Vector2(entry["w"], entry["h"])
		b.hp = _block_hp
		state.blocks.append(b)


## Advance the simulation by exactly one tick.
func step(cmd: SimCommand) -> void:
	_step_player(cmd)
	_step_projectiles()
	state.tick += 1


func _step_player(cmd: SimCommand) -> void:
	var move := cmd.move
	if move.length_squared() > 1.0:
		move = move.normalized()

	if cmd.aim != Vector2.ZERO:
		state.player_aim = cmd.aim.normalized()

	if state.dodge_cooldown > 0:
		state.dodge_cooldown -= 1
	if cmd.dodge and state.dodge_cooldown == 0:
		var dir := move if move != Vector2.ZERO else state.player_aim
		state.dodge_vel = dir.normalized() * _dodge_impulse
		state.dodge_cooldown = _dodge_cooldown_ticks

	state.player_vel = move * _player_speed + state.dodge_vel
	state.player_pos += state.player_vel * DT
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
		for b: State.Block in state.blocks:
			if _circle_hits_aabb(p.pos, projectile_radius, b.pos, b.size):
				b.hp -= 1
				hit = true
				break
		if not hit:
			survivors.append(p)
	state.projectiles = survivors

	var standing: Array[State.Block] = []
	for b: State.Block in state.blocks:
		if b.hp > 0:
			standing.append(b)
	state.blocks = standing


func _outside_arena(pos: Vector2) -> bool:
	return (
		pos.x < -projectile_radius or pos.y < -projectile_radius
		or pos.x > state.arena_size.x + projectile_radius
		or pos.y > state.arena_size.y + projectile_radius
	)


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
