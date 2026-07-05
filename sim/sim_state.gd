class_name SimState
extends RefCounted
## Complete simulation state. Plain data; only SimCore mutates it.
## serialize() has a stable field order — it defines the determinism contract.

class Projectile extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var ttl: int = 0
	var damage: int = 0

class Block extends RefCounted:
	var pos: Vector2 = Vector2.ZERO  # top-left corner
	var size: Vector2 = Vector2.ZERO
	var hp: int = 0

class Enemy extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var hp: int = 0
	var type: String = ""
	var fire_cooldown: int = 0
	var contact_cooldown: int = 0

class PendingSpawn extends RefCounted:
	var tick: int = 0
	var type: String = ""
	var pos: Vector2 = Vector2.ZERO

var tick: int = 0

var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.ZERO
var player_aim: Vector2 = Vector2.RIGHT
var player_hp: int = 0
var dodge_vel: Vector2 = Vector2.ZERO
var dodge_cooldown: int = 0
var fire_cooldown: int = 0
## Ticks of dodge invulnerability remaining.
var iframe_ticks: int = 0
## True once player_hp hit 0; the sim freezes (only tick advances).
var player_down: bool = false

## Data fragments earned this run (blocks + enemy kills).
var fragments: int = 0
var kills: int = 0
## Next wave to be scheduled.
var wave_index: int = 0

var projectiles: Array[Projectile] = []
var blocks: Array[Block] = []
var enemies: Array[Enemy] = []
var enemy_projectiles: Array[Projectile] = []
var pending_spawns: Array[PendingSpawn] = []

var arena_size: Vector2 = Vector2.ZERO


func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	_put_vec2(buf, player_pos)
	_put_vec2(buf, player_vel)
	_put_vec2(buf, player_aim)
	buf.put_32(player_hp)
	_put_vec2(buf, dodge_vel)
	buf.put_32(dodge_cooldown)
	buf.put_32(fire_cooldown)
	buf.put_32(iframe_ticks)
	buf.put_32(1 if player_down else 0)
	buf.put_32(fragments)
	buf.put_32(kills)
	buf.put_32(wave_index)
	buf.put_u32(projectiles.size())
	for p: Projectile in projectiles:
		_put_projectile(buf, p)
	buf.put_u32(blocks.size())
	for b: Block in blocks:
		_put_vec2(buf, b.pos)
		_put_vec2(buf, b.size)
		buf.put_32(b.hp)
	buf.put_u32(enemies.size())
	for e: Enemy in enemies:
		_put_vec2(buf, e.pos)
		_put_vec2(buf, e.vel)
		buf.put_32(e.hp)
		buf.put_utf8_string(e.type)
		buf.put_32(e.fire_cooldown)
		buf.put_32(e.contact_cooldown)
	buf.put_u32(enemy_projectiles.size())
	for p: Projectile in enemy_projectiles:
		_put_projectile(buf, p)
	buf.put_u32(pending_spawns.size())
	for s: PendingSpawn in pending_spawns:
		buf.put_32(s.tick)
		buf.put_utf8_string(s.type)
		_put_vec2(buf, s.pos)
	_put_vec2(buf, arena_size)
	return buf.data_array


func state_hash() -> int:
	return hash(serialize())


func _put_projectile(buf: StreamPeerBuffer, p: Projectile) -> void:
	_put_vec2(buf, p.pos)
	_put_vec2(buf, p.vel)
	buf.put_32(p.ttl)
	buf.put_32(p.damage)


func _put_vec2(buf: StreamPeerBuffer, v: Vector2) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
