class_name SimState
extends RefCounted
## Complete simulation state. Plain data; only SimCore mutates it.
## serialize() has a stable field order — it defines the determinism contract.

class Projectile extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var ttl: int = 0

class Block extends RefCounted:
	var pos: Vector2 = Vector2.ZERO  # top-left corner
	var size: Vector2 = Vector2.ZERO
	var hp: int = 0

var tick: int = 0

var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.ZERO
var player_aim: Vector2 = Vector2.RIGHT
var player_hp: int = 0
var dodge_vel: Vector2 = Vector2.ZERO
var dodge_cooldown: int = 0
var fire_cooldown: int = 0

var projectiles: Array[Projectile] = []
var blocks: Array[Block] = []

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
	buf.put_u32(projectiles.size())
	for p: Projectile in projectiles:
		_put_vec2(buf, p.pos)
		_put_vec2(buf, p.vel)
		buf.put_32(p.ttl)
	buf.put_u32(blocks.size())
	for b: Block in blocks:
		_put_vec2(buf, b.pos)
		_put_vec2(buf, b.size)
		buf.put_32(b.hp)
	_put_vec2(buf, arena_size)
	return buf.data_array


func state_hash() -> int:
	return hash(serialize())


func _put_vec2(buf: StreamPeerBuffer, v: Vector2) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
